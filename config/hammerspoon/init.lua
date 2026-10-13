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

local state_file = "@state_file@"

-- Match PaperWM's native Space numbering, including gaps for fullscreen apps.
local function workspace_status()
  local focused = hs.spaces.focusedSpace()
  local layout = hs.spaces.allSpaces() or {}
  local windows = PaperWM.state.get().window_list
  local result = { running = running, spaces = {} }
  local index = 0
  for _, screen in ipairs(hs.screen.allScreens()) do
    for _, space_id in ipairs(layout[screen:getUUID()] or {}) do
      index = index + 1
      if space_id == focused then result.current = index end
      if hs.spaces.spaceType(space_id) == "user" then
        local count = 0
        for _, column in ipairs(windows[space_id] or {}) do count = count + #column end
        table.insert(result.spaces, { index = index, id = space_id, windows = count })
      end
    end
  end
  return result
end

local function publish_status()
  if running then prune_closed_windows() end
  local file = io.open(state_file .. ".tmp", "w")
  if not file then return end
  file:write(hs.json.encode(workspace_status()))
  file:close()
  os.rename(state_file .. ".tmp", state_file)
end

local function toggle_paperwm()
  if running then PaperWM:stop() else PaperWM:start() end
  running = not running
  publish_status()
end
-- A recovery shortcut releases control and brings tiled windows into bounds.
hs.hotkey.bind({ "alt", "shift" }, "escape", toggle_paperwm)

hs.urlevent.bind("paperwm", function(_, params)
  if params.action == "toggle" then toggle_paperwm(); return end
  local index = tonumber(params.index)
  if not index or index ~= math.floor(index) or index < 1 or index > 99 then return end
  local space_id = PaperWM.space.MissionControl:getSpaceID(index)
  if not space_id or hs.spaces.spaceType(space_id) ~= "user" then return end
  if params.action == "switch" then
    PaperWM.space.switchToSpace(index)
  elseif params.action == "send" and running then
    PaperWM.space.moveWindowToSpace(index)
  end
end)

PaperWM:start()
publish_status()
-- Store only counts and Space IDs, never application names or window titles.
PaperWMStatusTimer = hs.timer.doEvery(2, publish_status)
hs.shutdownCallback = function()
  PaperWM:stop()
  os.remove(state_file)
end
