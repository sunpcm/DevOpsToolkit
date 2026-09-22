#!/usr/bin/env python3
"""Unit tests for the privilege-separated ACME manager."""

from __future__ import annotations

import importlib.machinery
import importlib.util
import argparse
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


class QueueDeploymentTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        root = Path(self.temporary.name)
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
        self.assertEqual((self.layout.certs / "example.com.key").read_bytes(), self.key)
        self.assertEqual((self.layout.certs / "example.com.crt").read_bytes(), self.cert)
        self.assertEqual(
            stat.S_IMODE((self.layout.certs / "example.com.key").stat().st_mode),
            0o640,
        )
        self.assertEqual(
            stat.S_IMODE((self.layout.certs / "example.com.crt").stat().st_mode),
            0o644,
        )

    def test_rejects_staged_symlink_and_quarantines_marker(self) -> None:
        marker = self.stage()
        key = self.layout.staging / "example.com.key"
        key.unlink()
        key.symlink_to(self.layout.staging / "example.com.crt")

        self.assertEqual(self.process(), 1)
        self.assertFalse(marker.exists())
        self.assertFalse((self.layout.certs / "example.com.key").exists())
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
        self.assertFalse((self.layout.certs / "example.com.key").exists())

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

        self.assertEqual(
            calls,
            [
                ["/bin/systemctl", "is-active", "--quiet", "nginx.service"],
                ["/bin/systemctl", "reload-or-restart", "nginx.service"],
            ],
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


if __name__ == "__main__":
    unittest.main()
