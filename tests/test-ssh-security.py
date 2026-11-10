#!/usr/bin/env python3
"""Behavioral regression tests for ssh_security socket/listener validation.

These tests exercise the exact parser functions and the exact Jinja2 expressions
and templates used by the role, rather than grepping task text. They cover:

* prefix-port false matches (2222 must never match 22222);
* non-SSH systemd sockets and overridden vendor units;
* exact TCP/Stream protocol, address-family and listener-endpoint matching;
* trusted process ownership: systemd must be PID 1, sshd must resolve to a real
  sshd executable via /proc/<pid>/exe and must not share the socket with an
  unrelated co-owner;
* spoofed process names (fake systemd PID, sshd with a suspicious exe path);
* mixed IPv4/IPv6 listeners where one family is SSH and another is not;
* single- and dual-stack socket template rendering.

The test depends on Jinja2 and PyYAML (hard dependencies of ansible-core, which
this project's gate already requires). If either is unavailable the import
fails and the test exits non-zero, reporting that the template/expression
coverage did not run rather than silently passing.

Run with a Jinja2-capable Python (for example the Homebrew ansible-core
interpreter, or via ``uv run --with ansible-core==2.21.4``):
    python3 tests/test-ssh-security.py
"""

from __future__ import annotations

import base64
import importlib.util
import sys
import types
import yaml
from pathlib import Path

from jinja2 import Environment, StrictUndefined


ROOT_DIR = Path(__file__).resolve().parent.parent
ROLE_DIR = ROOT_DIR / "ansible" / "roles" / "ssh_security"


def _load_filters():
    path = ROLE_DIR / "filter_plugins" / "ssh_security.py"
    spec = importlib.util.spec_from_file_location("ssh_security_filters", str(path))
    module = importlib.util.module_from_spec(spec)
    sys.modules["ssh_security_filters"] = module
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


mod = _load_filters()
Endpoint = mod.Endpoint
Process = mod.Process
parse_addr_port = mod.parse_addr_port
parse_listen_stream_endpoints = mod.parse_listen_stream_endpoints
parse_ss_lines = mod.parse_ss_lines
parse_exe_probe = mod.parse_exe_probe
ssh_port_is_free_or_owned = mod.ssh_port_is_free_or_owned
ssh_security_listen_matches = mod.ssh_security_listen_matches
ssh_security_is_managed_socket_dropin = mod.ssh_security_is_managed_socket_dropin


CONFIGURE_TASKS = yaml.safe_load((ROLE_DIR / "tasks" / "configure.yml").read_text())
MAIN_TASKS = yaml.safe_load((ROLE_DIR / "tasks" / "main.yml").read_text())


def _task_module(task, keys):
    """Return the module dict for a task keyed by one of ``keys``, else None."""
    for key in keys:
        value = task.get(key)
        if isinstance(value, dict):
            return value
    return None


def _socket_override_dest_basename() -> str:
    """Read the managed socket drop-in name from the real configure.yml task."""
    for task in CONFIGURE_TASKS:
        mod = _task_module(task, ("ansible.builtin.template", "template"))
        if mod is not None and mod.get("src") == "ssh.socket-override.conf.j2":
            dest = mod.get("dest")
            if not dest:
                raise AssertionError("socket override template task has no dest")
            return Path(dest).name
    raise AssertionError(
        "socket override template task (src=ssh.socket-override.conf.j2) not found"
    )


def _set_fact_value(tasks, fact_name) -> str:
    """Return the raw set_fact expression for ``fact_name``."""
    for task in tasks:
        mod = _task_module(task, ("ansible.builtin.set_fact", "set_fact"))
        if mod is not None and fact_name in mod:
            return mod[fact_name]
    raise AssertionError(f"set_fact {fact_name!r} not found")


