#!/usr/bin/env python3
"""Unit tests for the privilege-separated ACME manager."""

from __future__ import annotations

import importlib.machinery
import importlib.util
import argparse
import io
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


MANAGER_PATH = Path(__file__).parents[1] / "libexec" / "acme-manager"


def load_manager():
    loader = importlib.machinery.SourceFileLoader("acme_manager", str(MANAGER_PATH))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    if spec is None:
        raise RuntimeError("无法加载 acme-manager")
    module = importlib.util.module_from_spec(spec)
    sys.modules[loader.name] = module
    loader.exec_module(module)
    return module


manager = load_manager()


class DomainValidationTests(unittest.TestCase):
    def test_normalizes_case_and_trailing_dot(self) -> None:
        self.assertEqual(manager.normalize_primary_domain("Example.COM."), "example.com")
        self.assertEqual(
            manager.normalize_domain("*.Example.COM", allow_wildcard=True),
            "*.example.com",
        )

    def test_rejects_invalid_and_disallowed_wildcard_domains(self) -> None:
        invalid = ("example", "-example.com", "example..com", "example.com/path")
        for value in invalid:
            with self.subTest(value=value), self.assertRaises(manager.ManagerError):
                manager.normalize_primary_domain(value)
        with self.assertRaises(manager.ManagerError):
            manager.normalize_domain("*.example.com", allow_wildcard=False)


class DnsEnvironmentTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.config = self.root / "dns-config"

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_config(self, content: str) -> None:
        self.config.write_text(content, encoding="utf-8")
        self.config.chmod(0o640)

    def test_parses_strict_key_value_file(self) -> None:
        self.write_config("# provider credentials\nexport CF_Token='token value'\nCF_Account_ID=abc\n")
        self.assertEqual(
            manager.load_dns_environment(self.config, expected_uid=os.geteuid()),
            ["CF_Token=token value", "CF_Account_ID=abc"],
        )

    def test_rejects_dangerous_environment_names_and_writable_file(self) -> None:
        self.write_config("LD_PRELOAD=/tmp/payload.so\n")
        with self.assertRaises(manager.ManagerError):
            manager.load_dns_environment(self.config, expected_uid=os.geteuid())

        self.write_config("CF_Token=value\n")
        self.config.chmod(0o662)
        with self.assertRaises(manager.ManagerError):
            manager.load_dns_environment(self.config, expected_uid=os.geteuid())

    def test_rejects_symlink(self) -> None:
        target = self.root / "target"
        target.write_text("CF_Token=value\n", encoding="utf-8")
        self.config.symlink_to(target)
        with self.assertRaises(manager.ManagerError):
            manager.load_dns_environment(self.config, expected_uid=os.geteuid())

    def test_provider_secret_is_child_environment_not_command_argument(self) -> None:
        layout = manager.Layout(base=self.root / "state", etc=self.root / "etc")
        layout.acme_bin.parent.mkdir(parents=True)
        layout.acme_bin.write_text("#!/bin/sh\n", encoding="utf-8")
        with (
            mock.patch.object(manager.shutil, "which", return_value="/usr/sbin/runuser"),
            mock.patch.object(manager.subprocess, "run") as runner,
            mock.patch.dict(os.environ, {"HOST_ONLY_SECRET": "must-not-pass"}),
        ):
            manager.run_as_acme(
                layout,
                ["--issue", "-d", "example.com"],
                extra_environment=["CF_Token=secret-value"],
                capture_output=True,
            )
        command = runner.call_args.args[0]
        options = runner.call_args.kwargs
        self.assertNotIn("secret-value", " ".join(command))
        self.assertIn("--preserve-environment", command)
        self.assertEqual(options["env"]["CF_Token"], "secret-value")
        self.assertNotIn("HOST_ONLY_SECRET", options["env"])
        self.assertTrue(options["capture_output"])
        self.assertEqual(options["umask"], 0o077)

    def test_rejects_environment_override_at_execution_boundary(self) -> None:
        layout = manager.Layout(base=self.root / "state", etc=self.root / "etc")
        layout.acme_bin.parent.mkdir(parents=True)
        layout.acme_bin.write_text("#!/bin/sh\n", encoding="utf-8")
        with mock.patch.object(manager.shutil, "which", return_value="/usr/sbin/runuser"):
            for name in ("PATH", "USER", "LOGNAME"):
                with self.subTest(name=name), self.assertRaises(manager.ManagerError):
                    manager.run_as_acme(
                        layout, ["--issue"], extra_environment=[f"{name}=malicious"]
                    )


class QueueDeploymentTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        root = Path(self.temporary.name)
        self.root = root
        self.layout = manager.Layout(base=root / "state", etc=root / "etc")
        for directory in (
            self.layout.staging,
            self.layout.queue,
            self.layout.failed,
            self.layout.etc,
        ):
            directory.mkdir(parents=True, mode=0o700)
        self.layout.reload_services.write_text("# intentionally empty\n", encoding="utf-8")
        self.layout.reload_services.chmod(0o644)
        self.uid = os.geteuid()
        self.gid = os.getegid()
        self.identity = (self.uid, self.gid, self.gid)
        key_path = root / "test.key"
        self.key_path = key_path
        cert_path = root / "test.crt"
        subprocess.run(
            [
                "openssl",
                "req",
                "-x509",
                "-newkey",
                "ec",
                "-pkeyopt",
                "ec_paramgen_curve:P-256",
                "-nodes",
                "-keyout",
                str(key_path),
                "-out",
                str(cert_path),
                "-days",
                "1",
                "-subj",
                "/CN=example.com",
                "-addext",
                "subjectAltName=DNS:example.com",
            ],
            check=True,
            capture_output=True,
        )
        self.key = key_path.read_bytes()
        self.cert = cert_path.read_bytes()

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def stage(self, domain: str = "example.com") -> Path:
        (self.layout.staging / f"{domain}.key").write_bytes(self.key)
        (self.layout.staging / f"{domain}.crt").write_bytes(self.cert)
        (self.layout.staging / f"{domain}.ca").write_bytes(self.cert)
        marker = self.layout.queue / domain
        marker.write_text(f"{domain}\n", encoding="utf-8")
        marker.chmod(0o600)
        return marker

    def renew(self) -> None:
        renewed = self.root / "renewed.crt"
        subprocess.run(
            [
                "openssl", "req", "-x509", "-key", str(self.key_path),
                "-out", str(renewed), "-days", "2", "-subj", "/CN=example.com",
                "-addext", "subjectAltName=DNS:example.com",
            ],
            check=True,
            capture_output=True,
        )
        self.cert = renewed.read_bytes()

    def process(self, **kwargs) -> int:
        return manager.process_queue(
            self.layout,
            identity=self.identity,
            require_privileged=False,
            deployed_owner_uid=self.uid,
            config_owner_uid=self.uid,
            **kwargs,
        )

    def test_deploys_valid_pem_with_least_privilege_modes(self) -> None:
        marker = self.stage()
        self.assertEqual(self.process(), 0)
        self.assertFalse(marker.exists())
        bundle = self.layout.certs / "example.com" / "current"
        self.assertTrue(bundle.is_symlink())
        self.assertEqual((bundle / "privkey.pem").read_bytes(), self.key)
        self.assertEqual((bundle / "fullchain.pem").read_bytes(), self.cert)
        self.assertEqual((bundle / "ca.pem").read_bytes(), self.cert)
        self.assertEqual(
            stat.S_IMODE((bundle / "privkey.pem").stat().st_mode),
            0o640,
        )
        self.assertEqual(
            stat.S_IMODE((bundle / "fullchain.pem").stat().st_mode),
            0o644,
        )
        self.assertEqual(
            stat.S_IMODE((bundle / "ca.pem").stat().st_mode), 0o644
        )

    def test_rejects_staged_symlink_and_quarantines_marker(self) -> None:
        marker = self.stage()
        key = self.layout.staging / "example.com.key"
        key.unlink()
        key.symlink_to(self.layout.staging / "example.com.crt")

        self.assertEqual(self.process(), 1)
        self.assertFalse(marker.exists())
        self.assertFalse((self.layout.certs / "example.com").exists())
        failed = list(self.layout.failed.iterdir())
        self.assertEqual(len(failed), 1)
        self.assertTrue(failed[0].name.startswith("example.com."))

    def test_rejects_malformed_key_before_publish(self) -> None:
        marker = self.stage()
        (self.layout.staging / "example.com.key").write_bytes(
            b"-----BEGIN PRIVATE KEY-----\nINVALID\n-----END PRIVATE KEY-----\n"
        )
        self.assertEqual(self.process(), 1)
        self.assertFalse(marker.exists())
        self.assertFalse((self.layout.certs / "example.com").exists())

    def test_rejects_hardlinked_marker_without_mutating_target(self) -> None:
        self.stage()
        marker = self.layout.queue / "example.com"
        marker.unlink()
        target = self.layout.base / "acme-owned-state"
        target.write_text("keep\n", encoding="utf-8")
        target.chmod(0o600)
        marker.hardlink_to(target)
        original = target.stat()

        self.assertEqual(self.process(), 1)
        self.assertFalse(marker.exists())
        current = target.stat()
        self.assertEqual(current.st_uid, original.st_uid)
        self.assertEqual(current.st_gid, original.st_gid)
        self.assertEqual(stat.S_IMODE(current.st_mode), stat.S_IMODE(original.st_mode))
        self.assertEqual(target.read_text(encoding="utf-8"), "keep\n")

    def test_reload_runs_only_after_successful_deployment(self) -> None:
        self.layout.reload_services.write_text("nginx.service\n", encoding="utf-8")
        calls: list[list[str]] = []

        def runner(command, **_kwargs):
            calls.append(command)
            return subprocess.CompletedProcess(command, 0)

        original_which = manager.shutil.which
        with mock.patch.object(
            manager.shutil,
            "which",
            side_effect=lambda command: (
                "/bin/systemctl" if command == "systemctl" else original_which(command)
            ),
        ):
            self.assertEqual(self.process(reload_runner=runner), 0)
            self.assertEqual(calls, [])

            self.stage()
            self.assertEqual(self.process(reload_runner=runner), 0)

            self.stage()
            self.assertEqual(self.process(reload_runner=runner), 0)

            self.renew()
            self.stage()
            self.assertEqual(self.process(reload_runner=runner), 0)

        self.assertEqual(
            calls,
            [
                ["/bin/systemctl", "is-active", "--quiet", "nginx.service"],
                ["/bin/systemctl", "reload-or-restart", "nginx.service"],
                ["/bin/systemctl", "is-active", "--quiet", "nginx.service"],
                ["/bin/systemctl", "reload-or-restart", "nginx.service"],
            ],
        )

    def test_failed_pointer_switch_preserves_complete_old_bundle(self) -> None:
        self.stage()
        self.assertEqual(self.process(), 0)
        bundle = self.layout.certs / "example.com" / "current"
        old_target = os.readlink(bundle)
        old_cert = (bundle / "fullchain.pem").read_bytes()
        self.renew()
        marker = self.stage()
        original_replace = manager.os.replace

        def fail_switch(source, destination):
            if Path(destination).name == "current":
                raise OSError("injected pointer failure")
            return original_replace(source, destination)

        with mock.patch.object(manager.os, "replace", side_effect=fail_switch):
            self.assertEqual(self.process(), 1)

        self.assertFalse(marker.exists())
        self.assertEqual(os.readlink(bundle), old_target)
        self.assertEqual((bundle / "fullchain.pem").read_bytes(), old_cert)
        self.assertEqual((bundle / "privkey.pem").read_bytes(), self.key)

    def test_failed_revision_preparation_removes_partial_directory(self) -> None:
        marker = self.stage()
        original_install = manager._atomic_install

        def fail_fullchain(path, *args, **kwargs):
            if Path(path).name == "fullchain.pem":
                raise OSError("injected revision preparation failure")
            return original_install(path, *args, **kwargs)

        with mock.patch.object(manager, "_atomic_install", side_effect=fail_fullchain):
            self.assertEqual(self.process(), 1)

        self.assertFalse(marker.exists())
        revisions = self.layout.certs / "example.com" / "revisions"
        self.assertEqual(list(revisions.iterdir()), [])

    def test_directory_sync_failure_keeps_marker_for_recovery(self) -> None:
        self.stage()
        self.assertEqual(self.process(), 0)
        bundle = self.layout.certs / "example.com" / "current"
        old_revision = os.readlink(bundle)
        self.renew()
        marker = self.stage()
        original_sync = manager._fsync_directory
        domain_directory = self.layout.certs / "example.com"

        def fail_after_switch(path):
            if path == domain_directory:
                raise OSError("injected directory sync failure")
            return original_sync(path)

        with mock.patch.object(manager, "_fsync_directory", side_effect=fail_after_switch):
            self.assertEqual(self.process(), 1)

        self.assertTrue(marker.exists())
        new_revision = os.readlink(bundle)
        self.assertNotEqual(old_revision, new_revision)
        self.assertEqual((bundle / "fullchain.pem").read_bytes(), self.cert)
        self.assertEqual(self.process(), 0)
        self.assertFalse(marker.exists())
        self.assertEqual(os.readlink(bundle), new_revision)

    def test_switch_followed_by_reload_failure_recovers_without_new_revision(self) -> None:
        self.layout.reload_services.write_text("nginx.service\n", encoding="utf-8")
        original_which = manager.shutil.which

        def failing_runner(command, **_kwargs):
            if "reload-or-restart" in command:
                raise OSError("injected reload failure")
            return subprocess.CompletedProcess(command, 0)

        with mock.patch.object(
            manager.shutil, "which",
            side_effect=lambda name: "/bin/systemctl" if name == "systemctl" else original_which(name),
        ):
            self.stage()
            self.assertEqual(
                self.process(
                    reload_runner=lambda command, **kwargs: subprocess.CompletedProcess(command, 0)
                ),
                0,
            )
            bundle = self.layout.certs / "example.com" / "current"
            old_revision = os.readlink(bundle)
            self.renew()
            marker = self.stage()
            with self.assertRaises(OSError):
                self.process(reload_runner=failing_runner)
            self.assertTrue(marker.exists())
            new_revision = os.readlink(bundle)
            self.assertNotEqual(new_revision, old_revision)
            self.assertEqual((bundle / "fullchain.pem").read_bytes(), self.cert)

            calls = []

            def successful_runner(command, **_kwargs):
                calls.append(command)
                return subprocess.CompletedProcess(command, 0)

            self.assertEqual(self.process(reload_runner=successful_runner), 0)
            self.assertFalse(marker.exists())
            self.assertEqual(os.readlink(bundle), new_revision)
            self.assertIn("reload-or-restart", calls[-1])

    def test_legacy_flat_file_blocks_bundle_publish(self) -> None:
        legacy = self.layout.certs / "example.com.key"
        self.layout.certs.mkdir(mode=0o750)
        legacy.write_bytes(self.key)
        marker = self.stage()
        self.assertEqual(self.process(), 1)
        self.assertFalse(marker.exists())
        self.assertEqual(legacy.read_bytes(), self.key)
        self.assertFalse((self.layout.certs / "example.com").exists())

    def test_reload_multiple_active_consumers_only(self) -> None:
        self.layout.reload_services.write_text(
            "nginx.service\nxray.service\ninactive.service\nnginx.service\n",
            encoding="utf-8",
        )
        calls: list[list[str]] = []

        def runner(command, **_kwargs):
            calls.append(command)
            return subprocess.CompletedProcess(
                command, 3 if command[-1] == "inactive.service" else 0
            )

        original_which = manager.shutil.which
        with mock.patch.object(
            manager.shutil,
            "which",
            side_effect=lambda name: "/bin/systemctl" if name == "systemctl" else original_which(name),
        ):
            self.stage()
            self.assertEqual(self.process(reload_runner=runner), 0)

        self.assertEqual(
            [command[-1] for command in calls if "reload-or-restart" in command],
            ["nginx.service", "xray.service"],
        )


