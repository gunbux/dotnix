--!nonstrict
-- T3 Activity panel — every active thread; clicking a row opens it in T3.

local PHASES = {
  waiting_for_input = { glyph = "message-question", color = "error" },
  waiting_for_approval = { glyph = "hand-stop", color = "error" },
  failed = { glyph = "alert-triangle", color = "error" },
  running = { glyph = "loader-2", color = "primary" },
  starting = { glyph = "loader-2", color = "on_surface_variant" },
  completed = { glyph = "circle-check", color = "secondary" },
}

local status = noctalia.state.get("status")

local function render()
  local list = {}
  if type(status) == "table" and type(status.threads) == "table" then
    list = status.threads
  end

  if #list == 0 then
    panel.render(ui.column({ gap = 10, align = "center" }, {
      ui.glyph({ name = "sparkles", color = "on_surface_variant", size = 28 }),
      ui.label({ text = noctalia.tr("panel.idle"), color = "on_surface_variant", fontSize = 14 }),
    }))
    return
  end

  local rows = {}
  for _, thread in ipairs(list) do
    local style = PHASES[thread.phase] or PHASES.running
    local detail = noctalia.tr(`phase.{thread.phase}`)
    if thread.machine ~= nil and thread.machine ~= "" then
      detail ..= ` · {thread.machine}`
    end
    if thread.project ~= nil and thread.project ~= "" then
      detail ..= ` · {thread.project}`
    end
    if thread.branch ~= nil and thread.branch ~= "" then
      detail ..= ` · {thread.branch}`
    end
    local url = thread.url
    table.insert(rows, ui.row({
      key = thread.id,
      gap = 10,
      align = "center",
      padding = 8,
      radius = 8,
      tooltip = noctalia.tr("panel.open"),
      onClick = function()
        if url ~= nil and url ~= "" then
          noctalia.runAsync({ "xdg-open", url })
          noctalia.togglePanel("chun/t3-activity:threads")
        end
      end,
    }, {
      ui.glyph({ name = style.glyph, color = style.color, size = 18 }),
      ui.column({ gap = 2 }, {
        ui.label({
          text = tostring(thread.title or ""),
          color = "on_surface",
          fontSize = 13,
          fontWeight = "bold",
          maxLines = 1,
          maxWidth = 420,
        }),
        ui.label({
          text = detail,
          color = style.color,
          fontSize = 12,
          maxLines = 1,
          maxWidth = 420,
        }),
      }),
    }))
  end

  panel.render(ui.column({ gap = 4 }, rows))
end

noctalia.state.watch("status", function(value)
  status = value
  render()
end)

function onOpen()
  status = noctalia.state.get("status")
  render()
end

render()