def _assert_conditions(tasks, needle) -> list[str]:
    """Return the ``that`` list of the assert task whose text contains ``needle``."""
    for task in tasks:
        mod = _task_module(task, ("ansible.builtin.assert", "assert"))
        if mod is None:
            continue
        that = mod.get("that")
        if isinstance(that, list) and any(needle in str(item) for item in that):
            return [str(item) for item in that]
    raise AssertionError(f"assert condition containing {needle!r} not found")


SOCKET_OVERRIDE_BASENAME = _socket_override_dest_basename()
MARKER_EXPRESSION = _set_fact_value(CONFIGURE_TASKS, "ssh_legacy_socket_dropin_is_managed")
IPV6_EXPRESSION = _set_fact_value(CONFIGURE_TASKS, "ssh_ipv6_available")
EFFECTIVE_LISTEN_CONDITIONS = _assert_conditions(CONFIGURE_TASKS, "ssh_security_listen_matches")
PORT_ASSERT_EXPRESSION = _assert_conditions(
    MAIN_TASKS, "ssh_security_port_is_free_or_owned"
)[0]


def _ansible_bool(value) -> bool:
    """Mirror Ansible's ``bool`` filter for the plain-Jinja2 test harness."""
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    return str(value).strip().lower() in ("true", "yes", "on", "1")


# --- Realistic ``ss -ltnp --no-header`` output (columns include the process pid) ---

SS_TRADITIONAL_SSHD = """\
LISTEN 0      128          0.0.0.0:22        0.0.0.0:*    users:(("sshd",pid=640,fd=3))
LISTEN 0      128             [::]:22           [::]:*    users:(("sshd",pid=640,fd=4))
"""

# Ubuntu 24.04 socket activation: systemd (pid 1) and sshd hold the fd together.
SS_SOCKET_ACTIVATED = """\
LISTEN 0      128          0.0.0.0:22        0.0.0.0:*    users:(("systemd",pid=1,fd=56),("sshd",pid=1234,fd=3))
LISTEN 0      128             [::]:22           [::]:*    users:(("systemd",pid=1,fd=57),("sshd",pid=1234,fd=4))
"""

SS_PURE_SYSTEMD = """\
LISTEN 0      128          0.0.0.0:22        0.0.0.0:*    users:(("systemd",pid=1,fd=56))
"""

# A spoofed "systemd" name that is not PID 1.
SS_SYSTEMD_FAKE_PID = """\
LISTEN 0      128          0.0.0.0:2222       0.0.0.0:*    users:(("systemd",pid=999,fd=56))
"""

# sshd and an unrelated co-owner on the same socket line.
SS_SSHD_NGINX_SAME_LINE = """\
LISTEN 0      128          0.0.0.0:2222       0.0.0.0:*    users:(("sshd",pid=640,fd=3),("nginx",pid=999,fd=6))
"""

# Real listener is IPv4 loopback but effective Listen is IPv6 wildcard.
SS_SYSTEMD_WRONG_FAMILY = """\
LISTEN 0      128          127.0.0.1:2222     0.0.0.0:*    users:(("systemd",pid=1,fd=56))
"""

# A listener on the port whose effective Listen entry is Datagram (not Stream).
SS_SYSTEMD_DGRAM_PORT = """\
LISTEN 0      128          0.0.0.0:2222       0.0.0.0:*    users:(("systemd",pid=1,fd=56))
"""

# Same port, two address families, one SSH and one unrelated service.
SS_MIXED_SSHD_NGINX = """\
LISTEN 0      128          0.0.0.0:2222       0.0.0.0:*    users:(("sshd",pid=640,fd=3))
LISTEN 0      511             [::]:2222          [::]:*    users:(("nginx",pid=1234,fd=6))
"""

SS_NGINX_2222 = """\
LISTEN 0      511          0.0.0.0:2222       0.0.0.0:*    users:(("nginx",pid=1234,fd=6))
"""

# A listener on a different port that shares a numeric prefix (22222 vs 2222).
SS_PREFIX_COLLISION = """\
LISTEN 0      128          0.0.0.0:22222      0.0.0.0:*    users:(("nginx",pid=1234,fd=6))
"""

