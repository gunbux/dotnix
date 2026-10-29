--!nonstrict
-- T3 Activity watcher — headless [[service]] entry.
-- Each tick runs the t3-activity probe (pkgs/t3-activity) and publishes its
-- thread list as "status". With T3 Connect on, the probe also returns the
-- other linked machines' threads; it caches the relay fetch itself. Nix
-- substitutes the probe path below.

local checking = false
local sweepAt = 0
local probePath = "@t3Activity@"
local connectError = nil -- logged once per change, not every tick

local function cfg(key, fallback)
  local value = noctalia.getConfig(key)
  if value == nil then
    return fallback
  end
  return value
end

local function interval()
  return math.clamp(tonumber(cfg("poll_interval", 2)) or 2, 1, 30)
end

function onConfigChanged()
  checking = false
end

function update()
  noctalia.setUpdateInterval(interval() * 1000)
  if checking and os.time() - sweepAt < interval() + 8 then
    return -- previous probe still running
  end
  checking = true
  sweepAt = os.time()

  local argv = {
    probePath,
    "--home",
    noctalia.expandPath(tostring(cfg("t3_home", "~/.t3"))),
    "--finished-window",
    tostring(tonumber(cfg("finished_window", 30)) or 30),
  }
  if cfg("t3_connect", true) then
    table.insert(argv, "--relay")
  end

  local ok = noctalia.runAsync(argv, function(result)
    checking = false
    if result.timedOut or result.exitCode ~= 0 then
      noctalia.log(`[t3-activity] probe failed: {result.timedOut and "timed out" or "exit " .. tostring(result.exitCode)}`)
      return
    end
    local decoded = noctalia.json.decode(result.stdout)
    if type(decoded) ~= "table" or type(decoded.threads) ~= "table" then
      noctalia.log("[t3-activity] unparseable probe output")
      return
    end
    local err = type(decoded.connect) == "table" and decoded.connect.error or nil
    if err ~= connectError and err ~= nil then
      noctalia.log(`[t3-activity] T3 Connect: {err}`)
    end
    connectError = err
    noctalia.state.set("status", decoded)
  end, 20000)
  if not ok then
    checking = false
  end
end
