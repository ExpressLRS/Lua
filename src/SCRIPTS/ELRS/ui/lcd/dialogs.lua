---------------------------------------------------------------------------
-- B&W Dialogs                                                           --
---------------------------------------------------------------------------

local Dialogs = {}

local TEXT_H = 8

--- actions: optional { left, right } labels
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

function Dialogs.drawVersionRequired(versions)
  local lines = { "Requires EdgeTX:" }
  for i, version in ipairs(versions) do
    lines[i + 1] = version
  end
  Dialogs.draw("Unsupported", lines)
end

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