# An sshd name whose executable resolves to a suspicious path.
SS_SPOOFED_SSHD_EXE = """\
LISTEN 0      128          0.0.0.0:2222       0.0.0.0:*    users:(("sshd",pid=640,fd=3))
"""

# A valid sshd owner plus a spoofed owner whose name contains an escaped quote.
# The old findall-based parser silently dropped the malformed owner; the new
# parser must reject the whole line instead.
SS_SSHD_UNKNOWN_ESCAPED_OWNER = """\
LISTEN 0      128          0.0.0.0:2222       0.0.0.0:*    users:(("sshd",pid=640,fd=3),("unknown\\\"process",pid=556,fd=4))
"""

# A valid sshd owner followed by a structurally malformed owner.
SS_SSHD_MALFORMED_OWNER = """\
LISTEN 0      128          0.0.0.0:2222       0.0.0.0:*    users:(("sshd",pid=640,fd=3),garbage)
"""

# Two listeners on the exact same endpoint (SO_REUSEPORT ambiguity).
SS_DUPLICATE_ENDPOINT = """\
LISTEN 0      128          0.0.0.0:2222       0.0.0.0:*    users:(("systemd",pid=1,fd=56))
LISTEN 0      128          0.0.0.0:2222       0.0.0.0:*    users:(("systemd",pid=1,fd=57))
"""

LISTEN_DUALSTACK_22 = "0.0.0.0:22 (Stream)\n[::]:22 (Stream)"
EXE_SSHD = "640=/usr/sbin/sshd"
EXE_SYSTEMD = "1=/usr/lib/systemd/systemd"
EXE_SOCKET = "1=/usr/lib/systemd/systemd\n1234=/usr/sbin/sshd"


def test_parse_addr_port() -> None:
    assert parse_addr_port("0.0.0.0:22") == Endpoint("ipv4", "0.0.0.0", 22)
    assert parse_addr_port("[::]:22") == Endpoint("ipv6", "::", 22)
    assert parse_addr_port("127.0.0.1:2222") == Endpoint("ipv4", "127.0.0.1", 2222)
    assert parse_addr_port("[2001:db8::1]:2222") == Endpoint("ipv6", "2001:db8::1", 2222)
    assert parse_addr_port("2222") is None
    assert parse_addr_port("22 (Stream)") is None


def test_parse_listen_stream_endpoints() -> None:
    assert parse_listen_stream_endpoints(LISTEN_DUALSTACK_22) == {
        Endpoint("ipv4", "0.0.0.0", 22),
        Endpoint("ipv6", "::", 22),
    }
    assert parse_listen_stream_endpoints("0.0.0.0:2222 (Datagram)") == set()
    assert parse_listen_stream_endpoints("127.0.0.1:2222 (Stream)") == {
        Endpoint("ipv4", "127.0.0.1", 2222)
    }
    # A bare port (not address:port) is not a real `systemctl show --value`
    # output shape, so it must fail closed rather than be guessed.
    assert parse_listen_stream_endpoints("ListenStream=2222 (Stream)") is None
    assert parse_listen_stream_endpoints("not an endpoint (Stream)") is None
    assert parse_listen_stream_endpoints("") == set()
    assert parse_listen_stream_endpoints(None) == set()


def test_parse_exe_probe() -> None:
    assert parse_exe_probe("640=/usr/sbin/sshd\n1=/usr/lib/systemd/systemd") == {
        640: "/usr/sbin/sshd",
        1: "/usr/lib/systemd/systemd",
    }
    assert parse_exe_probe("garbage") is None
    assert parse_exe_probe("") == {}
    assert parse_exe_probe(None) == {}


