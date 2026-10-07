---------------------------------------------------------------------------
-- B&W Telemetry Details                                                 --
-- Loaded via loadScript() with (Telemetry, Dashboard) on ENTER, dropped --
-- on exit. run(event) returns true when closed.                         --
---------------------------------------------------------------------------

local Telemetry, Dashboard = ...

local ROW_H = 8
local ROW_Y = 11
local ROW_COUNT = math.floor((LCD_H - ROW_Y) / ROW_H)

local link = Telemetry.link

local function connected(v)
  return v ~= nil and Telemetry.isConnected()
end

local function rfMode()
  return Telemetry.isConnected() and Telemetry.rfModeName() or nil
end

local function lq()
  return Telemetry.isConnected() and (link.rqly or 0) .. "%" or nil
end

local function rssi()
  if not connected(link.rssi1) then
    return nil
  end
  if Telemetry.hasDiversity() then
    return link.rssi1 .. " / " .. link.rssi2 .. "dBm"
  end
  return link.rssi1 .. "dBm"
end

local function snr()
  if not connected(link.rsnr) then
    return nil
  end
  if not Telemetry.hasSnr() then
    return "n/a" -- FLRC: the sensor is a permanent 0, not a reading
  end
  return link.rsnr .. "dB"
end

local function antLabel()
  return Telemetry.isXband() and "Active Band" or "Active Antenna"
end

local function ant()
  if not Telemetry.isConnected() then
    return nil
  end
  if not Telemetry.hasDiversity() then
    return "N/A"
  end
  if Telemetry.isXband() then
    return Telemetry.activeAnt() == 1 and "SubG" or "2.4"
  end
  return "Ant " .. Telemetry.activeAnt()
end

local function sens()
  return connected(link.sens) and link.sens .. "dBm" or nil
end

local function margin()
  local db = Telemetry.marginDb()
  return connected(db) and string.format("%+ddB", db) or nil
end

local function power()
  return connected(link.tpwr) and link.tpwr .. "mW" or nil
end

local function pack()
  local vbat = link.vbat
  return vbat and vbat > 0 and string.format("%.2fV", vbat) or nil
end

local function cells()
  local vbat, n = link.vbat, Telemetry.cellCnt
  return vbat and vbat > 0 and n and string.format("%dS %.2fV", n, vbat / n) or nil
end

local function current()
  local curr = link.curr
  return curr and curr > 0 and string.format("%.2fA", curr) or nil
end

local function flightMode()
  local fm = link.fm
  return fm ~= nil and fm ~= 0 and tostring(fm) or nil
end

local function sats()
  return connected(link.sats) and tostring(link.sats) or nil
end

local function speed()
  return connected(link.gspd) and string.format("%.1f", link.gspd) or nil
end

local function alt()
  return connected(link.alt) and tostring(link.alt) or nil
end

-- Last known position survives link loss
local function lat()
  return Telemetry.gps and tostring(Telemetry.gps.lat)
end

local function lon()
  return Telemetry.gps and tostring(Telemetry.gps.lon)
end

-- A row without a value is a section header
local rows = {
  { "Link Status" },
  { "RF Mode", rfMode },
  { "Link Quality", lq },
  { "RSSI", rssi },
  { "SNR", snr },
  { antLabel, ant },
  { "Sensitivity", sens },
  { "Link Margin", margin },
  { "Power" },
  { "TX Power", power },
  { "Flight Controller" },
  { "Battery", pack },
  { "Cells", cells },
  { "Current", current },
  { "Flight Mode", flightMode },
  { "GPS" },
  { "Satellites", sats },
  { "Speed", speed },
  { "Altitude", alt },
  { "Latitude", lat },
  { "Longitude", lon },
}

local MAX_OFFSET = math.max(0, #rows - ROW_COUNT)

local offset = 0

local function run(event)
  if event == EVT_VIRTUAL_EXIT then
    return true
  elseif event == EVT_VIRTUAL_NEXT then
    offset = math.min(offset + 1, MAX_OFFSET)
  elseif event == EVT_VIRTUAL_PREV then
    offset = math.max(offset - 1, 0)
  end

  lcd.clear()
  Dashboard.drawTitle()
  for i = 1, math.min(ROW_COUNT, #rows - offset) do
    local row = rows[offset + i]
    local y = ROW_Y + (i - 1) * ROW_H
    local label = row[1]
    if type(label) == "function" then
      label = label()
    end
    if row[2] then
      lcd.drawText(1, y, label)
      lcd.drawText(LCD_W - 1, y, row[2]() or "--", RIGHT)
    else
      lcd.drawText(1, y, label, BOLD)
    end
  end
end

return { run = run }
