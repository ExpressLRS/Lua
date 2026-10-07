---------------------------------------------------------------------------
-- ELRS Telemetry State                                                  --
-- Shared by all widget instances. Each instance gets its own copy of    --
-- every frame, so frame handlers must only assign, never count.         --
---------------------------------------------------------------------------

local crsf = ...

local RfModes = loadScript("/SCRIPTS/ELRS/telemetry/rf_modes.lua")()

local Telemetry = {}

-- ============================================================================
-- State
-- ============================================================================

-- Refilled in place each tick; safe to cache
Telemetry.link = {}

---@type number?
Telemetry.headroomPct = nil

---@type number?
Telemetry.cellCnt = nil

-- Kept across dropouts to find a lost model
---@type {lat: number, lon: number}|nil
Telemetry.gps = nil

---@type boolean?
Telemetry.modelMismatch = nil

---@type string?
Telemetry.modelId = nil

---@type number?
Telemetry._cellCntCnt = nil
Telemetry._cellLastV = nil

---@type number?
Telemetry._smoothHead = nil

Telemetry._device = {}

Telemetry._lastDevPoll = 0

Telemetry._lastStatusPoll = 0

---@type boolean?
Telemetry._statusAnswered = nil

Telemetry._wasConnected = false

-- Raw ANT of antenna 1: 0 before EdgeTX 2.12.3, 1 after; nil until a 0 or 2 shows
---@type number?
Telemetry._antBase = nil

---@type number?
Telemetry._sampledAt = nil

-- ============================================================================
-- Queries
-- ============================================================================

function Telemetry.hasModule()
  return crsf.hasCrsfModule()
end

function Telemetry.isConnected()
  return crsf.hasTelemetry
end

-- Flag is stale once disconnected
function Telemetry.isMismatch()
  return crsf.hasTelemetry and Telemetry.modelMismatch
end

-- Worst first
Telemetry.STATUS = {
  NO_MODULE = 1,
  NO_TELEMETRY = 2,
  MISMATCH = 3,
  OK = 4,
}

function Telemetry.statusLevel()
  local STATUS = Telemetry.STATUS
  if not Telemetry.hasModule() then
    return STATUS.NO_MODULE
  end
  if not Telemetry.isConnected() then
    return STATUS.NO_TELEMETRY
  end
  if Telemetry.modelMismatch then
    return STATUS.MISMATCH
  end
  return STATUS.OK
end

-- 1 or 2; the stronger RSSI until ANT's base is known (0 dBm is no reading)
function Telemetry.activeAnt()
  local link = Telemetry.link
  if link.ant then
    return link.ant
  end
  local rssi1, rssi2 = link.rssi1, link.rssi2
  if rssi2 ~= nil and rssi2 ~= 0 and (rssi1 == nil or rssi1 == 0 or rssi2 > rssi1) then
    return 2
  end
  return 1
end

function Telemetry.activeRssi()
  local link = Telemetry.link
  return (Telemetry.activeAnt() == 2) and link.rssi2 or link.rssi1
end

-- dB above the RF mode's sensitivity floor
function Telemetry.marginDb()
  local rssi = Telemetry.activeRssi()
  local sens = Telemetry.link.sens
  if rssi == nil or sens == nil then
    return nil
  end
  return rssi - sens
end

-- Single-antenna RX leaves 2RSS at 0 dBm
function Telemetry.hasDiversity()
  local rssi2 = Telemetry.link.rssi2
  return rssi2 ~= nil and rssi2 ~= 0
end

function Telemetry.rfModeName()
  local rfmd = Telemetry.link.rfmd
  if rfmd == nil then
    return nil
  end
  return RfModes.name(rfmd)
end

function Telemetry.hasSnr()
  local rfmd = Telemetry.link.rfmd
  return rfmd == nil or RfModes.hasSnr(rfmd)
end

function Telemetry.isXband()
  local rfmd = Telemetry.link.rfmd
  return rfmd ~= nil and RfModes.isXband(rfmd)