def test_parse_ss_lines() -> None:
    lines = parse_ss_lines(SS_TRADITIONAL_SSHD, 22)
    assert lines is not None and len(lines) == 2
    assert lines[0].endpoint == Endpoint("ipv4", "0.0.0.0", 22)
    assert lines[0].processes == (Process("sshd", 640),)
    assert lines[1].endpoint == Endpoint("ipv6", "::", 22)

    socket_lines = parse_ss_lines(SS_SOCKET_ACTIVATED, 22)
    assert socket_lines is not None and socket_lines[0].processes == (
        Process("systemd", 1),
        Process("sshd", 1234),
    )

    # Prefix collision: target 2222 but only 22222 is present -> no lines.
    assert parse_ss_lines(SS_PREFIX_COLLISION, 2222) == []

    # Escaped-quote owner must be fully consumed, not silently dropped.
    escaped = parse_ss_lines(SS_SSHD_UNKNOWN_ESCAPED_OWNER, 2222)
    assert escaped is not None and len(escaped) == 1
    assert escaped[0].processes == (
        Process("sshd", 640),
        Process('unknown\\"process', 556),
    )

    # Structurally malformed owner -> fail closed (None).
    assert parse_ss_lines(SS_SSHD_MALFORMED_OWNER, 2222) is None

    # Missing process info -> fail closed (None).
    assert parse_ss_lines("LISTEN 0 128 0.0.0.0:22 0.0.0.0:*\n", 22) is None


