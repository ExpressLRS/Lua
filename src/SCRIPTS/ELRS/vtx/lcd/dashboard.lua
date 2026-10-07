---------------------------------------------------------------------------
-- B&W VTX Admin Dashboard                                               --
---------------------------------------------------------------------------

local VTXAdmin, PresetsStorage, labels = ...

local Dashboard = {}

local Dialogs

local TITLE_H = 9
local CELL_H = 11
local CELL_GAP = 2
local CELL_W = math.floor((LCD_W - 4 - 5 * CELL_GAP) / 6)
local CELLS_X = math.floor((LCD_W - (6 * CELL_W + 5 * CELL_GAP)) / 2)
local CELLS_Y = LCD_H - CELL_H - 2
local HERO_H = 14 -- DBLSIZE cap height
local SIDE_X = LCD_W - 40 -- fits "Power 8"

local function presetsShown()
  return PresetsStorage.enabled
end

--- The VTX's tuning, not the switch: they differ after boot. Switch breaks ties.
local function activePreset()
  if not VTXAdmin.isTuned() then
    return nil
  end
  local s = VTXAdmin.state
  local items = PresetsStorage.items
  local pos = PresetsStorage.latch.lastPos
  if pos > 0 and items[pos].band == s.band and items[pos].channel == s.channel then
    return pos
  end
  for i = 1, 6 do
    if items[i].band == s.band and items[i].channel == s.channel then
      return i
    end
  end
end

local function drawTitle()
  lcd.drawFilledRectangle(0, 0, LCD_W, TITLE_H)
  lcd.drawText(1, 1, "VTX Admin", INVERS)
  if VTXAdmin.isSending() then
    lcd.drawText(LCD_W - 1, 1, "Sending", INVERS + RIGHT)
  end
end

local function drawCells()
  local active = activePreset()
  local items = PresetsStorage.items
  for i = 1, 6 do
    local x = CELLS_X + (i - 1) * (CELL_W + CELL_GAP)
    local p = items[i]
    local text = labels.preset(p.band, p.channel)
    if i == active then
      lcd.drawFilledRectangle(x, CELLS_Y, CELL_W, CELL_H)
      lcd.drawText(x + math.floor(CELL_W / 2) + 1, CELLS_Y + 2, text, INVERS + CENTER)
    else
      lcd.drawRectangle(x, CELLS_Y, CELL_W, CELL_H)
      lcd.drawText(x + math.floor(CELL_W / 2) + 1, CELLS_Y + 2, text, CENTER)
    end
  end
end

local function drawHero(top, bottom)
  local y = top + math.floor((bottom - top - HERO_H) / 2)
  if not VTXAdmin.isActive() then
    lcd.drawText(LCD_W / 2, y + 4, VTXAdmin.statusText, CENTER)
    return
  end
  local s = VTXAdmin.state
  if s.band == 0 then
    lcd.drawText(LCD_W / 2, y, "VTX Off", DBLSIZE + CENTER)
    return
  end
  lcd.drawText(4, y, labels.preset(s.band, s.channel), DBLSIZE)
  if not VTXAdmin.hasPower() then
    return
  end
  lcd.drawText(SIDE_X, y - 1, labels.power(s.power))
  if s.pitmode then
    lcd.drawText(SIDE_X, y + 8, "PIT ON", INVERS)
  elseif s.pitmodeAux then
    lcd.drawText(SIDE_X, y + 8, "Pit " .. s.pitmodeAux)
  else
    lcd.drawText(SIDE_X, y + 8, "Pit Off")
  end
end

function Dashboard.draw()
  if not VTXAdmin.hasModule() then
    Dialogs = Dialogs or loadScript("/SCRIPTS/ELRS/ui/lcd/dialogs.lua")()
    Dialogs.drawNoModule()
    return
  end
  lcd.clear()
  drawTitle()
  if presetsShown() then
    drawHero(TITLE_H, CELLS_Y)
    drawCells()
  else
    drawHero(TITLE_H, LCD_H)
  end
end

return Dashboard