end

-- ============================================================================
-- Derived state
-- ============================================================================

local function checkCellCount(v)
  -- once the cell count is the same X times in a row, stop updating
  if (Telemetry._cellCntCnt or 0) > 5 then
    return
  end

  -- try to lock on to the cell count, so as the voltage sags we don't change S
  local cellCnt = math.floor(v / 4.35) + 1
  -- Prevent lock on when no voltage is present
  if (v / cellCnt) < 3.0 then
    return
  end

  if Telemetry.cellCnt ~= cellCnt then
    Telemetry.cellCnt = cellCnt
    Telemetry._cellCntCnt = 0
  else
    -- The value has to change to count as an update
    if Telemetry._cellLastV == v then
      return
    end
    Telemetry._cellLastV = v
    Telemetry._cellCntCnt = Telemetry._cellCntCnt + 1
  end
end

-- RX saturates above this; headroom is 100% here
Telemetry.RSSI_CEILING = -50
local RSSI_CEILING = Telemetry.RSSI_CEILING

-- 0% = sensitivity floor, 100% = RSSI_CEILING
local function updateHeadroom()
  local rssi = Telemetry.activeRssi()
  local sens = Telemetry.link.sens
  if rssi == nil or sens == nil then
    Telemetry.headroomPct = nil
    Telemetry._smoothHead = nil
    return
  end
  if rssi > RSSI_CEILING then
    rssi = RSSI_CEILING
  elseif rssi < sens then
    rssi = sens
  end
  local pct = math.floor(100 * (rssi - sens) / (RSSI_CEILING - sens) + 0.5)
  local smooth = Telemetry._smoothHead or pct
  if pct > smooth then
    pct = smooth + ((pct > smooth + 8) and 4 or 1)
  elseif pct < smooth then
    pct = smooth - ((pct < smooth - 8) and 4 or 1)
  end
  Telemetry._smoothHead = pct
  Telemetry.headroomPct = pct
end

local function updateGps()
  local gps = crsf.getSensorValue("GPS")
  if gps and gps ~= 0 then
    Telemetry.gps = gps
  end
end

-- ============================================================================
-- Resets
-- ============================================================================

local function resetConnection()
  Telemetry._smoothHead = nil
  Telemetry.headroomPct = nil
  Telemetry.cellCnt = nil
  Telemetry._cellCntCnt = nil
  Telemetry._cellLastV = nil
end

function Telemetry.resetModelMatch()
  Telemetry.modelMismatch = nil
  Telemetry._statusAnswered = nil
end

function Telemetry.resetModel()
  resetConnection()
  Telemetry.resetModelMatch()
  Telemetry.gps = nil
  Telemetry._wasConnected = false
  Telemetry._sampledAt = nil -- a sibling may have sampled this tick
  crsf.resetSensorCache()
end

-- ============================================================================
-- Outgoing requests
-- ============================================================================

-- EdgeTX's own init ping lands before the Lua queue exists
local function requestDeviceInfo()
  if Telemetry._device.name then
    return
  end
  local now = getTime()
  if now - Telemetry._lastDevPoll < 100 then
    return
  end
  Telemetry._lastDevPoll = now
  crsf:pingDevices(crsf.CONST.ADDRESS_TX)
end

local MODEL_MATCH_MIN_RSSI = -70

-- Each request replaces one RC-channels frame on the UART
local function canRequestStatus(now)
  if not crsf.hasTelemetry then
    return false
  end
  -- TBS modules never answer this
  if not Telemetry._device.isElrs then
    return false
  end
  -- Keep polling while mismatched; a fix never drops the link
  if Telemetry._statusAnswered and not Telemetry.modelMismatch then
    return false
  end
  -- Don't steal RC frames at range
  local rssi = Telemetry.activeRssi()
  if rssi == nil or rssi <= MODEL_MATCH_MIN_RSSI then
    return false
  end
  return now - Telemetry._lastStatusPoll >= 100 -- module refreshes at 1 Hz