def test_port_ownership() -> None:
    # Port free.
    assert ssh_port_is_free_or_owned("", 2222, "inactive", "", "") is True

    # Traditional sshd (exe-verified).
    assert (
        ssh_port_is_free_or_owned(SS_TRADITIONAL_SSHD, 22, "inactive", "", EXE_SSHD)
        is True
    )

    # Socket-activated sshd+systemd is SSH-owned.
    assert (
        ssh_port_is_free_or_owned(
            SS_SOCKET_ACTIVATED, 22, "active", LISTEN_DUALSTACK_22, EXE_SOCKET
        )
        is True
    )

    # Pure systemd PID 1 with a matching effective endpoint is SSH-owned.
    assert (
        ssh_port_is_free_or_owned(
            SS_PURE_SYSTEMD, 22, "active", LISTEN_DUALSTACK_22, EXE_SYSTEMD
        )
        is True
    )

    # systemd PID 1 but ssh.socket is not active -> refuse (not socket activation).
    assert (
        ssh_port_is_free_or_owned(
            SS_PURE_SYSTEMD, 22, "inactive", LISTEN_DUALSTACK_22, EXE_SYSTEMD
        )
        is False
    )

    # A: spoofed systemd name, not PID 1 -> refuse.
    assert (
        ssh_port_is_free_or_owned(
            SS_SYSTEMD_FAKE_PID,
            2222,
            "active",
            "0.0.0.0:2222 (Stream)",
            "999=/usr/lib/systemd/systemd",
        )
        is False
    )

    # B: sshd plus an unrelated co-owner on the same line -> refuse.
    assert (
        ssh_port_is_free_or_owned(
            SS_SSHD_NGINX_SAME_LINE,
            2222,
            "active",
            "0.0.0.0:2222 (Stream)",
            "640=/usr/sbin/sshd\n999=/usr/sbin/nginx",
        )
        is False
    )

    # C: real endpoint is IPv4 loopback but effective Listen is IPv6 -> refuse.
    assert (
        ssh_port_is_free_or_owned(
            SS_SYSTEMD_WRONG_FAMILY,
            2222,
            "active",
            "[::]:2222 (Stream)",
            EXE_SYSTEMD,
        )
        is False
    )

    # D: effective Listen is Datagram, not Stream -> refuse.
    assert (
        ssh_port_is_free_or_owned(
            SS_SYSTEMD_DGRAM_PORT,
            2222,
            "active",
            "0.0.0.0:2222 (Datagram)",
            EXE_SYSTEMD,
        )
        is False
    )

    # Mixed IPv4/IPv6: one family is sshd, the other nginx -> refuse.
    assert (
        ssh_port_is_free_or_owned(
            SS_MIXED_SSHD_NGINX,
            2222,
            "inactive",
            "",
            "640=/usr/sbin/sshd\n1234=/usr/sbin/nginx",
        )
        is False
    )

    # Non-SSH service on the port -> refuse.
    assert (
        ssh_port_is_free_or_owned(
            SS_NGINX_2222, 2222, "inactive", "", "1234=/usr/sbin/nginx"
        )
        is False
    )

    # Prefix collision: a listener on 22222 must not occupy 2222 -> free.
    assert ssh_port_is_free_or_owned(SS_PREFIX_COLLISION, 2222, "inactive", "", "") is True

    # Missing exe probe -> cannot positively confirm sshd -> refuse.
    assert ssh_port_is_free_or_owned(SS_TRADITIONAL_SSHD, 22, "inactive", "", "") is False

    # Suspicious sshd exe path -> refuse.
    assert (
        ssh_port_is_free_or_owned(
            SS_SPOOFED_SSHD_EXE, 2222, "inactive", "", "640=/tmp/sshd"
        )
        is False
    )

    # sshd exe at a user-writable non-canonical path (e.g. /opt/...) -> refuse.
    assert (
        ssh_port_is_free_or_owned(
            SS_SPOOFED_SSHD_EXE, 2222, "inactive", "", "640=/opt/user-controlled/sshd"
        )
        is False
    )

    # systemd exe at a non-canonical path -> refuse (only system paths accepted).
    assert (
        ssh_port_is_free_or_owned(
            SS_PURE_SYSTEMD, 22, "active", LISTEN_DUALSTACK_22, "1=/opt/systemd"
        )
        is False
    )

    # usr-merge / non-merged aliases are still accepted.
    assert (
        ssh_port_is_free_or_owned(
            SS_TRADITIONAL_SSHD, 22, "inactive", "", "640=/sbin/sshd"
        )
        is True
    )
    assert (
        ssh_port_is_free_or_owned(
            SS_PURE_SYSTEMD, 22, "active", LISTEN_DUALSTACK_22, "1=/lib/systemd/systemd"
        )
        is True
    )

    # Escaped-quote spoofed owner on the same line as sshd -> refuse (was
    # silently dropped by the old findall parser).
    assert (
        ssh_port_is_free_or_owned(
            SS_SSHD_UNKNOWN_ESCAPED_OWNER,
            2222,
            "inactive",
            "",
            "640=/usr/sbin/sshd\n556=/opt/x",
        )
        is False
    )

    # Structurally malformed owner -> refuse rather than partial accept.
    assert (
        ssh_port_is_free_or_owned(
            SS_SSHD_MALFORMED_OWNER, 2222, "inactive", "", "640=/usr/sbin/sshd"
        )
        is False
    )

    # Duplicate same-endpoint listeners are ambiguous -> refuse.
    assert (
        ssh_port_is_free_or_owned(
            SS_DUPLICATE_ENDPOINT,
            2222,
            "active",
            "0.0.0.0:2222 (Stream)",
            EXE_SYSTEMD,
        )
        is False
    )

    # Unparseable ss line -> fail closed.
    assert (
        ssh_port_is_free_or_owned(
            "LISTEN 0 128 0.0.0.0:22 0.0.0.0:*\n", 22, "inactive", "", ""
        )
        is False
    )


