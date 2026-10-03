---------------------------------------------------------------------------
-- ELRS Telemetry Widget - Display Components                            --
-- Zero-arg LVGL text/color callbacks: dot functions, not methods.       --
---------------------------------------------------------------------------

local Telemetry = ...

local Display = {}

function Display.isConnected()
  return Telemetry.isConnected()
end

function Display.isMismatch()
  return Telemetry.isMismatch()
end

function Display.isNotMismatch()
  return not Telemetry.isMismatch()
end

function Display.hasDiversity()
  return Telemetry.hasDiversity()
end

local STATUS_TEXT = {
  [Telemetry.STATUS.NO_MODULE] = "No CRSF module",
  [Telemetry.STATUS.NO_TELEMETRY] = "No telemetry",
  [Telemetry.STATUS.MISMATCH] = "Model Mismatch",
}

--- nil when connected with no warnings.
function Display.statusText()
  return STATUS_TEXT[Telemetry.statusLevel()]
end

function Display.pageSubtitle()
  return Display.statusText() or "Telemetry"
end

--- e.g. "100%"
function Display.lqValueText()
  if not Telemetry.isConnected() then
    return "--"
  end
  return table.concat({ tostring(Telemetry.link.rqly or 0), "%" })
end

function Display.lqPct()
  if not Telemetry.isConnected() then
    return 0
  end
  return Telemetry.link.rqly or 0
end

function Display.headroomPct()
  return Telemetry.headroomPct or 0
end

function Display.hasHeadroom()
  return Telemetry.headroomPct ~= nil
end

--- e.g. "100 %"
function Display.tqlyText()
  local tqly = Telemetry.link.tqly
  if not Telemetry.isConnected() or tqly == nil then
    return "--"
  end
  return table.concat({ tostring(tqly), " %" })
end

--- e.g. "-95 dBm"
function Display.trssText()
  local trss = Telemetry.link.trss
  if not Telemetry.isConnected() or trss == nil then
    return "--"
  end
  return table.concat({ tostring(trss), " dBm" })
end

--- e.g. "100 mW"
function Display.powerText()
  local tpwr = Telemetry.link.tpwr
  if not Telemetry.isConnected() or tpwr == nil then
    return "--"
  end
  return table.concat({ tostring(tpwr), " mW" })
end

--- e.g. "4S 3.75 V"
function Display.cellText()
  local vbat = Telemetry.link.vbat
  if vbat == nil or vbat <= 0 then
    return "--"
  end
  local cells = Telemetry.cellCnt
  if cells == nil then
    return "--"
  end
  return string.format("%dS %.2f V", cells, vbat / cells)
end

--- e.g. "15.20 V"
function Display.packText()
  local vbat = Telemetry.link.vbat
  if vbat == nil or vbat <= 0 then
    return "--"
  end
  return string.format("%.2f V", vbat)
end

--- e.g. "LQ 100%"
function Display.lqText()
  return table.concat({ "LQ ", tostring(Telemetry.link.rqly or 0), "%" })
end

--- e.g. "99"
function Display.lqHeroText()
  if not Telemetry.isConnected() then
    return "--"
  end
  return tostring(Telemetry.link.rqly or 0)
end

--- e.g. "-87dBm", "" while unknown; sep goes between number and unit.
function Display.rssiText(sep)
  local rssi = Telemetry.activeRssi()
  if rssi == nil then
    return ""
  end
  return table.concat({ tostring(rssi), sep or "", "dBm" })
end

function Display.hasStatus()
  return Display.statusText() ~= nil
end

function Display.noStatus()
  return Display.statusText() == nil
end

