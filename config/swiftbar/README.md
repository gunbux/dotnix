# Native macOS desktop

The Mac configuration uses PaperWM through Hammerspoon for scrolling columns,
SwiftBar for world clocks and media controls, and Stats for system monitoring.
Hammerspoon, SwiftBar and Stats start through Home Manager's launchd services. The existing macOS menu bar
keeps its application menus and system controls; no separate bar is drawn.

## Apply

From the repository root:

```sh
nh darwin switch "path:$PWD" -H greptile-mac
```

The `path:` reference includes new files before Git tracks them. Once tracked,
the usual `nh darwin switch . -H greptile-mac` also works.

Home Manager removes its previous Paneru, AeroSpace and SketchyBar services
when activating this configuration. Avoid additional login items or Homebrew
services for those window managers. Allow the new background items if macOS asks.

Grant **Hammerspoon** Accessibility permission in System Settings > Privacy &
Security. If it does not start after granting permission:

```sh
launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.hammerspoon"
```

PaperWM waits to initialize until Accessibility is available, then reloads the
configuration. If macOS shows permission enabled but scrolling or keyboard
navigation cannot reach every window, restart the service with the command above.
A stale Hammerspoon process can retain closed windows and lose its scroll event
tap after a permission change; a full restart rebuilds that state.

Home Manager manages `~/.hammerspoon/init.lua` and the PaperWM spoon. Back up
unmanaged files at those paths before activation. Hammerspoon itself is installed
through the host's Homebrew casks; PaperWM's source is pinned in `flake.lock`.
SwiftBar's plugin folder is configured at `~/.config/swiftbar/plugins`. Its
Spotify/Music plugin may request Automation permission. It queries only running
players and hides when none has a track.

## Scrolling windows

PaperWM opens windows as columns on a horizontal strip. New windows start at
half the display width. Hold Option while scrolling to slide between columns.
Animation duration is set to zero and scroll gain to four for this trial.
Native macOS Spaces gestures remain available.

| Shortcut | Action |
| --- | --- |
| Option + H/L or Left/Right | Focus previous/next column |
| Option + J/K or Down/Up | Focus within a stack |
| Option + Control + H/J/K/L or arrows | Swap windows |
| Option + I/U | Previous/next native Space |
| Option + Tab | Return to recent Space |
| Option + 1–9 | Select native Space |
| Option + Control + 1–9 | Send window to native Space |
| Option + R | Cycle width |
| Option + Equal / Minus | Increase width / reverse width cycle |
| Option + Shift + R | Cycle stacked window height |
| Option + F | Toggle full width |
| Option + G | Toggle managed/floating window |
| Option + C | Center column |
| Option + Left/Right Bracket | Stack/unstack window |
| Option + W | Toggle tabbed stack |
| Option + Shift + T | Refresh windows |
| Option + Shift + Escape | Pause/resume PaperWM; pausing brings windows into bounds |
| Option + Return | Open Ghostty |
| Option + B | Open Zen |

Create additional desktops in Mission Control first; PaperWM uses existing native
Spaces. Numbering includes fullscreen Spaces, so the menu may skip a number.
SwiftBar shows the active desktop and tiled window counts across displays.
Click a desktop to switch, or hold Option while clicking to send the focused
window there. The menu also offers pause/resume. Its snapshot contains only Space
IDs and counts, and refreshes every two seconds.

For multiple monitors, enable "Displays have separate Spaces" and arrange the
displays above/below one another in System Settings. Horizontally adjacent
displays can cause macOS to move off-screen windows onto the wrong monitor.
Thin window slivers at the edges are an expected macOS workaround. Native Space
switching still uses macOS's transitions; this trial cannot guarantee Niri's
animation behavior. No SIP changes are required.

Finder windows remain floating as a workaround for closed-window tracking failures.
They are excluded from PaperWM navigation and the tiled window counts.

Closed-window cleanup handles missed destroy/visibility events in other apps.
It removes zero-size stale entries
from the layout every two seconds while keeping valid offscreen columns. When
closing a window leaves the desktop focused, it focuses a remaining tiled window.

Use Hammerspoon's menu to open its console or reload the configuration. Windows
already minimized by Paneru may need to be restored from the Dock.

## Menu bar

SwiftBar shows the Singapore and Los Angeles times as `SG 13:20 · LA 22:20`.
Its clock dropdown includes
dates and the local time when travelling outside those offsets. The media item
shows Spotify or Music and offers play/pause, next/previous, and open-player
actions. Command-drag menu items to reorder them.

Stats enables CPU, memory, disk, and network monitoring. Its popups provide more
detail; widget styles can be adjusted in Stats settings. Heavy sensors and
duplicate battery/Bluetooth widgets are disabled. Apple's native Control Center
provides volume, brightness, Wi-Fi, Bluetooth, and other system controls. Battery
percentage is enabled in the native menu bar.

SwiftBar and Stats updates stay under Nix control. Hammerspoon uses Homebrew. Nix reapplies the configured Stats module
selection during activation; other widget settings remain adjustable in its UI.

SwiftBar's compact AI item uses `C` for Claude and `O` for OpenAI Codex, for example
`C 42% · O 72%`. These values are session quota **remaining**, with weekly
quota and reset times in the dropdown. It refreshes every five minutes; opening
the menu keeps the current snapshot, and **Refresh usage** requests a new one.
Missing data appears as `?` rather than zero. A failed refresh replaces the old
snapshot with unavailable data. If CodexBar returns a saved snapshot over ten
minutes old, the bar marks it `(stale)` and the dropdown shows its update time.

The Mac's declarative Homebrew casks install CodexBar. SwiftBar calls
`/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI` directly, so no CLI
symlink or running CodexBar app is needed. The widget explicitly uses OAuth and
reuses the local Claude Code and Codex logins. Sign in with `claude` and
`codex login` first. API-key-only accounts do not supply subscription quota.
Credentials and CodexBar's mutable settings stay outside the Nix store.
Claude on macOS may need a one-time OAuth Keychain access grant in CodexBar's
settings. Enable Claude, choose OAuth, and use its explicit Refresh action to
complete setup. Background polls do not request that permission interactively.
The dropdown's **Configure CodexBar** action opens the app for setup or diagnosis;
quit it afterward if you only want SwiftBar's item.

Usage belongs to the selected local accounts. A remote Paseo daemon using another
account needs its own usage collector. This widget does not measure per-agent
token totals or API spending. See the
[CodexBar CLI documentation](https://github.com/steipete/CodexBar/blob/main/docs/cli.md).

The custom Noctalia Bongo Cat, OCR, Nix update, phone, public IP, and
Tailscale widgets have not been ported. This replaces the functionality of the
previous Mac bar while keeping the native macOS presentation.

Menu renderer checks:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p test_macos_bar.py
```