def test_actual_assert_expression() -> None:
    """Render the exact port-ownership assert expression from tasks/main.yml."""
    filters = mod.FilterModule().filters()
    assert "ssh_security_port_is_free_or_owned" in filters
    assert "ssh_security_listen_stream_ports" in filters

    env = Environment(undefined=StrictUndefined)
    env.filters.update(filters)
    env.filters["bool"] = _ansible_bool
    expression = PORT_ASSERT_EXPRESSION
    template = env.from_string("{{ " + expression + " }}")

    def render(ss_out, port, socket_state, listen, exe_probe):
        context = {
            "ssh_desired_port_listener": types.SimpleNamespace(stdout=ss_out),
            "ssh_port": port,
            "ssh_prepare_socket_state": types.SimpleNamespace(stdout=socket_state),
            "ssh_prepare_socket_listenstream": types.SimpleNamespace(stdout=listen),
            "ssh_listener_exe_probe": types.SimpleNamespace(stdout=exe_probe),
        }
        return template.render(**context)

    assert (
        render(SS_NGINX_2222, 2222, "inactive", "", "1234=/usr/sbin/nginx") == "False"
    )
    assert render("", 2222, "inactive", "", "") == "True"
    assert (
        render(SS_SOCKET_ACTIVATED, 22, "active", LISTEN_DUALSTACK_22, EXE_SOCKET)
        == "True"
    )
    assert render(SS_PREFIX_COLLISION, 2222, "inactive", "", "") == "True"


def test_ipv6_available_expression() -> None:
    """Render the exact set_fact expression from tasks/configure.yml."""
    env = Environment(undefined=StrictUndefined)
    env.filters["bool"] = _ansible_bool
    template = env.from_string(IPV6_EXPRESSION)

    def render(rc, stdout):
        context = {
            "ssh_ipv6_bind_probe": types.SimpleNamespace(rc=rc, stdout=stdout),
        }
        return template.render(**context)

    # Available: probe succeeded and printed exactly "ok".
    assert render(0, "ok\n") == "True"
    # Disabled / bind failed: non-zero rc.
    assert render(1, "") == "False"
    # Probe failed: rc 0 but unexpected output must not be trusted.
    assert render(0, "") == "False"
    assert render(0, "error") == "False"


def _rendered_listeners(ports, ipv6_available):
    template_path = ROLE_DIR / "templates" / "ssh.socket-override.conf.j2"
    source = template_path.read_text()
    env = Environment(undefined=StrictUndefined)
    env.filters["bool"] = _ansible_bool
    rendered = env.from_string(source).render(
        ssh_listener_ports=ports, ssh_ipv6_available=ipv6_available
    )
    listeners = []
    for line in rendered.splitlines():
        if line.startswith("ListenStream="):
            value = line.split("=", 1)[1]
            if value:
                listeners.append(value)
            else:
                listeners.clear()
    return rendered, listeners


def test_socket_template() -> None:
    # Dual-stack: both families bound for each unique port.
    rendered, listeners = _rendered_listeners([22, 2222, 22], True)
    expected = [
        addr + str(port)
        for port in (22, 2222)
        for addr in ("0.0.0.0:", "[::]:")
    ]
    assert listeners == expected, listeners
    assert "BindIPv6Only=ipv6-only" in rendered

    # Single stack (IPv6 unavailable): only IPv4 listeners, never [::].
    rendered, listeners = _rendered_listeners([22, 2222], False)
    assert listeners == ["0.0.0.0:22", "0.0.0.0:2222"], listeners
    assert "[::]:" not in rendered
    assert "BindIPv6Only=ipv6-only" in rendered


VENDOR_SSH_SOCKET = """\
[Socket]
ListenStream=0.0.0.0:22
ListenStream=[::]:22
BindIPv6Only=ipv6-only
FreeBind=yes
"""

# Representative openssh sshd-socket-generator output on Ubuntu 24.04.
ADDRESSES_CONF = """\
[Socket]
ListenStream=
ListenStream=0.0.0.0:22
ListenStream=[::]:22
"""


def _render_socket_override(ports, ipv6_available):
    template_path = ROLE_DIR / "templates" / "ssh.socket-override.conf.j2"
    source = template_path.read_text()
    env = Environment(undefined=StrictUndefined)
    env.filters["bool"] = _ansible_bool
    return env.from_string(source).render(
        ssh_listener_ports=ports, ssh_ipv6_available=ipv6_available
    )


