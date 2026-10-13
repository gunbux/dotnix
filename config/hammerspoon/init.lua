-- Don't initialize window filters or event taps before Accessibility is granted.
-- Reload into a fresh Lua runtime when permission becomes available.
if not hs.accessibilityState() then
  hs.printf("PaperWM is waiting for Hammerspoon Accessibility permission.")
  PaperWMPermissionTimer = hs.timer.doEvery(2, function()
    if hs.accessibilityState() then
      PaperWMPermissionTimer:stop()
      hs.reload()
    end
  end)
  return
end

-- PaperWM is pinned by Nix and loaded from ~/.hammerspoon/Spoons.
PaperWM = hs.loadSpoon("PaperWM")
local prune_closed_windows = dofile(hs.configdir .. "/cleanup.lua")(PaperWM)
hs.window.animationDuration = 0
PaperWM.window_gap = 8
PaperWM.window_ratios = { 1 / 3, 1 / 2, 2 / 3, 1 }
PaperWM.default_width = 0.5
PaperWM.center_mouse = false
PaperWM.move_window_keep_space = true
PaperWM.scroll_window = { "alt" }
PaperWM.scroll_gain = 4
-- Preserve macOS's existing trackpad gestures for Spaces.
PaperWM.swipe_fingers = 0
PaperWM.window_filter:rejectApp("System Settings")
-- Finder stays running after closing its windows; keep it outside the tiled strip.
PaperWM.window_filter:rejectApp("Finder")

local running = true
local keys = {
  focus_left = { { "alt" }, "h" },
  focus_down = { { "alt" }, "j" },
  focus_up = { { "alt" }, "k" },
  focus_right = { { "alt" }, "l" },
  swap_left = { { "alt", "ctrl" }, "h" },
  swap_down = { { "alt", "ctrl" }, "j" },
  swap_up = { { "alt", "ctrl" }, "k" },
  swap_right = { { "alt", "ctrl" }, "l" },
  switch_space_l = { { "alt" }, "i" },
  switch_space_r = { { "alt" }, "u" },
  switch_recent_space = { { "alt" }, "tab" },
  center_window = { { "alt" }, "c" },
  full_width = { { "alt" }, "f" },
  cycle_width = { { "alt" }, "r" },
  reverse_cycle_width = { { "alt" }, "-" },
  increase_width = { { "alt" }, "=" },
  cycle_height = { { "alt", "shift" }, "r" },
  toggle_floating = { { "alt" }, "g" },
  toggle_stack = { { "alt" }, "w" },
  slurp_in = { { "alt" }, "[" },
  barf_out = { { "alt" }, "]" },
  refresh_windows = { { "alt", "shift" }, "t" },
}
for index = 1, 9 do
  keys["switch_space_" .. index] = { { "alt" }, tostring(index) }
  keys["move_window_" .. index] = { { "alt", "ctrl" }, tostring(index) }
end
local actions = PaperWM.actions.actions()
local guarded_actions = {}
for name, callback in pairs(actions) do
  guarded_actions[name] = function(...)
    if running or name:match("^switch_") then return callback(...) end
  end
end
hs.spoons.bindHotkeysToSpec(guarded_actions, keys)
for key, direction in pairs({ left = "left", down = "down", up = "up", right = "right" }) do
  hs.hotkey.bind({ "alt" }, key, guarded_actions["focus_" .. direction])
  hs.hotkey.bind({ "alt", "ctrl" }, key, guarded_actions["swap_" .. direction])
end
hs.hotkey.bind({ "alt" }, "return", function() hs.application.launchOrFocus("Ghostty") end)
hs.hotkey.bind({ "alt" }, "b", function() hs.application.launchOrFocus("Zen") end)

local function toggle_paperwm()
  if running then PaperWM:stop() else PaperWM:start() end
  running = not running
end
-- A recovery shortcut releases control and brings tiled windows into bounds.
hs.hotkey.bind({ "alt", "shift" }, "escape", toggle_paperwm)

PaperWM:start()
PaperWMCleanupTimer = hs.timer.doEvery(2, function()
  if running then prune_closed_windows() end
end)
hs.shutdownCallback = function()
  PaperWM:stop()
end