--- RSSI / sensitivity, e.g. "-85 -92 / -112 dBm" with diversity.
function Display.signalText()
  if not Telemetry.isConnected() then
    return ""
  end
  local rssi = Telemetry.activeRssi()
  if rssi == nil then
    return ""
  end
  local parts
  if Telemetry.hasDiversity() then
    parts = { tostring(Telemetry.link.rssi1 or "--"), " ", tostring(Telemetry.link.rssi2) }
  else
    parts = { tostring(rssi) }
  end
  local sens = Telemetry.link.sens
  if sens ~= nil then
    parts[#parts + 1] = " / "
    parts[#parts + 1] = tostring(sens)
  end
  parts[#parts + 1] = " dBm"
  return table.concat(parts)
end

--- Active antenna only, e.g. "-90 / -112 dBm": the pair doesn't fit the
--- compact row.
function Display.signalShortText()
  if not Telemetry.isConnected() then
    return ""
  end
  local rssi = Telemetry.activeRssi()
  if rssi == nil then
    return ""
  end
  local sens = Telemetry.link.sens
  if sens == nil then
    return table.concat({ tostring(rssi), " dBm" })
  end
  return table.concat({ tostring(rssi), " / ", tostring(sens), " dBm" })
end

--- e.g. "250Hz"
function Display.rfModeText()
  if not Telemetry.isConnected() then
    return ""
  end
  return Telemetry.rfModeName() or ""
end

--- e.g. "250Hz 50mW"
function Display.rfDetailText()
  local parts = { Display.rfModeText() }
  local tpwr = Telemetry.link.tpwr
  if Telemetry.isConnected() and tpwr then
    parts[#parts + 1] = table.concat({ tostring(tpwr), "mW" })
  end
  return table.concat(parts, " ")
end

--- e.g. "4S 3.80V (15.20V)"
function Display.batteryTextVerbose()
  local vbat = Telemetry.link.vbat
  if vbat == nil or vbat <= 0 then
    return "--"
  end
  local cells = Telemetry.cellCnt
  if cells then
    return string.format("%dS %.2fV (%.2fV)", cells, vbat / cells, vbat)
  end
  return string.format("%.2fV", vbat)
end

function Display.heroColor()
  if Telemetry.isMismatch() then
    return COLOR_THEME_WARNING
  end
  return COLOR_THEME_PRIMARY1
end

-- Theme colours follow the user's theme; GREEN/RED literals are raw primaries.
local HEALTH = { COLOR_THEME_EDIT, COLOR_THEME_ACTIVE, COLOR_THEME_WARNING }

-- ACTIVE yellow is unreadable as text on light themes.
local HEALTH_TEXT = { COLOR_THEME_EDIT, ORANGE, COLOR_THEME_WARNING }

-- dB above sensitivity.
local MARGIN_CRIT = 10
local MARGIN_WARN = 30

--- level: 1 good, 2 warn, 3 critical.
function Display.healthColor(level)
  return HEALTH[level] or COLOR_THEME_DISABLED
end

function Display.healthTextColor(level)
  return HEALTH_TEXT[level] or COLOR_THEME_DISABLED
end

local LQ_GOOD = 90
local LQ_CRIT = 50

function Display.lqLevel()
  if not Telemetry.isConnected() then
    return 3
  end
  local lq = Telemetry.link.rqly or 0
  if lq >= LQ_GOOD then
    return 1
  end
  if lq >= LQ_CRIT then
    return 2
  end
  return 3
end

function Display.marginLevel()
  local db = Telemetry.marginDb()
  if db == nil then
    return 3
  end
  if db > MARGIN_WARN then
    return 1
  end
  if db > MARGIN_CRIT then
    return 2
  end
  return 3
end

function Display.lqBarColor()
  return Display.healthColor(Display.lqLevel())
end

function Display.lqTextColor()
  return Display.healthTextColor(Display.lqLevel())
end

function Display.headroomBarColor()
  return Display.healthColor(Display.marginLevel())
end

-- Half-periods in 10 ms ticks: 1 Hz and 4 Hz.
local BLINK_SLOW = 50
local BLINK_FAST = 12

local function lit(halfPeriod)
  return math.floor(getTime() / halfPeriod) % 2 == 0
end

--- Blinks only when the link is broken or mismatched.
function Display.ledColor()
  local level = Telemetry.statusLevel()
  local STATUS = Telemetry.STATUS
  if level == STATUS.NO_MODULE then
    return COLOR_THEME_DISABLED
  end
  if level == STATUS.NO_TELEMETRY then
    return lit(BLINK_SLOW) and COLOR_THEME_WARNING or COLOR_THEME_DISABLED
  end
  if level == STATUS.MISMATCH then
    return lit(BLINK_FAST) and COLOR_THEME_WARNING or COLOR_THEME_DISABLED
  end
  return Display.lqBarColor()
end

--- Factory, not a callback.
function Display.antColor(n)
  return function()
    if not Telemetry.isConnected() then
      return COLOR_THEME_DISABLED
    end
    -- ANT is 0-based.
    if (Telemetry.link.ant or 0) + 1 == n then
      return COLOR_THEME_FOCUS -- not PRIMARY1: black on light themes
    end
    return COLOR_THEME_DISABLED
  end
end

--- Neutral when healthy or unknown; warns as the margin shrinks.
function Display.detailColor()
  local db = Telemetry.marginDb()
  if db == nil then
    return COLOR_THEME_SECONDARY1
  end
  local level = Display.marginLevel()
  if level == 1 then
    return COLOR_THEME_SECONDARY1
  end
  return Display.healthTextColor(level)
end

return Display
