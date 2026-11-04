import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import json

spec = importlib.util.spec_from_file_location('gateway', Path(__file__).with_name('gateway.py'))
gateway = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gateway)

class GatewayTests(unittest.TestCase):
    def test_private_credentials_reject_readable_files_and_links(self):
        with tempfile.TemporaryDirectory() as work:
            secret = Path(work) / 'token'
            secret.write_text('dummy-token-' * 4)
            secret.chmod(0o600)
            self.assertEqual(gateway.private_secret(secret), 'dummy-token-' * 4)
            secret.chmod(0o640)
            with self.assertRaises(RuntimeError): gateway.private_secret(secret)
            secret.chmod(0o600)
            link = Path(work) / 'link'
            link.symlink_to(secret)
            with self.assertRaises(RuntimeError): gateway.private_secret(link)

    def test_restart_preserves_credentials_and_failed_issue_is_not_published(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            binary = root / 't3'
            binary.write_text('#!/bin/sh\nprintf "dummy-token-abcdefghijklmnopqrstuvwxyz0123456789"\n')
            binary.chmod(0o700)
            secrets = root / 'secrets'
            secrets.mkdir(mode=0o700)
            gateway.provision_tokens(str(binary), root / 'state', secrets)
            before = {p.name: p.read_bytes() for p in secrets.iterdir()}
            self.assertEqual(set(before), {'t3-token'})
            self.assertTrue(all(p.stat().st_mode & 0o777 == 0o600 for p in secrets.iterdir()))
            binary.write_text('#!/bin/sh\nexit 1\n')
            gateway.provision_tokens(str(binary), root / 'state', secrets)
            self.assertEqual({p.name: p.read_bytes() for p in secrets.iterdir()}, before)
            for p in secrets.iterdir(): p.unlink()
            with self.assertRaises(RuntimeError): gateway.provision_tokens(str(binary), root / 'state', secrets)
            self.assertEqual(list(secrets.iterdir()), [])

    def test_approved_mcp_session_is_private_reused_and_renewed(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            settings = gateway.Config('unused', root / 'state', root, 3773)
            with patch.object(gateway, 'issue_mcp_client', return_value=('dummy-approved-token-' * 3, 30 * 86400)) as issue:
                gateway.ensure_mcp_access(settings)
                before = (root / 't3-mcp-token').read_bytes()
                gateway.ensure_mcp_access(settings)
                self.assertEqual(issue.call_count, 1)
                self.assertEqual((root / 't3-mcp-token').read_bytes(), before)
                metadata = root / 't3-mcp-session.json'
                data = json.loads(metadata.read_text())
                data['expiresAt'] = 1
                metadata.write_text(json.dumps(data))
                gateway.ensure_mcp_access(settings)
                self.assertEqual(issue.call_count, 2)
                self.assertTrue(all(p.stat().st_mode & 0o777 == 0o600 for p in root.iterdir()))
                metadata.unlink()
                with patch.object(gateway, 'issue_mcp_client', side_effect=RuntimeError('unavailable')):
                    with self.assertRaises(RuntimeError): gateway.ensure_mcp_access(settings)
                self.assertEqual((root / 't3-mcp-token').read_bytes(), before)

    def test_gateway_enables_peer_links_without_replacing_other_settings(self):
        with tempfile.TemporaryDirectory() as work:
            base = Path(work)
            directory = base / 'userdata'
            directory.mkdir(mode=0o700)
            path = directory / 'settings.json'
            path.write_text('{"linkedEnvironmentsEnabled":false,"otherSetting":"keep"}')
            path.chmod(0o600)
            gateway.enable_peer_links(base)
            import json
            self.assertEqual(json.loads(path.read_text()), {'linkedEnvironmentsEnabled': True, 'otherSetting': 'keep'})
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            before = path.stat().st_mtime_ns
            gateway.enable_peer_links(base)
            self.assertEqual(path.stat().st_mtime_ns, before)
            path.write_text('[]')
            with self.assertRaises(RuntimeError): gateway.enable_peer_links(base)

if __name__ == '__main__': unittest.main()
