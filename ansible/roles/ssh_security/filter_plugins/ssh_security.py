"""Pure helpers for ssh_security socket/listener validation.

These functions parse the effective ``systemctl show ssh.socket --property=Listen
--value`` output, the ``ss`` listener probe, and a ``/proc/<pid>/exe`` read-only
resolution so the role can make exact, fail-closed decisions about port ownership.

They deliberately avoid the hazards of the previous inline checks:

* substring port matching (``ListenStream=2222`` matching ``ListenStream=22222``);
* trusting raw ``systemctl cat`` fragments that still show vendor or overridden
  ``ListenStream`` lines that no longer take effect;
* treating a port as SSH-owned merely because one ``ss`` line names ``sshd``,
  while another listener on the same port belongs to an unrelated service;
* trusting a process *name* alone when that name can be spoofed;
* accepting a basename/blacklist match for ``sshd`` or ``systemd`` when the
  executable could live at a user-writable path (e.g. ``/opt/...``).

The decision function returns ``True`` only when a port is positively free or
positively OpenSSH-owned, using exact TCP/Stream endpoints (address family +
address + port) and positively-verified process ownership:

* ``systemd`` must be PID 1 and resolve to a systemd/init executable;
* ``sshd`` must resolve to the canonical system ``sshd`` executable via
  ``/proc/<pid>/exe`` and must not share the socket with any unrelated process;
* multiple listeners on the exact same endpoint are ambiguous (SO_REUSEPORT can
  let distinct systemd units bind one endpoint) and are rejected.

Every ambiguous case returns ``False`` so callers refuse the change rather than
risk dropping the trusted SSH connection.
"""

from __future__ import annotations

import base64
import re
from dataclasses import dataclass


@dataclass(frozen=True)
class Endpoint:
    family: str  # "ipv4" | "ipv6"
    addr: str  # normalized address, e.g. "0.0.0.0" or "::"
    port: int


@dataclass(frozen=True)
class Process:
    name: str
    pid: int


@dataclass(frozen=True)
class ListenerLine:
    endpoint: Endpoint
    processes: tuple[Process, ...]


_ADDR_PORT_RE = re.compile(
    r"^(?:\[(?P<v6>[^\]]+)\]|(?P<v4>\d{1,3}(?:\.\d{1,3}){3})):(?P<port>\d+)$"
)

# A single ``ss`` owner tuple: ("name",pid=N,fd=N).  ss escapes ``"`` as ``\"``
# and ``\`` as ``\\``, so the quoted name may contain backslash-escaped
# characters; the name body stops only at the first unescaped closing quote.
_OWNER_RE = re.compile(r'\(\"((?:[^\"\\]|\\.)*)\",pid=(\d+),fd=\d+\)')

# Canonical paths only.  Positive ownership is proven by exact path, never by
# basename, so a user-writable copy under /opt (or any other path) cannot pass.
_TRUSTED_SSHD_PATHS = frozenset({
    "/usr/sbin/sshd",
    "/sbin/sshd",  # non-merged /usr alias
})
_TRUSTED_SYSTEMD_PATHS = frozenset({
    "/usr/lib/systemd/systemd",
    "/lib/systemd/systemd",  # non-merged /usr alias
})


def parse_addr_port(token: str) -> Endpoint | None:
    match = _ADDR_PORT_RE.match(token)
    if not match:
        return None
    if match.group("v6") is not None:
        return Endpoint("ipv6", match.group("v6"), int(match.group("port")))
    return Endpoint("ipv4", match.group("v4"), int(match.group("port")))


def parse_listen_stream_endpoints(value) -> set[Endpoint] | None:
    """Return the effective Stream listen endpoints, or None on unknown input.

    Only ``(Stream)`` endpoints count; ``(Datagram)`` and other socket types are
    deliberately excluded because ssh.socket owns a TCP listener. An unparseable
    Stream line returns ``None`` so callers fail closed.
    """
    endpoints: set[Endpoint] = set()
    for raw in str(value or "").splitlines():
        token = raw.strip()
        if not token:
            continue
        for prefix in ("Listen=", "ListenStream="):
            if token.startswith(prefix):
                token = token[len(prefix):].strip()
                break
        proto = "stream"
        match = re.match(r"^(.*?)\s*\(([^)]*)\)\s*$", token)
        if match:
            token = match.group(1).strip()
            proto = match.group(2).strip().lower()
        if proto != "stream":
            continue
        endpoint = parse_addr_port(token)
        if endpoint is None:
            return None
        endpoints.add(endpoint)
    return endpoints


def _parse_users(users_part: str) -> list[Process] | None:
    """Parse the complete ``users:(...)`` owner list, or None on any ambiguity.

    The list is consumed exhaustively: every owner must match the strict
    ``("name",pid=N,fd=N)`` shape.  A malformed or partially-parseable owner
    (for example a spoofed name containing an unescaped or escaped quote) fails
    the whole parse rather than being silently dropped.
    """
    s = users_part.strip()
    prefix = "users:("
    if not s.startswith(prefix):
        return None
    if not s.endswith(")"):
        return None
    inner = s[len(prefix):-1].strip()
    if not inner:
        return None
    processes: list[Process] = []
    pos = 0
    n = len(inner)
    first = True
    while pos < n:
        if not first:
            if inner[pos] != ",":
                return None
            pos += 1
            while pos < n and inner[pos].isspace():
                pos += 1
        match = _OWNER_RE.match(inner, pos)
        if match is None:
            return None
        processes.append(Process(match.group(1), int(match.group(2))))
        pos = match.end()
        first = False
    return processes


