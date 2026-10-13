import importlib.util
import json
from datetime import datetime, timezone
from pathlib import Path
import unittest
import sys
import tempfile


PLUGIN = Path(__file__).resolve().parents[1] / "config/swiftbar/menu.py"
spec = importlib.util.spec_from_file_location("macos_menu", PLUGIN)
menu = importlib.util.module_from_spec(spec)
spec.loader.exec_module(menu)


class NativeMenuTest(unittest.TestCase):
    def test_usage_menu_marks_old_provider_snapshots_as_stale(self):
        output = menu.usage_menu([{"provider": "claude", "usage": {
            "updatedAt": "2020-01-01T00:00:00Z", "primary": {"usedPercent": 20},
        }}])
        self.assertIn("C 80% (stale)", output.splitlines()[0])
        self.assertIn("Updated ", output)

    def test_usage_menu_labels_weekly_primary_fallback_correctly(self):
        output = menu.usage_menu([{"provider": "claude", "usage": {
            "primary": {"usedPercent": 20, "windowMinutes": 10080},
        }}])
        self.assertIn("Weekly: 80% left", output)
        self.assertNotIn("Session: 80% left", output)

    def test_usage_fetch_keeps_partial_json_from_nonzero_cli_exit(self):
        with tempfile.TemporaryDirectory() as directory:
            helper = Path(directory) / "codexbar"
            payload = [{"provider": "codex", "usage": {"primary": {"usedPercent": 25}}}]
            helper.write_text(f"#!{sys.executable}\nprint({json.dumps(payload)!r})\nraise SystemExit(1)\n")
            helper.chmod(0o700)
            self.assertIn("C ? · O 75%", menu.current_usage(str(helper)))

    def test_usage_fetch_hides_malformed_output_and_stderr(self):
        with tempfile.TemporaryDirectory() as directory:
            helper = Path(directory) / "codexbar"
            helper.write_text(f"#!{sys.executable}\nimport sys\nprint('secret-token', file=sys.stderr)\nprint('bad json')\n")
            helper.chmod(0o700)
            output = menu.current_usage(str(helper))
            self.assertIn("Could not read usage", output)
            self.assertNotIn("secret-token", output)
            self.assertNotIn("bad json", output)

    def test_usage_fetch_explains_missing_installation(self):
        with tempfile.TemporaryDirectory() as directory:
            output = menu.current_usage(str(Path(directory) / "missing"))
            self.assertIn("CodexBar is not installed yet", output)

    def test_usage_menu_shows_remaining_quota_and_local_reset(self):
        output = menu.usage_menu([
            {"provider": "claude", "usage": {"primary": {"usedPercent": 58}, "secondary": {"usedPercent": 90}}},
            {"provider": "codex", "usage": {"primary": {"usedPercent": 28, "resetsAt": "2026-10-13T12:00:00Z"}}},
        ])
        self.assertIn("C 42% · O 72%", output.splitlines()[0])
        self.assertIn("Weekly: 10% left", output)
        reset = datetime.fromisoformat("2026-10-13T12:00:00+00:00").astimezone().strftime("%a %d %b, %H:%M %Z")
        self.assertIn(f"Resets {reset}", output)
        self.assertIn("Refresh usage | refresh=true", output)

    def test_usage_menu_preserves_healthy_provider_when_other_fails(self):
        output = menu.usage_menu([
            {"provider": "claude", "error": {"message": "secret-token | bash=/tmp/bad"}},
            {"provider": "codex", "usage": {"primary": {"usedPercent": 100}}},
        ])
        self.assertIn("C ? · O 0%", output)
        self.assertIn("Claude: unavailable", output)
        self.assertNotIn("secret-token", output)

    def test_usage_menu_never_turns_missing_or_invalid_quota_into_zero(self):
        for value in (None, True, "25", float("nan"), -1):
            with self.subTest(value=value):
                output = menu.usage_menu([{"provider": "claude", "usage": {"primary": {"usedPercent": value}}}])
                self.assertIn("C ? · O ?", output.splitlines()[0])
                self.assertNotIn("0%", output)

    def test_usage_menu_handles_malformed_payload_without_injected_actions(self):
        for payload in (None, {}, [None], [{"provider": "claude", "usage": "bad"}]):
            with self.subTest(payload=payload):
                output = menu.usage_menu(payload)
                self.assertIn("C ? · O ?", output)
        output = menu.usage_menu([{"provider": "claude", "usage": {"primary": {
            "usedPercent": 20, "resetsAt": "bad\n---\nInjected | bash=/tmp/bad",
        }}}])
        self.assertNotIn("Injected", output)

    def test_workspace_menu_uses_native_space_indices_for_switch_and_send(self):
        state = {
            "current": 3,
            "spaces": [
                {"index": 1, "id": 11, "windows": 3},
                {"index": 3, "id": 22, "windows": 1},
            ],
        }
        output = menu.workspace_menu(state)
        self.assertIn("Desk 3", output)
        row = next((line for line in output.splitlines() if line.startswith("Desktop 3 ·")), "")
        self.assertIn("1 window", row)
        self.assertIn("checked=true", row)
        self.assertIn("href=hammerspoon://paperwm?action=switch&index=3", row)
        self.assertIn("href=hammerspoon://paperwm?action=send&index=3", output)
        self.assertNotIn("Desktop 2 ·", output)

    def test_workspace_menu_handles_daemon_startup_without_actions(self):
        output = menu.workspace_menu({"spaces": []})
        self.assertIn("Waiting for Hammerspoon", output)
        self.assertNotIn("action=switch", output)

    def test_fullscreen_space_still_offers_desktop_switching(self):
        output = menu.workspace_menu({"current": 2, "running": True, "spaces": [{"index": 1, "windows": 2}]})
        self.assertIn("Desk 2", output)
        self.assertIn("action=switch&index=1", output)
        self.assertIn("action=toggle", output)
        self.assertNotIn("Waiting for Hammerspoon", output)
        self.assertNotIn("checked=true", output)

    def test_paused_menu_hides_stale_counts_and_window_movement(self):
        output = menu.workspace_menu({"current": 1, "running": False, "spaces": [{"index": 1, "windows": 8}]})
        self.assertIn("PaperWM paused", output)
        self.assertIn("action=switch&index=1", output)
        self.assertNotIn("8 windows", output)
        self.assertNotIn("action=send", output)

    def test_world_clocks_follow_los_angeles_daylight_saving(self):
        winter = menu.clock_menu(datetime(2026, 1, 15, 12, tzinfo=timezone.utc))
        summer = menu.clock_menu(datetime(2026, 7, 15, 12, tzinfo=timezone.utc))
        self.assertTrue(winter)
        self.assertTrue(summer)
        self.assertIn("SG 20:00 · LA 04:00", winter.splitlines()[0])
        self.assertIn("SG 20:00 · LA 05:00", summer.splitlines()[0])

    def test_clocks_keep_the_date_correct_across_midnight(self):
        output = menu.clock_menu(datetime(2026, 1, 15, 2, tzinfo=timezone.utc))
        self.assertIn("Los Angeles: Wed 14 Jan, 18:00", output)
        self.assertIn("Singapore: Thu 15 Jan, 10:00", output)

    def test_track_metadata_cannot_create_swiftbar_actions_or_submenus(self):
        output = menu.media_menu("Spotify", "playing", "Artist\n---", "--Song | bash=/tmp/untrusted")
        self.assertTrue(output)
        lines = output.splitlines()
        self.assertIn("Artist --- · Song ¦ bash=/tmp/untrusted", lines[0])
        self.assertEqual(lines.count("---"), 1)
        self.assertNotIn("bash=/tmp/untrusted", lines[0].split(" | ")[1])
        self.assertIn('tell application "Spotify" to playpause', output)

    def test_unknown_players_cannot_create_applescript_actions(self):
        self.assertEqual(menu.media_menu('Spotify" to do shell script "bad', "playing", "Artist", "Song"), "")
        self.assertEqual(menu.media_menu("Spotify", "stopped", "Artist", "Song"), "")

    def test_paused_player_still_offers_playback_controls(self):
        output = menu.media_menu("Music", "paused", "Artist", "Song")
        self.assertIn("Paused", output)
        self.assertIn('tell application "Music" to playpause', output)


if __name__ == "__main__":
    unittest.main()
