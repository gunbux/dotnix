-- The pinned PaperWM can retain destroyed windows when visibility events are missed.
return function(paperwm)
  local function remove_closed(windows)
    local changed = {}
    for _, window in ipairs(windows) do
      if paperwm.state.windowIndex(window) then
        -- Keep the current focus while removing stale entries from any Space.
        local space = paperwm.windows.removeWindow(window, true)
        if space then changed[space] = true end
      end
    end
    for space in pairs(changed) do paperwm:tileSpace(space) end

    -- Closing Finder's last window leaves its desktop focused, with no window.
    -- Give navigation a live anchor, without stealing focus from another app.
    local current = hs.spaces.focusedSpace()
    if changed[current] and not hs.window.focusedWindow() then
      local columns = paperwm.state.get().window_list[current] or {}
      for _, column in ipairs(columns) do
        for _, window in ipairs(column) do
          local frame = window:frame()
          if frame.w > 0 and frame.h > 0 then window:focus(); return end
        end
      end
    end
  end

  local original = paperwm.events.windowEventHandler
  paperwm.events.windowEventHandler = function(window, event, self)
    if event == "windowDestroyed" and not self.floating.isFloating(window) then
      remove_closed({ window })
      return
    end
    return original(window, event, self)
  end

  return function()
    -- A destroyed AX window has zero geometry. Valid offscreen columns retain
    -- their width and height, so checking position/visibility would be incorrect.
    local stale = {}
    for _, columns in pairs(paperwm.state.get().window_list) do
      for _, column in ipairs(columns) do
        for _, window in ipairs(column) do
          local frame = window:frame()
          if frame.w == 0 and frame.h == 0 then table.insert(stale, window) end
        end
      end
    end
    if #stale > 0 then remove_closed(stale) end
  end
end
