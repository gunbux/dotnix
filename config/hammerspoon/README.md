# Native macOS desktop

The Mac configuration uses PaperWM through Hammerspoon for scrolling columns,
CodexBar for Claude/Codex usage, and Stats for CPU monitoring.
Hammerspoon, CodexBar and Stats start through Home Manager's launchd services.
The existing macOS menu bar
keeps its application menus and system controls; no separate bar is drawn.

## Apply

From the repository root:

```sh
nh darwin switch "path:$PWD" -H greptile-mac
```

The `path:` reference includes new files before Git tracks them. Once tracked,
the usual `nh darwin switch . -H greptile-mac` also works.

Home Manager removes its previous SwiftBar, Paneru, AeroSpace and SketchyBar services
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
Spaces. Numbering includes fullscreen Spaces, so shortcuts may skip a desktop.

For multiple monitors, enable "Displays have separate Spaces" and arrange the
displays above/below one another in System Settings. Horizontally adjacent
displays can cause macOS to move off-screen windows onto the wrong monitor.
Thin window slivers at the edges are an expected macOS workaround. Native Space
switching still uses macOS's transitions; this trial cannot guarantee Niri's
animation behavior. No SIP changes are required.

Finder windows remain floating as a workaround for closed-window tracking failures.
They are excluded from PaperWM navigation.

Closed-window cleanup handles missed destroy/visibility events in other apps.
It removes zero-size stale entries
from the layout every two seconds while keeping valid offscreen columns. When
closing a window leaves the desktop focused, it focuses a remaining tiled window.
Cleanup pauses while the screen is locked, and windows are refreshed after
unlocking or waking so offscreen columns are re-adopted.

Use Hammerspoon's menu to open its console or reload the configuration. Windows
already minimized by Paneru may need to be restored from the Dock.

## Menu bar

CodexBar provides the native Claude and Codex usage menus. Configure enabled
providers and account access in CodexBar's settings. It can reuse local Claude
Code and Codex logins; credentials and mutable settings stay outside the Nix store.
CodexBar is installed through the host's Homebrew casks and starts through Home
Manager. Avoid enabling a duplicate login item for it.

Stats shows CPU monitoring. Memory, disk, network, and other metric widgets are
disabled by default; you can enable them in Stats settings. Nix reapplies the
configured module selection during activation, while widget styling stays
adjustable in the UI. Stats updates are managed by Nix.

Apple's native menu bar and Control Center provide the clock, battery, volume,
brightness, Wi-Fi, Bluetooth, and other system controls. SwiftBar and its custom
plugins are no longer installed or started by this configuration.
