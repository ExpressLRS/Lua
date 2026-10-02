---------------------------------------------------------------------------
-- Color LCD Dialogs                                                     --
---------------------------------------------------------------------------

local Dialogs = {}

function Dialogs.showConfirm(title, message, onConfirm)
  return lvgl.confirm({ title = title, message = message, confirm = onConfirm })
end

function Dialogs.showMessage(title, message)
  return lvgl.message({ title = title, message = message })
end

-- lines: label descriptors { text, font }, used as children
local function buildDialog(title, lines, onClose)
  local dg = lvgl.dialog({
    title = title,
    flexFlow = lvgl.FLOW_COLUMN,
    flexPad = lvgl.PAD_SMALL,
    close = onClose,
  })

  dg:build({
    {
      type = lvgl.BOX,
      x = 10,
      flexFlow = lvgl.FLOW_COLUMN,
      flexPad = lvgl.PAD_SMALL,
      children = lines,
    },
    {
      type = lvgl.BOX,
      w = lvgl.PERCENT_SIZE + 100,
      align = CENTER,
      flexFlow = lvgl.FLOW_ROW,
      children = {
        {
          type = lvgl.BUTTON,
          w = lvgl.PERCENT_SIZE + 98,
          text = "Close",
          press = function()
            dg:close()
            if onClose then
              onClose()
            end
          end,
        },
      },
    },
  })

  return dg
end

function Dialogs.showInfo(title, message)
  return buildDialog(title, { { type = lvgl.LABEL, text = message } })
end

local function buildExitDialog(title, lines, onExit)
  lvgl.clear()
  return buildDialog(title, lines, onExit)
end

function Dialogs.showVersionRequired(versions, onExit)
  local lines = { { type = lvgl.LABEL, text = "Requires EdgeTX:" } }
  for i, version in ipairs(versions) do
    lines[i + 1] = { type = lvgl.LABEL, text = version }
  end
  return buildExitDialog("EdgeTX Version Not Supported", lines, onExit)
end

function Dialogs.noModuleChecklist(color)
  return {
    { type = lvgl.LABEL, color = color, text = "- Internal/External module enabled" },
    {
      type = lvgl.LABEL,
      color = color,
      font = SMLSIZE,
      text = "  Internal: set Internal RF type to CRSF in SYS > Hardware",
    },
    { type = lvgl.LABEL, color = color, text = "- Protocol set to CRSF" },
    { type = lvgl.LABEL, color = color, text = "- Suggested baud rate (depends on packet rate):" },
    { type = lvgl.LABEL, color = color, font = SMLSIZE, text = "  400k for 250Hz, 921k for 500Hz, 1.87M for 1000Hz" },
  }
end

function Dialogs.showNoModule(onExit)
  return buildExitDialog("No Module Found: Check Model Settings", Dialogs.noModuleChecklist(), onExit)
end

return Dialogs