class DeployRequestTests(unittest.TestCase):
    def test_request_rejects_symlink_marker(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            layout = manager.Layout(base=Path(temporary) / "state", etc=Path(temporary) / "etc")
            layout.queue.mkdir(parents=True)
            layout.staging.mkdir(parents=True)
            target = Path(temporary) / "target"
            target.write_text("unchanged\n", encoding="utf-8")
            (layout.queue / "example.com").symlink_to(target)
            identity = (os.geteuid(), os.getegid(), os.getegid())
            with mock.patch.object(manager, "account_ids", return_value=identity):
                with self.assertRaises(manager.ManagerError):
                    manager.request_deploy(layout, "example.com")
            self.assertEqual(target.read_text(encoding="utf-8"), "unchanged\n")

    def test_request_replaces_hardlink_without_mutating_target(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            layout = manager.Layout(base=Path(temporary) / "state", etc=Path(temporary) / "etc")
            layout.queue.mkdir(parents=True)
            layout.staging.mkdir(parents=True)
            target = Path(temporary) / "target"
            target.write_text("unchanged\n", encoding="utf-8")
            (layout.queue / "example.com").hardlink_to(target)
            identity = (os.geteuid(), os.getegid(), os.getegid())
            with mock.patch.object(manager, "account_ids", return_value=identity):
                manager.request_deploy(layout, "example.com")
            self.assertEqual(target.read_text(encoding="utf-8"), "unchanged\n")
            self.assertEqual(
                (layout.queue / "example.com").read_text(encoding="utf-8"),
                "example.com\n",
            )


class CertificateCommandTests(unittest.TestCase):
    def test_add_pins_ecc_for_issue_and_install(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            layout = manager.Layout(base=Path(temporary) / "state", etc=Path(temporary) / "etc")
            args = argparse.Namespace(
                domains=["example.com"],
                method="webroot",
                webroot=str(Path(temporary) / "webroot"),
                dns_provider="dns_cf",
            )
            commands: list[list[str]] = []

            def capture(_layout, arguments, **_kwargs):
                commands.append(list(arguments))
                return subprocess.CompletedProcess(arguments, 0)

            with (
                mock.patch.object(manager, "require_root"),
                mock.patch.object(manager, "_prepare_challenge_directory"),
                mock.patch.object(manager, "run_as_acme", side_effect=capture),
                mock.patch.object(manager, "request_deploy"),
                mock.patch.object(manager, "process_queue", return_value=0),
            ):
                self.assertEqual(manager.add_certificate(args, layout), 0)

        self.assertIn("--keylength", commands[0])
        self.assertEqual(commands[0][commands[0].index("--keylength") + 1], "ec-256")
        self.assertIn("--ecc", commands[1])

    def test_dns_issue_captures_provider_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            layout = manager.Layout(base=Path(temporary) / "state", etc=Path(temporary) / "etc")
            args = argparse.Namespace(
                domains=["example.com"],
                method="dns",
                webroot="/var/www/html",
                dns_provider="dns_cf",
            )
            calls: list[dict[str, object]] = []

            def capture(_layout, _arguments, **kwargs):
                calls.append(kwargs)
                return subprocess.CompletedProcess(_arguments, 0)

            with (
                mock.patch.object(manager, "require_root"),
                mock.patch.object(
                    manager,
                    "load_dns_environment",
                    return_value=["CF_Token=secret-value"],
                ),
                mock.patch.object(manager, "run_as_acme", side_effect=capture),
                mock.patch.object(manager, "request_deploy"),
                mock.patch.object(manager, "process_queue", return_value=0),
            ):
                self.assertEqual(manager.add_certificate(args, layout), 0)

        self.assertEqual(calls[0]["extra_environment"], ["CF_Token=secret-value"])
        self.assertTrue(calls[0]["capture_output"])

    def test_failed_external_command_never_prints_command_or_secret(self) -> None:
        failure = subprocess.CalledProcessError(
            17, ["env", "CF_Token=secret-value", "acme.sh", "--issue"]
        )
        with (
            mock.patch.object(manager, "add_certificate", side_effect=failure),
            mock.patch.object(manager.sys, "stderr", new_callable=io.StringIO) as errors,
        ):
            self.assertEqual(manager.main(["add", "example.com"]), 17)
        self.assertIn("exit=17", errors.getvalue())
        self.assertNotIn("secret-value", errors.getvalue())
        self.assertNotIn("CF_Token", errors.getvalue())


if __name__ == "__main__":
    unittest.main()