def _effective_listeners(main_unit, dropins):
    """Simulate systemd ListenStream= reset/append merge order.

    The main unit is applied first, then drop-ins sorted by filename (ASCII).
    An empty ``ListenStream=`` resets the accumulated list; a non-empty value
    appends.  This mirrors how ``addresses.conf`` sorts after a ``99-...``
    drop-in but before a ``zz-...`` drop-in.
    """
    listeners: list[str] = []
    ordered = [("ssh.socket", main_unit)] + sorted(dropins.items())
    for _name, content in ordered:
        for line in content.splitlines():
            line = line.strip()
            if line.startswith("ListenStream="):
                value = line.split("=", 1)[1].strip()
                if not value:
                    listeners = []
                else:
                    listeners.append(value)
    return listeners


def test_socket_generator_ordering() -> None:
    override_v4 = _render_socket_override([22, 2223], False)
    override_v6 = _render_socket_override([22, 2223], True)

    # The managed drop-in name is read from the real configure.yml template task,
    # so renaming it back to a pre-addresses.conf name (e.g. 99-...) makes the
    # override lose and this test go red.
    name = SOCKET_OVERRIDE_BASENAME

    # Our managed drop-in must sort after addresses.conf -> v4-only override wins.
    merged = _effective_listeners(VENDOR_SSH_SOCKET, {
        "addresses.conf": ADDRESSES_CONF,
        name: override_v4,
    })
    assert merged == ["0.0.0.0:22", "0.0.0.0:2223"]

    # Dual-stack still binds both families per port.
    merged_v6 = _effective_listeners(VENDOR_SSH_SOCKET, {
        "addresses.conf": ADDRESSES_CONF,
        name: override_v6,
    })
    assert merged_v6 == ["0.0.0.0:22", "[::]:22", "0.0.0.0:2223", "[::]:2223"]

    # A legacy 99- name sorts before addresses.conf -> generator overrides -> v6
    # leaks. It must not be the current managed name.
    legacy = "99-devops-toolkit.conf"
    assert legacy != name
    merged_legacy = _effective_listeners(VENDOR_SSH_SOCKET, {
        legacy: override_v4,
        "addresses.conf": ADDRESSES_CONF,
    })
    assert merged_legacy == ["0.0.0.0:22", "[::]:22"]


def test_listen_matches() -> None:
    # v4-only effective output matches expected.
    assert (
        ssh_security_listen_matches(
            [22, 2223], False, "0.0.0.0:22 (Stream)\n0.0.0.0:2223 (Stream)"
        )
        is True
    )

    # Dual-stack effective output matches expected.
    assert (
        ssh_security_listen_matches(
            [22], True, "0.0.0.0:22 (Stream)\n[::]:22 (Stream)"
        )
        is True
    )

    # String truthiness is coerced.
    assert (
        ssh_security_listen_matches(
            [22], "true", "0.0.0.0:22 (Stream)\n[::]:22 (Stream)"
        )
        is True
    )

    # IPv6 disabled but a residual v6 endpoint remains -> mismatch (fail closed).
    assert (
        ssh_security_listen_matches(
            [22, 2223],
            False,
            "0.0.0.0:22 (Stream)\n[::]:22 (Stream)\n0.0.0.0:2223 (Stream)",
        )
        is False
    )

    # Missing an expected v4 endpoint -> mismatch.
    assert (
        ssh_security_listen_matches([22, 2223], False, "0.0.0.0:22 (Stream)")
        is False
    )

    # Unparseable / empty effective output -> fail closed.
    assert ssh_security_listen_matches([22], False, "not an endpoint (Stream)") is False
    assert ssh_security_listen_matches([22], False, "") is False


