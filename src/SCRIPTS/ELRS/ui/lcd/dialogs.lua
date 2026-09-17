---------------------------------------------------------------------------
-- B&W Dialogs                                                           --
-- Loaded via loadScript() with no arguments; returns the Dialogs table. --
-- Shared by every tool's B&W UI.                                        --
--                                                                       --
-- Full-screen dialog: MIDSIZE title, body lines, and an optional row of --
-- action labels along the bottom. Redrawn every frame; the caller       --
-- handles the keys.                                                     --
---------------------------------------------------------------------------

local Dialogs = {}

-- B&W text row height
local TEXT_H = 8

--- Clear the screen and draw a dialog.
-- @param title    heading, drawn MIDSIZE
-- @param lines    array of body lines
-- @param actions  optional { left, right } action labels for the bottom row
function Dialogs.draw(title, lines, actions)
  lcd.clear()
  local y = 0
  lcd.drawText(2, y, title, MIDSIZE)
  y = y + (TEXT_H * 2) - 2
  for _, line in ipairs(lines) do
    lcd.drawText(2, y, line)
    y = y + TEXT_H
  end
  if actions then
    y = y + TEXT_H
    if actions.left then
      lcd.drawText(2, y, actions.left, 0)
    end
    if actions.right then
      lcd.drawText(LCD_W - 2, y, actions.right, RIGHT)
    end
  end
end

--- The EdgeTX version gate.
-- @param versions  REQUIRED_VERSIONS from SCRIPTS/ELRS/edgetx_version.lua
function Dialogs.drawVersionRequired(versions)
  local lines = { "Requires EdgeTX:" }
  for i, version in ipairs(versions) do
    lines[i + 1] = version
  end
  Dialogs.draw("Unsupported", lines)
end

--- No CRSF module configured on the model.
function Dialogs.drawNoModule()
  Dialogs.draw(" No ExpressLRS", {
    "Enable a CRSF Internal",
    "  or External module in",
    "      Model settings",
    " If module is internal",
    "also set Internal RF to",
    "CRSF in SYS->Hardware",
  })
end

return Dialogs
