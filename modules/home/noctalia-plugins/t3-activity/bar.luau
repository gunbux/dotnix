--!nonstrict
-- T3 Activity pill — like the T3 app's notification pill on Android: a filled
-- pill counting threads per state ("2 working · 1 done"), coloured by the most
-- urgent one. A dim icon when idle. Hover lists each thread with its machine,
-- project, branch and how long it has been at it, and says so when T3 Connect
-- could not be read.

-- Pill colours per state; "needs" groups approval and input.
local STATES = {
  needs = { glyph = "message-question", fill = "error", ink = "on_error" },
  failed = { glyph = "alert-triangle", fill = "error", ink = "on_error" },
  working = { glyph = "loader-2", fill = "primary", ink = "on_primary" },
  done = { glyph = "circle-check", fill = "secondary", ink = "on_secondary" },
}
local ORDER = { "needs", "failed", "working", "done" }
local STATE_OF = {
  waiting_for_input = "needs",
  waiting_for_approval = "needs",
  failed = "failed",
  running = "working",
  starting = "working",
  completed = "done",
}

local status = noctalia.state.get("status")
local probePath = "@t3Activity@" -- substituted by Nix

local function threads()
  if type(status) == "table" and type(status.threads) == "table" then
    return status.threads
  end
  return {}
end

local function elapsed(since)
  local age = os.time() - (tonumber(since) or os.time())
  if age < 60 then
    return "<1m"
  elseif age < 3600 then
    return `{math.floor(age / 60)}m`
  end
  return `{math.floor(age / 3600)}h{math.floor(age % 3600 / 60)}m`
end

-- A failed T3 Connect read, so a quiet bar is not mistaken for idle machines.
local function appendUnreachable(rows)
  if type(status) == "table" and type(status.connect) == "table" and not status.connect.ok then
    table.insert(rows, { key = noctalia.tr("tooltip.connect"), value = noctalia.tr("tooltip.connect_error") })
  end
end

local function render()
  local list = threads()
  local container = barWidget.isVertical() and ui.column or ui.row

  if #list == 0 then
    barWidget.render(container({ align = "center" }, {
      ui.glyph({ name = "sparkles", color = "on_surface_variant", size = 14 }),
    }))
    local rows = { { key = noctalia.tr("tooltip.idle"), value = "" } }
    appendUnreachable(rows)
    if #rows == 1 then
      barWidget.setTooltip(noctalia.tr("tooltip.idle"))
    else
      barWidget.setTooltip(rows)
    end
    return
  end

  local counts = {}
  for _, thread in ipairs(list) do
    local state = STATE_OF[thread.phase] or "working"
    counts[state] = (counts[state] or 0) + 1
  end
  local parts = {}
  local lead = nil
  for _, state in ipairs(ORDER) do
    if counts[state] then
      lead = lead or state
      table.insert(parts, `{counts[state]} {noctalia.tr(`pill.{state}`)}`)
    end
  end
  local style = STATES[lead]

  barWidget.render(container({
    gap = 4,
    align = "center",
    paddingH = 8,
    paddingV = 1,
    radius = 999,
    fill = style.fill,
  }, {
    ui.glyph({ name = style.glyph, color = style.ink, size = 13 }),
    ui.label({ text = table.concat(parts, " · "), color = style.ink, fontWeight = "bold" }),
  }))

  local rows = {}
  for i, thread in ipairs(list) do
    if i > 8 then
      break
    end
    local title = tostring(thread.title or "")
    if #title > 40 then
      title = string.sub(title, 1, 39) .. "…"
    end
    local value = noctalia.tr(`phase.{thread.phase}`)
    if thread.phase == "running" or thread.phase == "starting" then
      value ..= ` {elapsed(thread.since)}`
    end
    if thread.machine ~= nil and thread.machine ~= "" then
      value ..= ` · {thread.machine}`
    end
    if thread.project ~= nil and thread.project ~= "" then
      value ..= ` · {thread.project}`
    end
    if thread.branch ~= nil and thread.branch ~= "" then
      value ..= ` · {thread.branch}`
    end
    table.insert(rows, { key = title, value = value })
  end
  appendUnreachable(rows)
  barWidget.setTooltip(rows)
end

noctalia.state.watch("status", function(value)
  status = value
  render()
end)

function update()
  noctalia.setUpdateInterval(5000)
  render()
end

-- Like tapping the phone's notification: a thread waiting on you opens
-- straight away (the list is sorted most urgent first), as does a lone thread;
-- otherwise the panel lists them.
function onClick()
  local list = threads()
  local first = list[1]
  local waiting = first ~= nil and STATE_OF[first.phase] == "needs"
  if first ~= nil and (waiting or #list == 1) and first.url ~= nil and first.url ~= "" then
    noctalia.runAsync({ "xdg-open", first.url })
    noctalia.runAsync({ probePath, "--seen", first.id })
    return
  end
  noctalia.togglePanel("chun/t3-activity:threads")
end

render()