def test_is_managed_socket_dropin() -> None:
    def enc(text: str) -> str:
        return base64.b64encode(text.encode("utf-8")).decode("ascii")

    # Positive: exact first-line marker, with and without leading blank lines.
    assert ssh_security_is_managed_socket_dropin(
        enc("# Managed by DevOpsToolkit\n[Socket]\nListenStream=\n")
    ) is True
    assert ssh_security_is_managed_socket_dropin(
        enc("\n\n  # Managed by DevOpsToolkit  \n[Socket]\n")
    ) is True

    # Negative: a negated phrase must not be treated as managed.
    assert ssh_security_is_managed_socket_dropin(
        enc("# Not Managed by DevOpsToolkit\n[Socket]\n")
    ) is False
    # Negative: marker appears only as a later reference, not the first line.
    assert ssh_security_is_managed_socket_dropin(
        enc("# user note\n# Managed by DevOpsToolkit is referenced here\n[Socket]\n")
    ) is False
    # Negative: marker embedded inside a longer first line.
    assert ssh_security_is_managed_socket_dropin(
        enc("see # Managed by DevOpsToolkit below\n[Socket]\n")
    ) is False
    # Negative: empty or blank-only content.
    assert ssh_security_is_managed_socket_dropin(enc("")) is False
    assert ssh_security_is_managed_socket_dropin(enc("\n  \n")) is False


def test_managed_dropin_expression() -> None:
    """Render the exact legacy-managed set_fact expression from configure.yml."""
    env = Environment(undefined=StrictUndefined)
    env.filters.update(mod.FilterModule().filters())
    env.filters["bool"] = _ansible_bool
    template = env.from_string(MARKER_EXPRESSION)

    def enc(text: str) -> str:
        return base64.b64encode(text.encode("utf-8")).decode("ascii")

    def render(content_b64):
        return template.render(
            ssh_legacy_socket_dropin=types.SimpleNamespace(content=content_b64),
        )

    assert render(enc("# Managed by DevOpsToolkit\n[Socket]\n")) == "True"
    assert render(enc("# Not Managed by DevOpsToolkit\n[Socket]\n")) == "False"
    assert render(enc("# user note\n# Managed by DevOpsToolkit is referenced here\n")) == "False"
    assert render(enc("")) == "False"


def test_effective_listen_assert_expression() -> None:
    """Render the exact assert conditions from tasks/configure.yml."""
    filters = mod.FilterModule().filters()
    env = Environment(undefined=StrictUndefined)
    env.filters.update(filters)
    env.filters["bool"] = _ansible_bool
    rc_expression = EFFECTIVE_LISTEN_CONDITIONS[0]
    listen_expression = EFFECTIVE_LISTEN_CONDITIONS[1]
    rc_template = env.from_string("{{ " + rc_expression + " }}")
    listen_template = env.from_string("{{ " + listen_expression + " }}")

    def render(ports, ipv6_available, rc, listen):
        context = {
            "ssh_listener_ports": ports,
            "ssh_ipv6_available": ipv6_available,
            "ssh_effective_socket_listen": types.SimpleNamespace(rc=rc, stdout=listen),
        }
        return (
            rc_template.render(**context),
            listen_template.render(**context),
        )

    assert render([22], False, 0, "0.0.0.0:22 (Stream)") == ("True", "True")
    assert (
        render([22, 2223], False, 0, "0.0.0.0:22 (Stream)\n0.0.0.0:2223 (Stream)")
        == ("True", "True")
    )
    assert (
        render([22], False, 0, "0.0.0.0:22 (Stream)\n[::]:22 (Stream)")
        == ("True", "False")
    )
    assert render([22], False, 1, "0.0.0.0:22 (Stream)") == ("False", "True")


if __name__ == "__main__":
    test_parse_addr_port()
    test_parse_listen_stream_endpoints()
    test_parse_exe_probe()
    test_parse_ss_lines()
    test_port_ownership()
    test_actual_assert_expression()
    test_ipv6_available_expression()
    test_socket_template()
    test_socket_generator_ordering()
    test_listen_matches()
    test_is_managed_socket_dropin()
    test_managed_dropin_expression()
    test_effective_listen_assert_expression()
    print("test-ssh-security.py: OK")
