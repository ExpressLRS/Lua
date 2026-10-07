---------------------------------------------------------------------------
-- B&W Telemetry Dashboard                                               --
-- Loaded via loadScript() with (Telemetry).                             --
---------------------------------------------------------------------------

local Telemetry = ...

local Dashboard = {}

local Dialogs

local TITLE_H = 9
local BAR_H = 5
local HERO_Y = 11
local LQ_BAR_Y = 27
local RSSI_Y = 34
local RSSI_BAR_Y = 41
local GRID_Y = 48
local GRID_LINE = 8
local MID = math.floor(LCD_W / 2)

local function dash(v, text)
  if v == nil or not Telemetry.isConnected() then
    return "--"
  end
  return text
end

function Dashboard.drawTitle()
  lcd.drawFilledRectangle(0, 0, LCD_W, TITLE_H)
  lcd.drawText(1, 1, "ExpressLRS", INVERS)
  local level = Telemetry.statusLevel()
  local STATUS = Telemetry.STATUS
  if level == STATUS.NO_TELEMETRY then
    lcd.drawText(LCD_W - 1, 2, "No telemetry", SMLSIZE + INVERS + RIGHT)
  elseif level == STATUS.MISMATCH then
    lcd.drawText(LCD_W - 1, 2, "MISMATCH!", SMLSIZE + INVERS + RIGHT + BLINK)
  elseif level == STATUS.OK then
    lcd.drawText(LCD_W - 1, 2, Telemetry.rfModeName() or "", SMLSIZE + INVERS + RIGHT)
  end
end

local function drawBar(y, pct)
  lcd.drawRectangle(0, y, LCD_W, BAR_H)
  if pct then
    local w = math.floor((LCD_W - 2) * math.max(0, math.min(100, pct)) / 100)
    if w > 0 then
      lcd.drawFilledRectangle(1, y + 1, w, BAR_H - 2)
    end
  end
end

local function drawHero()
  local link = Telemetry.link
  local connected = Telemetry.isConnected()
  local lq = connected and tostring(link.rqly or 0) or "--"
  lcd.drawText(1, HERO_Y, lq, DBLSIZE)
  lcd.drawText(36, HERO_Y + 8, "LQ %", SMLSIZE)
  if not connected or not Telemetry.hasDiversity() then
    return
  end
  local ant = Telemetry.activeAnt()
  if Telemetry.isXband() then
    lcd.drawText(LCD_W - 1, HERO_Y + 8, ant == 1 and "SubG" or "2.4", SMLSIZE + RIGHT)
  else
    lcd.drawText(LCD_W - 1, HERO_Y + 8, "Ant " .. ant, SMLSIZE + RIGHT)
  end
end

--- e.g. "-85 -92 / -112dBm"
local function signalText()
  local link = Telemetry.link
  local rssi = Telemetry.activeRssi()
  if rssi == nil or not Telemetry.isConnected() then
    return "--"
  end
  local text = tostring(rssi)
  if Telemetry.hasDiversity() then
    text = (link.rssi1 or "--") .. " " .. link.rssi2
  end
  if link.sens then
    text = text .. " / " .. link.sens
  end
  return text .. "dBm"
end

local function cellText()
  local vbat = Telemetry.link.vbat
  local cells = Telemetry.cellCnt
  if vbat == nil or vbat <= 0 or cells == nil then
    return "--"
  end
  return string.format("%dS %.2fV", cells, vbat / cells)
end

local function drawCell(x, right, y, caption, text)
  lcd.drawText(x, y, caption, SMLSIZE)
  lcd.drawText(right, y, text, SMLSIZE + RIGHT)
end

local function drawGrid()
  local link = Telemetry.link
  local y2 = GRID_Y + GRID_LINE
  drawCell(1, MID - 3, GRID_Y, "PWR", dash(link.tpwr, (link.tpwr or "") .. "mW"))
  drawCell(1, MID - 3, y2, "BATT", cellText())
  drawCell(MID + 2, LCD_W - 1, GRID_Y, "TQly", dash(link.tqly, (link.tqly or "") .. "%"))
  drawCell(MID + 2, LCD_W - 1, y2, "TRSS", dash(link.trss, (link.trss or "") .. "dBm"))
end

function Dashboard.draw()
  if not Telemetry.hasModule() then
    Dialogs = Dialogs or loadScript("/SCRIPTS/ELRS/ui/lcd/dialogs.lua")()
    Dialogs.drawNoModule()
    return
  end
  lcd.clear()
  Dashboard.drawTitle()
  drawHero()
  drawBar(LQ_BAR_Y, Telemetry.isConnected() and Telemetry.link.rqly)
  drawCell(1, LCD_W - 1, RSSI_Y, "RSSI", signalText())
  drawBar(RSSI_BAR_Y, Telemetry.headroomPct)
  drawGrid()
end

return Dashboard