def parse_ss_lines(value, target_port) -> list[ListenerLine] | None:
    """Parse ``ss`` output for a target port, or None on any unparseable line."""
    target = int(target_port)
    lines: list[ListenerLine] = []
    for raw in str(value or "").splitlines():
        line = raw.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) < 6:
            return None
        endpoint = parse_addr_port(parts[3])
        if endpoint is None:
            return None
        if endpoint.port != target:
            continue
        processes = _parse_users(" ".join(parts[5:]))
        if processes is None:
            return None
        lines.append(ListenerLine(endpoint, tuple(processes)))
    return lines


def parse_exe_probe(value) -> dict[int, str] | None:
    """Parse ``pid=exe`` lines from the target-side /proc exe probe."""
    result: dict[int, str] = {}
    for raw in str(value or "").splitlines():
        line = raw.strip()
        if not line:
            continue
        if "=" not in line:
            return None
        pid_text, exe = line.split("=", 1)
        try:
            pid = int(pid_text)
        except ValueError:
            return None
        result[pid] = exe
    return result


def _is_sshd_exe(exe: str) -> bool:
    return exe in _TRUSTED_SSHD_PATHS


def _is_systemd_exe(exe: str) -> bool:
    return exe in _TRUSTED_SYSTEMD_PATHS


def _line_is_trusted_ssh(
    line: ListenerLine,
    socket_active: bool,
    listen: set[Endpoint],
    exe_map: dict[int, str],
) -> bool:
    names = {p.name for p in line.processes}

    # Any unrelated co-owner (e.g. nginx) makes the socket untrusted.
    if names - {"systemd", "sshd"}:
        return False

    has_systemd = "systemd" in names
    has_sshd = "sshd" in names
    if not has_systemd and not has_sshd:
        return False

    if has_systemd:
        systemd_procs = [p for p in line.processes if p.name == "systemd"]
        # systemd is only credible as PID 1.
        if any(p.pid != 1 for p in systemd_procs):
            return False
        if not socket_active:
            return False
        # The exact endpoint must be one of ssh.socket's effective Stream listens.
        if line.endpoint not in listen:
            return False
        for p in systemd_procs:
            if not _is_systemd_exe(exe_map.get(p.pid, "")):
                return False

    if has_sshd:
        sshd_procs = [p for p in line.processes if p.name == "sshd"]
        for p in sshd_procs:
            if not _is_sshd_exe(exe_map.get(p.pid, "")):
                return False

    return True


def ssh_port_is_free_or_owned(
    ss_output, port, socket_state, listen_value, exe_probe=None
) -> bool:
    """Return True only when a port is free or positively OpenSSH-owned."""
    target = int(port)
    socket_active = str(socket_state or "").strip() == "active"

    listen = parse_listen_stream_endpoints(listen_value)
    if listen is None:
        return False

    lines = parse_ss_lines(ss_output, target)
    if lines is None:
        return False

    if not lines:
        return True

    # Multiple listeners on the exact same endpoint are ambiguous: SO_REUSEPORT
    # lets distinct systemd units bind one endpoint, so we cannot positively
    # attribute it to ssh.socket.  Normal v4/v6 endpoints are distinct and are
    # unaffected by this check.
    if len(lines) != len({line.endpoint for line in lines}):
        return False

    exe_map = parse_exe_probe(exe_probe)
    if exe_map is None:
        return False

    return all(
        _line_is_trusted_ssh(line, socket_active, listen, exe_map) for line in lines
    )


def listen_stream_ports(value) -> set[int]:
    """Diagnostic: ports from effective Stream listen endpoints."""
    endpoints = parse_listen_stream_endpoints(value)
    if endpoints is None:
        return set()
    return {e.port for e in endpoints}


def _coerce_bool(value) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    text = str(value).strip().lower()
    return text in ("true", "yes", "on", "1")


def ssh_security_listen_matches(ports, ipv6_available, listen_value) -> bool:
    """True when the effective Listen matches the intended managed endpoints.

    ``ports`` is the managed listen port list; ``ipv6_available`` controls
    whether each port must also be bound on ``[::]``.  ``listen_value`` is the
    ``systemctl show ssh.socket --property=Listen --value`` output.  Any
    unparseable effective output fails closed.
    """
    try:
        port_set = {int(p) for p in ports}
    except (TypeError, ValueError):
        return False
    expected: set[Endpoint] = set()
    for port in port_set:
        expected.add(Endpoint("ipv4", "0.0.0.0", port))
        if _coerce_bool(ipv6_available):
            expected.add(Endpoint("ipv6", "::", port))
    actual = parse_listen_stream_endpoints(listen_value)
    if actual is None:
        return False
    return actual == expected


_MANAGED_MARKER = "# Managed by DevOpsToolkit"


def ssh_security_is_managed_socket_dropin(content) -> bool:
    """True only when the first non-blank line is the exact managed marker.

    ``content`` is the base64 value from ``ansible.builtin.slurp``.  A drop-in
    produced by this role starts with the exact line
    ``# Managed by DevOpsToolkit``.  The check tolerates leading blank lines and
    surrounding whitespace, but it must be the whole first non-blank line: the
    marker may not appear elsewhere in the file, so a user file that merely
    mentions or negates the phrase (for example ``# Not Managed by
    DevOpsToolkit``) is never treated as managed.
    """
    try:
        text = base64.b64decode(str(content or "")).decode("utf-8")
    except Exception:
        return False
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        return line == _MANAGED_MARKER
    return False


class FilterModule:
    def filters(self):
        return {
            "ssh_security_listen_stream_ports": listen_stream_ports,
            "ssh_security_port_is_free_or_owned": ssh_port_is_free_or_owned,
            "ssh_security_listen_matches": ssh_security_listen_matches,
            "ssh_security_is_managed_socket_dropin": ssh_security_is_managed_socket_dropin,
        }
