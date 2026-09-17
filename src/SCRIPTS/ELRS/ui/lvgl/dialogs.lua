---------------------------------------------------------------------------
-- Color LCD Dialogs                                                     --
-- Loaded via loadScript() with no arguments; returns the Dialogs table. --
-- Shared by every tool's LVGL UI; the widgets' full-screen pages reuse  --
-- the no-module checklist.                                              --
--                                                                       --
-- The version gate and the missing-module notice are terminal -- the    --
-- only way out is exiting the tool -- so each takes the caller's onExit --
-- and wires it to both the dialog's close box and its Exit button.      --
---------------------------------------------------------------------------

local Dialogs = {}

function Dialogs.showConfirm(options)
  return lvgl.confirm({
    title = options.title,
    message = options.message,
    confirm = options.onConfirm,
    cancel = options.onCancel,
  })
end

function Dialogs.showMessage(options)
  return lvgl.message({
    title = options.title,
    message = options.message,
  })
end

--- Build a full-screen dialog: a column of text lines over a single Exit
-- button. lines are label descriptors ({ text = ..., font = ... }), used
-- verbatim as children.
local function buildExitDialog(title, lines, onExit)
  lvgl.clear()

  local dg = lvgl.dialog({
    title = title,
    flexFlow = lvgl.FLOW_COLUMN,
    flexPad = lvgl.PAD_SMALL,
    close = onExit,
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
          text = "Exit",
          press = function()
            dg:close()
            onExit()
          end,
        },
      },
    },
  })

  return dg
end

--- The EdgeTX version gate.
-- @param versions  REQUIRED_VERSIONS from SCRIPTS/ELRS/edgetx_version.lua
function Dialogs.showVersionRequired(versions, onExit)
  local lines = { { type = lvgl.LABEL, text = "Requires EdgeTX:" } }
  for i, version in ipairs(versions) do
    lines[i + 1] = { type = lvgl.LABEL, text = version }
  end
  return buildExitDialog("EdgeTX Version Not Supported", lines, onExit)
end

--- Label rows listing what to check when no CRSF module is found.
-- @param color  optional text color
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

--- No CRSF module configured on the model.
function Dialogs.showNoModule(onExit)
  return buildExitDialog("No Module Found: Check Model Settings", Dialogs.noModuleChecklist(), onExit)
end

return Dialogs
