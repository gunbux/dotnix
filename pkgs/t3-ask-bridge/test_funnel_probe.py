import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

from funnel_probe import TARGET, port_view, preflight, run_probe

BASE = {"TCP": {"8443": {"HTTPS": True}},
        "Web": {"test.example.ts.net:8443": {"Handlers": {"/": {"Proxy": TARGET}}}},
        "AllowFunnel": {"test.example.ts.net:8443": True}}


class ProbeTests(unittest.TestCase):
    def test_existing_public_bridge_is_required(self):
        self.assertTrue(preflight(BASE))
        for section in ("TCP", "Web", "AllowFunnel"):
            config = copy.deepcopy(BASE)
            config[section] = {}
            with self.assertRaises(RuntimeError):
                preflight(config)

    def test_reserved_port_is_protected_at_every_level(self):
        for section, value in [("TCP", {"443": {"HTTPS": True}}),
                               ("Web", {"test.example.ts.net:443": {"Handlers": {}}}),
                               ("AllowFunnel", {"test.example.ts.net:443": False})]:
            occupied = {section: value}
            for nested in (False, True):
                config = copy.deepcopy(BASE)
                if nested:
                    config["Foreground"] = {"other-session": occupied}
                else:
                    config.setdefault(section, {}).update(value)
                with self.assertRaises(RuntimeError):
                    preflight(config)

    def test_foreground_child_is_removed_and_8443_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / "state.json"
            state.write_text(json.dumps(BASE))
            fake = root / "tailscale"
            fake.write_text("#!" + sys.executable + "\n" + '''import json, signal, sys, time
from pathlib import Path
p = Path(__file__).with_name('state.json')
if sys.argv[1:] == ['serve', 'status', '--json']:
    print(p.read_text()); sys.exit()
assert sys.argv[1:] == ['funnel', '--https=443', 'http://127.0.0.1:8789']
s = json.loads(p.read_text())
s['Foreground'] = {'probe': {'TCP': {'443': {'HTTPS': True}}}}
p.write_text(json.dumps(s))
def stop(*args):
    s = json.loads(p.read_text()); s.pop('Foreground', None)
    p.write_text(json.dumps(s)); sys.exit()
signal.signal(signal.SIGTERM, stop)
while True: time.sleep(.01)
''')
            fake.chmod(0o700)
            run_probe(str(fake), seconds=0.05, ready_timeout=3)
            self.assertEqual(json.loads(state.read_text()), BASE)
            self.assertFalse(port_view(json.loads(state.read_text()), 443))


if __name__ == "__main__":
    unittest.main()