end

local function updateModelMatch()
  local now = getTime()
  if not canRequestStatus(now) then
    return
  end
  Telemetry._lastStatusPoll = now
  crsf:requestElrsStatus()
end

-- ============================================================================
-- Per-tick pump
-- ============================================================================

-- 30 ms: dedupes instances within one 50 ms widget loop; else smoothing
-- speeds up per widget
local SAMPLE_INTERVAL = 3

-- 1 or 2; nil while the base is unknown
local function decodeAnt(raw)
  if raw == nil or not crsf.hasTelemetry then
    return nil -- not streaming reads 0
  end
  if raw == 0 then
    Telemetry._antBase = 0
  elseif raw == 2 then
    Telemetry._antBase = 1
  end
  local base = Telemetry._antBase
  if base == nil then
    return nil
  end
  local ant = raw - base + 1
  if ant ~= 1 and ant ~= 2 then
    return nil
  end
  return ant
end

-- Call after drain() so hasTelemetry is current
function Telemetry.update()
  local now = getTime()
  if now - (Telemetry._sampledAt or -SAMPLE_INTERVAL) < SAMPLE_INTERVAL then
    return
  end
  Telemetry._sampledAt = now

  local link = Telemetry.link
  link.tpwr = crsf.getSensorValue("TPWR")
  link.rfmd = crsf.getSensorValue("RFMD")
  link.rssi1 = crsf.getSensorValue("1RSS")
  link.rssi2 = crsf.getSensorValue("2RSS")
  link.rqly = crsf.getSensorValue("RQly")
  link.rsnr = crsf.getSensorValue("RSNR")
  link.ant = decodeAnt(crsf.getSensorValue("ANT"))
  link.tqly = crsf.getSensorValue("TQly")
  link.trss = crsf.getSensorValue("TRSS")
  link.vbat = crsf.getSensorValue("RxBt")
  link.curr = crsf.getSensorValue("Curr")
  link.fm = crsf.getSensorValue("FM")
  link.sats = crsf.getSensorValue("Sats")
  link.gspd = crsf.getSensorValue("GSpd")
  link.alt = crsf.getSensorValue("Alt")
  link.sens = link.rfmd and RfModes.floor(link.rfmd)

  local connected = crsf.hasTelemetry
  if connected ~= Telemetry._wasConnected then
    Telemetry._wasConnected = connected
    Telemetry.resetModelMatch()
    if not connected then
      resetConnection()
    end
  end

  if connected then
    updateGps()
    updateHeadroom()
    if link.vbat then
      checkCellCount(link.vbat)
    end
  end

  requestDeviceInfo()
  updateModelMatch()
end

-- ============================================================================
-- Frame handlers
-- ============================================================================

local function onDeviceInfo(data)
  local info = crsf:decodeDeviceInfo(data)
  if info == nil or info.id ~= crsf.CONST.ADDRESS_TX then
    return -- short frame (the ping retries) or not the TX module
  end
  Telemetry._device.name = info.name
  Telemetry._device.isElrs = info.isElrs
  RfModes.select(info.vMaj)
end

local function onElrsStatus(data)
  local status = crsf:decodeElrsStatus(data)
  if status == nil or status.id ~= crsf.CONST.ADDRESS_TX then
    return
  end
  Telemetry._statusAnswered = true
  Telemetry.modelMismatch = status.modelMismatch
end

function Telemetry:_onFrame(command, data)
  if command == crsf.CONST.FRAMETYPE_DEVICE_INFO then
    onDeviceInfo(data)
  elseif command == crsf.CONST.FRAMETYPE_ELRS_STATUS then
    onElrsStatus(data)
  end
end

-- Every instance, every frame: each has its own queue that would overflow
function Telemetry.drain()
  crsf.drain(Telemetry, Telemetry._onFrame)
end

-- ============================================================================
-- Return singleton
-- ============================================================================

return Telemetry
