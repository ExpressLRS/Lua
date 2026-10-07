-- ============================================================================
-- CRSF Simulator: packet-level mock for crossfireTelemetryPop/Push
-- Loaded by crsf.lua setMock() on -simu builds; returns
-- { pop, push, getSensorValue, moduleFound }
-- ============================================================================

local shim = loadScript("/SCRIPTS/CRSFSimulator/shim.lua")()

-- Scenarios (set config.scenario below):
--   normal             TX + RX connected, full telemetry
--   no_telemetry       TX only, no RX
--   reconnect          RX appears after ~5 s
--   model_mismatch     connected, model mismatch flag
--   mismatch_cycle     mismatched link, ~10 s up / ~5 s down, forever;
--                      expect a status request per connect edge, then ~1 Hz
--   mismatch_recovery  mismatch clears after ~10 s, link stays up; the module
--                      only answers when asked, so the widget must keep polling
--   weak_link          RQly ~60, RSSI ~-85 dBm; gated polls stay quiet
--   armed              armed warning flag
--   single_antenna     2RSS pinned to 0 (no diversity)
--   flrc               F1000, RSNR always 0
--   xband              X150: 1RSS sub-GHz, 2RSS 2.4 GHz
--   unrated_rate       no published sensitivity; floor-based UI must fall back
--   slow_loading       PARAMETER_READ answers delayed ~2 s each
--   no_module          no CRSF module
--   critical_error     baud rate error; suppress write (0x2E) clears it
--   old_firmware       TX reports ELRS 3.4.2, below the 3.5.4 minimum
-- Connected scenarios also arm while CH5 (AUX1) is high.
local config = {
  scenario = "normal",
  -- Lower to emulate a slow link (firmware floor 15) and force chunking
  maxPacketBytes = 64,
}

local CRSF = {
  FRAMETYPE_DEVICE_PING = 0x28,
  FRAMETYPE_DEVICE_INFO = 0x29,
  FRAMETYPE_PARAMETER_SETTINGS_ENTRY = 0x2B,
  FRAMETYPE_PARAMETER_READ = 0x2C,
  FRAMETYPE_PARAMETER_WRITE = 0x2D,
  FRAMETYPE_ELRS_STATUS = 0x2E,
  FRAMETYPE_COMMAND = 0x32,
  FRAMETYPE_MSP_REQ = 0x7A,
  FRAMETYPE_MSP_RESP = 0x7B,
  FRAMETYPE_MSP_WRITE = 0x7C,

  MSP_HEADER_V1 = 0x30, -- v1 | start-of-frame | seq 0
  MSP_ELRS_RXTX_CONFIG = 0x2D,
  MSP_RXTX_UID = 0x00,
  MSP_RXTX_BIND_PHRASE = 0x01,

  ADDRESS_BROADCAST = 0x00,
  ADDRESS_HANDSET = 0xEA,
  ADDRESS_RX = 0xEC,
  ADDRESS_TX = 0xEE,

  UINT8 = 0,
  INT8 = 1,
  UINT16 = 2,
  INT16 = 3,
  FLOAT = 8,
  TEXT_SELECTION = 9,
  STRING = 10,
  FOLDER = 11,
  INFO = 12,
  COMMAND = 13,

  ELRS_SERIAL_ID = 0x454C5253,

  CMD_IDLE = 0,
  CMD_CLICK = 1,
  CMD_EXECUTING = 2,
  CMD_ASKCONFIRM = 3,
  CMD_CONFIRMED = 4,
  CMD_CANCEL = 5,
  CMD_QUERY = 6,

  -- TXModuleEndpoint.cpp supressCriticalErrors()
  FIELD_ID_SUPPRESS_CRITICAL_ERRORS = 0x2E,
}

-- SX128X rates from common.cpp; defaultTlm indexes the Telem Ratio options
local rateConfigs = {
  [0] = { hz = 50, interval = 20000, defaultTlm = 5 }, -- TLM_RATIO_1_16
  [1] = { hz = 150, interval = 6666, defaultTlm = 4 }, -- TLM_RATIO_1_32
  [2] = { hz = 250, interval = 4000, defaultTlm = 3 }, -- TLM_RATIO_1_64
  [3] = { hz = 500, interval = 2000, defaultTlm = 2 }, -- TLM_RATIO_1_128
}

-- rx_config_pwm_t per Output Ch
local pwmChannelConfig = {
  [1] = { inputChannel = 1, mode = 0, inverted = 0 },
  [2] = { inputChannel = 2, mode = 1, inverted = 0 },
  [3] = { inputChannel = 3, mode = 2, inverted = 1 },
  [4] = { inputChannel = 4, mode = 0, inverted = 0 },
}

-- Colour firmware gives each widget its own frame queue: a shared log with
-- per-consumer cursors, new consumers start at the tail. On B&W crsf.lua
-- pops with one key, as there the firmware has a single queue.

local frameLog = {}
local logTotal = 0
local logPruned = 0
local cursors = setmetatable({}, { __mode = "k" })
local defaultConsumer = {}

-- OTA relay delay: delivered after the next nil pop
local deferredQueue = {}
local deferredReady = false

local SLOW_LOADING_DELAY_TICKS = 200 -- 2 s per field
local delayedResponseQueue = {}

-- Firmware updates folder names on the next event loop, not in the write
local FOLDER_NAMES_UPDATE_TICKS = 2 -- 20 ms
local folderNamesReadyAt = 0
local folderNamesDevice = nil

local function pruneLog()
  local minCursor = logTotal
  for _, c in pairs(cursors) do
    if c < minCursor then
      minCursor = c
    end
  end
  for i = logPruned + 1, minCursor do
    frameLog[i] = nil
  end
  logPruned = minCursor
end

local function queuePush(command, data)
  logTotal = logTotal + 1
  frameLog[logTotal] = { command = command, data = data }
  pruneLog()
end

local function queuePushDeferred(command, data)
  deferredQueue[#deferredQueue + 1] = { command = command, data = data }
end

-- Copy: consumers decode in place
local function deliver(consumer, index)
  cursors[consumer] = index
  local pkt = frameLog[index]
  local data = {}
  for i = 1, #pkt.data do
    data[i] = pkt.data[i]
  end
  return pkt.command, data
end

local function queuePop(consumer)
  consumer = consumer or defaultConsumer
  local cursor = cursors[consumer]
  if cursor == nil then
    cursor = logTotal
    cursors[consumer] = cursor
  end

  if cursor < logTotal then
    deferredReady = false
    return deliver(consumer, cursor + 1)
  end

  if deferredReady and #deferredQueue > 0 then
    local pkt = shim.tableRemove(deferredQueue, 1)
    ---@diagnostic disable-next-line: need-check-nil
    queuePush(pkt.command, pkt.data)
    return deliver(consumer, cursors[consumer] + 1)
  end

  if #deferredQueue > 0 then
    deferredReady = true
  end

  return nil
end

local function appendString(tbl, str)
  for i = 1, #str do
    tbl[#tbl + 1] = string.byte(str, i)
  end
  tbl[#tbl + 1] = 0
end

local function appendU32BE(tbl, val)
  tbl[#tbl + 1] = bit32.band(bit32.rshift(val, 24), 0xFF)
  tbl[#tbl + 1] = bit32.band(bit32.rshift(val, 16), 0xFF)
  tbl[#tbl + 1] = bit32.band(bit32.rshift(val, 8), 0xFF)
  tbl[#tbl + 1] = bit32.band(val, 0xFF)
end

local function appendU16BE(tbl, val)
  tbl[#tbl + 1] = bit32.band(bit32.rshift(val, 8), 0xFF)
  tbl[#tbl + 1] = bit32.band(val, 0xFF)
end

-- ============================================================================
-- CRSF Packet Encoders
-- ============================================================================

local function encodeDeviceInfo(device, destAddr)
  local data = {}
  data[1] = destAddr or CRSF.ADDRESS_HANDSET
  data[2] = device.id
  appendString(data, device.name)
  appendU32BE(data, device.serialNo or CRSF.ELRS_SERIAL_ID)
  appendU32BE(data, device.hwVer or 0)
  appendU32BE(data, device.swVer or 0x00040100) -- 4.1.0
  data[#data + 1] = device.fieldCount
  data[#data + 1] = 0 -- parameter version
  return data
end

local function encodeParameterEntry(device, param, chunk, destAddr)
  local data = {}
  data[1] = destAddr or CRSF.ADDRESS_HANDSET
  data[2] = device.id
  data[3] = param.id
  data[4] = 0 -- chunks remaining
  data[5] = param.parent or 0
  data[6] = param.type
  if param.hidden then
    data[6] = bit32.bor(data[6], 0x80)
  end

  appendString(data, param.dynName or param.name)

  local t = bit32.band(param.type, 0x7F)

  if t == CRSF.TEXT_SELECTION then
    appendString(data, param.options)
    data[#data + 1] = param.value or 0
    data[#data + 1] = 0
    local optCount = 1
    for i = 1, #param.options do
      if string.byte(param.options, i) == 59 then -- ';'
        optCount = optCount + 1
      end
    end
    data[#data + 1] = optCount - 1
    data[#data + 1] = 0
    appendString(data, param.units or "")
  elseif t == CRSF.COMMAND then
    data[#data + 1] = param.status or CRSF.CMD_IDLE
    data[#data + 1] = param.timeout or 200 -- 10 ms ticks
    appendString(data, param.info or "")
  elseif t == CRSF.FOLDER then
    if param._device then
      for _, p in ipairs(param._device.params) do
        if (param.id == 0 and (p.parent == 0 or p.parent == nil)) or (param.id ~= 0 and p.parent == param.id) then
          data[#data + 1] = p.id
        end
      end
    end
    data[#data + 1] = 0xFF
  elseif t == CRSF.INFO then
    appendString(data, param.value or "")
  elseif t == CRSF.STRING then
    appendString(data, param.value or "")
    data[#data + 1] = param.maxlen or 32
  elseif t == CRSF.UINT8 then
    data[#data + 1] = param.value or 0
    data[#data + 1] = param.min or 0
    data[#data + 1] = param.max or 255
    data[#data + 1] = param.default or 0
    appendString(data, param.units or "")
  elseif t == CRSF.INT8 then
    local v = param.value or 0
    if v < 0 then
      v = v + 256
    end
    local mn = param.min or 0
    if mn < 0 then
      mn = mn + 256
    end
    local mx = param.max or 127
    if mx < 0 then
      mx = mx + 256
    end
    data[#data + 1] = v
    data[#data + 1] = mn
    data[#data + 1] = mx
    data[#data + 1] = param.default or 0
    appendString(data, param.units or "")
  elseif t == CRSF.UINT16 or t == CRSF.INT16 then
    appendU16BE(data, param.value or 0)
    appendU16BE(data, param.min or 0)
    appendU16BE(data, param.max or 65535)
    appendU16BE(data, param.default or 0)
    appendString(data, param.units or "")
  elseif t == CRSF.FLOAT then
    appendU32BE(data, param.value or 0)
    appendU32BE(data, param.min or 0)
    appendU32BE(data, param.max or 0)
    appendU32BE(data, param.default or 0)
    data[#data + 1] = param.prec or 0
    appendU32BE(data, param.step or 1)
    appendString(data, param.units or "")
  end

  -- As CRSFEndpoint::sendParameter: 6 bytes header/CRC + fieldId + chunksRemain
  local chunkMax = config.maxPacketBytes - 8
  local body = {}
  for i = 5, #data do
    body[#body + 1] = data[i]
  end
  if #body <= chunkMax then
    return data
  end
  local totalChunks = math.ceil(#body / chunkMax)
  local k = chunk or 0
  if k >= totalChunks then
    k = totalChunks - 1
  end
  local out = { data[1], data[2], data[3], totalChunks - 1 - k }
  for i = k * chunkMax + 1, math.min((k + 1) * chunkMax, #body) do
    out[#out + 1] = body[i]
  end
  return out
end

local function encodeElrsStatus(deviceId, destAddr, badPkts, goodPkts, flags, flagsInfo)
  local data = {}
  data[1] = destAddr or CRSF.ADDRESS_HANDSET
  data[2] = deviceId
  data[3] = badPkts or 0
  appendU16BE(data, goodPkts or 0)
  data[#data + 1] = flags or 0
  appendString(data, flagsInfo or "")
  return data
end

-- ============================================================================
-- TX device (TXModuleParameters.cpp)
-- ============================================================================

-- STR_LUA_ALLAUX_UPDOWN; \192/\193 are the ELRS up/down arrow glyphs
local ALLAUX_UPDOWN = (function()
  local opts = {}
  for i = 1, 10 do
    opts[#opts + 1] = shim.tableConcat({ "AUX", i, "\192" })
    opts[#opts + 1] = shim.tableConcat({ "AUX", i, "\193" })
  end
  return shim.tableConcat(opts, ";")
end)()

local txDevice = {
  id = CRSF.ADDRESS_TX,
  name = "TX16S MK3",
  serialNo = CRSF.ELRS_SERIAL_ID,
  hwVer = 0,
  swVer = config.scenario == "old_firmware" and 0x00030402 or 0x00040100, -- 3.4.2 / 4.1.0
  fieldCount = 25,
  params = {
    {
      id = 1,
      parent = 0,
      type = CRSF.TEXT_SELECTION,
      name = "Packet Rate",
      options = "50(-117dBm);150(-112dBm);250(-108dBm);500(-105dBm)",
      value = 2,
      units = "Hz",
    },
    {
      id = 2,
      parent = 0,
      type = CRSF.TEXT_SELECTION,
      name = "Telem Ratio",
      options = "Std;Off;1:128;1:64;1:32;1:16;1:8;1:4;1:2;Race",
      value = 0,
      units = " (1:64)",
    },
    {
      id = 3,
      parent = 0,
      type = CRSF.TEXT_SELECTION,
      name = "Switch Mode",
      options = "Hybrid;Wide",
      value = 1,
      units = "",
    },
    {
      id = 4,
      parent = 0,
      type = CRSF.TEXT_SELECTION,
      name = "Model Match",
      options = "Off;On",
      value = 0,
      units = "(ID: 1)",
    },
    {
      id = 5,
      parent = 0,
      type = CRSF.TEXT_SELECTION,
      name = "Antenna Mode",
      options = "Gemini;Ant 1;Ant 2;Switch",
      value = 0,
      units = "",
    },

    { id = 6, parent = 0, type = CRSF.FOLDER, name = "TX Power" },
    {
      id = 7,
      parent = 6,
      type = CRSF.TEXT_SELECTION,
      name = "Max Power",
      options = "10/10;25/25;25/50;25/100;25/250;25/500;25/1000;25/2000",
      value = 3,
      units = "mW",
    },
    {
      id = 8,
      parent = 6,
      type = CRSF.TEXT_SELECTION,
      name = "Dynamic",
      options = "Off;Dyn;AUX9;AUX10;AUX11;AUX12",
      value = 1,
      units = "",
    },
    {
      id = 9,
      parent = 6,
      type = CRSF.TEXT_SELECTION,
      name = "Fan Thresh",
      options = "10mW;25mW;50mW;100mW;250mW;500mW;1000mW;2000mW;Never",
      value = 3,
      units = "",
    },

    { id = 10, parent = 0, type = CRSF.FOLDER, name = "VTX Administrator" },
    {
      id = 11,
      parent = 10,
      type = CRSF.TEXT_SELECTION,
      name = "Band/Enable",
      options = "Disabled;A;B;E;F;R;L",
      value = 5,
      units = "",
    },
    { id = 12, parent = 10, type = CRSF.UINT8, name = "Channel", value = 1, min = 1, max = 8, units = "" },
    -- Not "-": that hides Pitmode and the folder name's power/pit segments
    {
      id = 13,
      parent = 10,
      type = CRSF.TEXT_SELECTION,
      name = "Pwr Lvl",
      options = "-;1;2;3;4;5;6;7;8",
      value = 2,
      units = "",
    },
    {
      id = 14,
      parent = 10,
      type = CRSF.TEXT_SELECTION,
      name = "Pitmode",
      options = shim.tableConcat({ "Off;On;", ALLAUX_UPDOWN }),
      value = 0,
      units = "",
    },
    {
      id = 15,
      parent = 10,
      type = CRSF.COMMAND,
      name = "Send VTx",
      status = CRSF.CMD_IDLE,
      timeout = 200,
      info = "",
    },

    { id = 16, parent = 0, type = CRSF.FOLDER, name = "WiFi Connectivity" },
    {
      id = 17,
      parent = 16,
      type = CRSF.COMMAND,
      name = "Enable WiFi",
      status = CRSF.CMD_IDLE,
      timeout = 200,
      info = "",
      persistent = true,
    }, -- runs until cancelled
    {
      id = 18,
      parent = 16,
      type = CRSF.COMMAND,
      name = "Enable Rx WiFi",
      status = CRSF.CMD_IDLE,
      timeout = 200,
      info = "",
      persistent = true,
    }, -- runs until cancelled

    {
      id = 19,
      parent = 0,
      type = CRSF.COMMAND,
      name = "Bind",
      status = CRSF.CMD_IDLE,
      timeout = 200,
      info = "",
      progress = { "Binding...", "Waiting for RX...", "RX found", "Saving..." },
    },

    -- Echoes Bind Phrase: tests that a STRING write reloads siblings
    { id = 24, parent = 0, type = CRSF.INFO, name = "Phrase Echo", value = "default" },

    {
      id = 20,
      parent = 0,
      type = CRSF.STRING,
      name = "Bind Phrase",
      value = "default",
      maxlen = 16,
    },

    {
      id = 21,
      parent = 0,
      type = CRSF.FLOAT,
      name = "Freq Offset",
      value = 0,
      min = -5000,
      max = 5000,
      default = 0,
      prec = 2,
      step = 1,
      units = "kHz",
    },

    { id = 22, parent = 0, type = CRSF.INFO, name = "Bad/Good", value = "0/250", hidden = true },

    { id = 23, parent = 0, type = CRSF.INFO, name = "4.1.0 ISM2G4", value = "825ed8" },

    -- Not a real TX parameter; tests INT8 sign handling
    {
      id = 25,
      parent = 0,
      type = CRSF.INT8,
      name = "RF Gain",
      value = -3,
      min = -10,
      max = 10,
      default = 0,
      units = "dB",
    },
  },
}

-- ============================================================================
-- RX device (RXParameters.cpp)
-- ============================================================================

local rxDevice = {
  id = CRSF.ADDRESS_RX,
  name = "Bob 2400RX",
  serialNo = CRSF.ELRS_SERIAL_ID,
  hwVer = 0,
  swVer = 0x00040100, -- 4.1.0
  fieldCount = 26,
  params = {
    {
      id = 1,
      parent = 0,
      type = CRSF.TEXT_SELECTION,
      name = "Protocol",
      options = "CRSF;Inverted CRSF;SBUS;Inverted SBUS;SUMD;DJI RS Pro;HoTT Telemetry;MAVLink;DisplayPort;GPS",
      value = 0,
      units = "",
    },
    {
      id = 2,
      parent = 0,
      type = CRSF.TEXT_SELECTION,
      name = "SBUS failsafe",
      options = "No Pulses;Last Pos",
      value = 0,
      units = "",
    },
    {
      id = 3,
      parent = 0,
      type = CRSF.TEXT_SELECTION,
      name = "Antenna Mode",
      options = "Antenna 1;Antenna 2;Diversity",
      value = 2,
      units = "",
    },
    {
      id = 4,
      parent = 0,
      type = CRSF.TEXT_SELECTION,
      name = "Tlm Power",
      options = "10;25;50;100;250;MatchTX",
      value = 2,
      units = "mW",
    },

    { id = 5, parent = 0, type = CRSF.FOLDER, name = "Team Race" },
    {
      id = 6,
      parent = 5,
      type = CRSF.TEXT_SELECTION,
      name = "Channel",
      options = "AUX2;AUX3;AUX4;AUX5;AUX6;AUX7;AUX8;AUX9;AUX10;AUX11;AUX12",
      value = 0,
      units = "",
    },
    {
      id = 7,
      parent = 5,
      type = CRSF.TEXT_SELECTION,
      name = "Position",
      options = "Disabled;1/Low;2;3;Mid;4;5;6/High",
      value = 0,
      units = "",
    },

    { id = 8, parent = 0, type = CRSF.FOLDER, name = "Output Mapping" },
    { id = 9, parent = 8, type = CRSF.UINT8, name = "Output Ch", value = 1, min = 1, max = 4, units = "" },
    { id = 10, parent = 8, type = CRSF.UINT8, name = "Input Ch", value = 1, min = 1, max = 16, units = "" },
    {
      id = 11,
      parent = 8,
      type = CRSF.TEXT_SELECTION,
      name = "Output Mode",
      options = "50Hz;60Hz;100Hz;160Hz;333Hz;400Hz;10kHzDuty;On/Off;DShot",
      value = 0,
      units = "",
    },
    {
      id = 12,
      parent = 8,
      type = CRSF.TEXT_SELECTION,
      name = "Invert",
      options = "Off;On",
      value = 0,
      units = "",
    },

    { id = 13, parent = 8, type = CRSF.FOLDER, name = "PWM Ch1" },
    {
      id = 14,
      parent = 13,
      type = CRSF.UINT8,
      name = "Failsafe",
      value = 0,
      min = 0,
      max = 100,
      units = "%",
    },
    {
      id = 15,
      parent = 13,
      type = CRSF.TEXT_SELECTION,
      name = "Mode",
      options = "50Hz;60Hz;100Hz;160Hz;333Hz;400Hz",
      value = 0,
      units = "",
    },

    { id = 16, parent = 8, type = CRSF.FOLDER, name = "PWM Ch2" },
    {
      id = 17,
      parent = 16,
      type = CRSF.UINT8,
      name = "Failsafe",
      value = 0,
      min = 0,
      max = 100,
      units = "%",
    },
    {
      id = 18,
      parent = 16,
      type = CRSF.TEXT_SELECTION,
      name = "Mode",
      options = "50Hz;60Hz;100Hz;160Hz;333Hz;400Hz",
      value = 0,
      units = "",
    },

    -- COMMAND that changes a sibling value (Lua-Scripts #8)
    { id = 19, parent = 0, type = CRSF.FOLDER, name = "Gyro" },
    {
      id = 20,
      parent = 19,
      type = CRSF.TEXT_SELECTION,
      name = "Orientation",
      options = "Up;Down;Left;Right",
      value = 0,
      units = "",
    },
    {
      id = 21,
      parent = 19,
      type = CRSF.COMMAND,
      name = "Detect Orientation",
      status = CRSF.CMD_IDLE,
      timeout = 200,
      info = "",
      progress = { "Detecting...", "Reading IMU..." },
      onComplete = function(device, findParam)
        local o = findParam(device, 20)
        if o then
          o.value = ((o.value or 0) + 1) % 4
        end
      end,
    },

    {
      id = 22,
      parent = 0,
      type = CRSF.TEXT_SELECTION,
      name = "Bind Storage",
      options = "Persistent;Volatile;Returnable;Administered",
      value = 0,
      units = "",
    },
    {
      id = 23,
      parent = 0,
      type = CRSF.COMMAND,
      name = "Enter Bind Mode",
      status = CRSF.CMD_IDLE,
      timeout = 200,
      info = "",
    },
    -- Finishes at once with an info text, as TBS allows
    {
      id = 26,
      parent = 0,
      type = CRSF.COMMAND,
      name = "Reset Stats",
      status = CRSF.CMD_IDLE,
      timeout = 200,
      info = "",
      result = "OK",
    },

    { id = 24, parent = 0, type = CRSF.INFO, name = "Model Id", value = "12" },

    { id = 25, parent = 0, type = CRSF.INFO, name = "RX Version", value = "4.1.0 825ed8" },
  },
}

local function findParam(device, fieldId)
  for _, p in ipairs(device.params) do
    if p.id == fieldId then
      return p
    end
  end
  return nil
end

local function findDeviceByAddr(addr)
  if addr == txDevice.id then
    return txDevice
  end
  if rxDevice and addr == rxDevice.id then
    return rxDevice
  end
  return nil
end

-- findSelectionLabel(); index is 0-based
local function getOptionLabel(options, index)
  local i = 0
  for label in string.gmatch(options, "([^;]+)") do
    if i == index then
      return label
    end
    i = i + 1
  end
  return ""
end

-- ============================================================================
-- Firmware-derived updates (TXModuleParameters.cpp)
-- ============================================================================

-- updateFolderNames(); TX only, RX reuses these ids
local function updateFolderNames(device)
  if device.id ~= CRSF.ADDRESS_TX then
    return
  end

  local txPwrFolder = findParam(device, 6)
  local maxPower = findParam(device, 7)
  local dynamic = findParam(device, 8)
  if txPwrFolder and maxPower then
    local pwrLabel = getOptionLabel(maxPower.options, maxPower.value or 0)
    local name = "TX Power (" .. pwrLabel
    if dynamic and (dynamic.value or 0) > 0 then
      local dynLabel = getOptionLabel(dynamic.options, dynamic.value)
      name = name .. " " .. dynLabel
    end
    name = name .. ")"
    txPwrFolder.dynName = name
  end

  local vtxFolder = findParam(device, 10)
  local vtxBand = findParam(device, 11)
  local vtxChan = findParam(device, 12)
  local vtxPwr = findParam(device, 13)
  local vtxPit = findParam(device, 14)
  if vtxFolder and vtxBand then
    local bandVal = vtxBand.value or 0
    if bandVal == 0 then
      vtxFolder.dynName = nil
    else
      local bandLabel = getOptionLabel(vtxBand.options, bandVal)
      local chanLabel = tostring((vtxChan and vtxChan.value) or 1)
      local name = "VTX Admin (" .. bandLabel .. ":" .. chanLabel

      local pwrVal = (vtxPwr and vtxPwr.value) or 0
      if pwrVal > 0 then
        ---@diagnostic disable-next-line: need-check-nil
        local pwrLabel = getOptionLabel(vtxPwr.options, pwrVal)
        name = name .. ":" .. pwrLabel

        local pitVal = (vtxPit and vtxPit.value) or 0
        if pitVal == 1 then
          name = name .. ":P"
        elseif pitVal > 1 then
          ---@diagnostic disable-next-line: need-check-nil
          local pitLabel = getOptionLabel(vtxPit.options, pitVal)
          name = name .. ":" .. pitLabel
        end
      end

      name = name .. ")"
      vtxFolder.dynName = name
    end
  end
end

-- TLMratioEnumToValue()
local function tlmRatioEnumToValue(enumval)
  if enumval <= 1 then
    return 1
  end -- Std/Off
  if enumval >= 9 then
    return 1
  end -- Race
  return math.floor(2 ^ (9 - enumval))
end

-- TLMBurstMaxForRateRatio()
local function tlmBurstMaxForRateRatio(rateHz, ratioDiv)
  local retVal = math.floor(512 * rateHz / ratioDiv / 1000)
  if retVal > 1 then
    retVal = retVal - 1
  else
    retVal = 1
  end
  return retVal
end

-- updateTlmBandwidth()
local function updateTlmBandwidth(device)
  local packetRate = findParam(device, 1)
  local telemRatio = findParam(device, 2)
  local switchMode = findParam(device, 3)
  if not packetRate or not telemRatio then
    return
  end

  local rateIdx = packetRate.value or 0
  local rateCfg = rateConfigs[rateIdx]
  if not rateCfg then
    return
  end

  local tlmVal = telemRatio.value or 0

  -- Std or Race
  if tlmVal == 0 or tlmVal == 9 then
    local defaultDiv = tlmRatioEnumToValue(rateCfg.defaultTlm)
    telemRatio.units = " (1:" .. defaultDiv .. ")"
    return
  end

  if tlmVal == 1 then
    telemRatio.units = ""
    return
  end

  local hz = rateCfg.hz
  local ratioDiv = tlmRatioEnumToValue(tlmVal)
  local burst = tlmBurstMaxForRateRatio(hz, ratioDiv)

  -- Wide: 10 bytes per call, Hybrid: 5
  local isFullRes = switchMode and (switchMode.value or 0) == 1
  local bytesPerCall = isFullRes and 10 or 5

  local bandwidth = math.floor(bytesPerCall * 8 * burst * hz / ratioDiv / (burst + 1))

  -- Telemetry packed into LinkStats; sizeof(OTA_LinkStats_s) = 4
  if isFullRes then
    bandwidth = bandwidth + 8 * (10 - 4)
  end

  telemRatio.units = " (" .. bandwidth .. "bps)"
end

-- updateVtxAdminOpts(); hiding Send VTx is mock-only, to test COMMAND sibling re-reads
local function updateVtxAdminOpts(device)
  if device.id ~= CRSF.ADDRESS_TX then
    return
  end

  local vtxBand = findParam(device, 11)
  local vtxChan = findParam(device, 12)
  local vtxPwr = findParam(device, 13)
  local vtxPit = findParam(device, 14)
  local vtxSend = findParam(device, 15)
  if vtxBand and vtxChan and vtxPwr and vtxPit and vtxSend then
    local disabled = (vtxBand.value or 0) == 0
    vtxChan.hidden = disabled or nil
    vtxPwr.hidden = disabled or nil
    vtxPit.hidden = (disabled or (vtxPwr.value or 0) == 0) or nil
    vtxSend.hidden = disabled or nil
  end
end

updateFolderNames(txDevice)
updateTlmBandwidth(txDevice)
updateVtxAdminOpts(txDevice)

-- ============================================================================
-- Scenario State
-- ============================================================================

local reconnectDelay = 500 -- 5 s
local startTime = nil -- first push/pop
local mismatchClearDelay = 1000 -- 10 s

local function isRxAvailable()
  if config.scenario == "reconnect" then
    if not startTime then
      return false
    end
    return getTime() - startTime >= reconnectDelay
  end
  return config.scenario ~= "no_telemetry"
end

-- Flag bits (TXModuleEndpoint.h): 0 connected, 1 status1, 2 model mismatch,
-- 3 armed, 4 warning1, 5 error connected, 6 error baud rate
local criticalErrorsSuppressed = false

local function isArmed()
  return (getOutputValue(4) or 0) > 0 -- CH5, 0-based
end

local function getElrsFlags()
  local flags
  if config.scenario == "reconnect" then
    flags = isRxAvailable() and 0x01 or 0x00
  elseif config.scenario == "model_mismatch" or config.scenario == "mismatch_cycle" then
    flags = 0x05 -- connected + model mismatch
  elseif config.scenario == "mismatch_recovery" then
    local cleared = startTime ~= nil and getTime() - startTime >= mismatchClearDelay
    flags = cleared and 0x01 or 0x05
  elseif config.scenario == "armed" then
    flags = 0x09 -- connected + armed
  elseif config.scenario == "critical_error" then
    if criticalErrorsSuppressed then
      flags = 0x01
    else
      flags = 0x41 -- connected + baud rate error
    end
  elseif
    config.scenario == "normal"
    or config.scenario == "slow_loading"
    or config.scenario == "single_antenna"
    or config.scenario == "weak_link"
    or config.scenario == "unrated_rate"
    or config.scenario == "flrc"
    or config.scenario == "xband"
  then
    flags = 0x01 -- connected
  else
    flags = 0x00 -- no telemetry
  end
  if bit32.btest(flags, 0x01) and isArmed() then
    flags = bit32.bor(flags, 0x08)
  end
  return flags
end

-- Highest bit wins, as sendELRSstatus()
local function getElrsFlagsInfo(flags)
  if bit32.btest(flags, 0x40) then
    return "Baud rate too low"
  elseif bit32.btest(flags, 0x08) then
    return "[ ! Armed ! ]"
  elseif bit32.btest(flags, 0x04) then
    return "Model Mismatch"
  end
  return ""
end

-- ============================================================================
-- Commands
-- ============================================================================

local commandStates = {} -- "deviceId:paramId"
-- CRSFEndpoint::nextStatusChunk, per device
local nextStatusChunk = {}

local function getCommandKey(deviceId, paramId)
  return tostring(deviceId) .. ":" .. tostring(paramId)
end

local COMMAND_EXECUTE_POLLS = 1

local function handleCommandWrite(device, param, newStatus)
  local key = getCommandKey(device.id, param.id)
  if not commandStates[key] then
    commandStates[key] = { status = CRSF.CMD_IDLE, info = "" }
  end
  local state = commandStates[key]

  if newStatus == CRSF.CMD_CLICK or newStatus == CRSF.CMD_CONFIRMED then
    -- WiFi/BLE commands confirm only while connected ("normal")
    local needsConfirm = param.persistent and config.scenario == "normal"
    if newStatus == CRSF.CMD_CLICK and needsConfirm then
      state.status = CRSF.CMD_ASKCONFIRM
      state.info = "Confirm " .. param.name .. "?"
    elseif param.result then
      state.status = CRSF.CMD_IDLE
      state.info = param.result
    else
      state.status = CRSF.CMD_EXECUTING
      if param.persistent then
        state.info = "Executing..."
        state.queriesRemaining = nil -- until cancelled
      elseif param.progress then
        state.progressIndex = 1
        state.info = param.progress[1]
        state.queriesRemaining = #param.progress
      else
        state.info = "Executing..."
        state.queriesRemaining = COMMAND_EXECUTE_POLLS
      end
    end
  elseif newStatus == CRSF.CMD_CANCEL then
    state.status = CRSF.CMD_IDLE
    state.info = ""
  elseif newStatus == CRSF.CMD_QUERY then
    if state.status == CRSF.CMD_EXECUTING and state.queriesRemaining then
      state.queriesRemaining = state.queriesRemaining - 1
      if state.queriesRemaining <= 0 then
        state.status = CRSF.CMD_IDLE
        state.info = ""
        if param.onComplete then
          param.onComplete(device, findParam)
        end
      elseif param.progress then
        state.progressIndex = (state.progressIndex or 1) + 1
        state.info = param.progress[state.progressIndex] or state.info
      end
    end
  end

  param.status = state.status
  param.info = state.info
end

-- ============================================================================
-- MSP bind UID
-- ============================================================================

-- TX and RX start mismatched
local mspUid = {
  [CRSF.ADDRESS_TX] = { 13, 213, 105, 32, 0, 1 },
  [CRSF.ADDRESS_RX] = { 13, 213, 105, 32, 0, 2 },
}

-- Deterministic, not the firmware's MD5
local function deriveUid(chars)
  local uid = { 0, 0, 0, 0, 0, 0 }
  local acc = 0
  for i = 1, #chars do
    acc = (acc + chars[i] * i) % 251
    local slot = (i - 1) % 6 + 1
    uid[slot] = (uid[slot] + acc + chars[i]) % 256
  end
  return uid
end

local function encodeMspUidResponse(deviceId, destAddr, uid)
  return {
    destAddr,
    deviceId,
    CRSF.MSP_HEADER_V1,
    7, -- subcmd + 6 UID bytes
    CRSF.MSP_ELRS_RXTX_CONFIG,
    CRSF.MSP_RXTX_UID,
    uid[1],
    uid[2],
    uid[3],
    uid[4],
    uid[5],
    uid[6],
  }
end

-- ============================================================================
-- push / pop
-- ============================================================================

local function mockPush(command, data)
  if not startTime then
    startTime = getTime()
  end

  -- One log line per frame so tests can count wire traffic
  print(shim.tableConcat({
    "CRSFSIM push t=",
    getTime(),
    " cmd=",
    command,
    " dst=",
    data and data[1] or "-",
    " field=",
    data and data[3] or "-",
    " arg=",
    data and data[4] or "-",
  }))

  if command == CRSF.FRAMETYPE_DEVICE_PING then
    local dest = data[1] or CRSF.ADDRESS_BROADCAST
    local replyTo = data[2] or CRSF.ADDRESS_HANDSET

    -- Only a broadcast ping is forwarded over the air
    if dest == CRSF.ADDRESS_BROADCAST or dest == CRSF.ADDRESS_TX then
      queuePush(CRSF.FRAMETYPE_DEVICE_INFO, encodeDeviceInfo(txDevice, replyTo))
    end

    if dest == CRSF.ADDRESS_BROADCAST and isRxAvailable() then
      queuePushDeferred(CRSF.FRAMETYPE_DEVICE_INFO, encodeDeviceInfo(rxDevice, replyTo))
    end
    return true
  elseif command == CRSF.FRAMETYPE_PARAMETER_READ then
    local deviceId = data[1]
    local fieldId = data[3]
    local chunk = data[4] or 0
    local destAddr = data[2] or CRSF.ADDRESS_HANDSET

    local device = findDeviceByAddr(deviceId)
    if device then
      local param
      if fieldId == 0 then
        param = { id = 0, parent = 0, type = CRSF.FOLDER, name = device.name, _device = device }
      else
        param = findParam(device, fieldId)
      end
      if param then
        local key = getCommandKey(device.id, param.id)
        if commandStates[key] and bit32.band(param.type, 0x7F) == CRSF.COMMAND then
          param.status = commandStates[key].status
          param.info = commandStates[key].info
        end
        param._device = param._device or device
        local entry = encodeParameterEntry(device, param, chunk, destAddr)
        param._device = nil
        if config.scenario == "slow_loading" then
          delayedResponseQueue[#delayedResponseQueue + 1] = {
            command = CRSF.FRAMETYPE_PARAMETER_SETTINGS_ENTRY,
            data = entry,
            deliverAt = getTime() + SLOW_LOADING_DELAY_TICKS,
          }
        else
          queuePush(CRSF.FRAMETYPE_PARAMETER_SETTINGS_ENTRY, entry)
        end
      end
    end
    return true
  elseif command == CRSF.FRAMETYPE_PARAMETER_WRITE then
    local deviceId = data[1]
    local fieldId = data[3]
    local writeValue = data[4]

    -- Field 0: ELRS status request
    if fieldId == 0 then
      local flags = getElrsFlags()
      local flagsInfo = getElrsFlagsInfo(flags)
      local destAddr = data[2] or CRSF.ADDRESS_HANDSET
      queuePush(CRSF.FRAMETYPE_ELRS_STATUS, encodeElrsStatus(deviceId, destAddr, 0, 250, flags, flagsInfo))
      return true
    end

    if fieldId == CRSF.FIELD_ID_SUPPRESS_CRITICAL_ERRORS then
      criticalErrorsSuppressed = true
      return true
    end

    local device = findDeviceByAddr(deviceId)
    if device then
      local param = findParam(device, fieldId)
      if param then
        local t = bit32.band(param.type, 0x7F)
        if t == CRSF.COMMAND then
          -- As parameterUpdateReq: a query mid-response fetches the next chunk
          local destAddr = data[2] or CRSF.ADDRESS_HANDSET
          local chunk = nextStatusChunk[device.id] or 0
          if writeValue ~= CRSF.CMD_QUERY or chunk == 0 then
            handleCommandWrite(device, param, writeValue)
            chunk = 0
          end
          local entry = encodeParameterEntry(device, param, chunk, destAddr)
          if entry[4] == 0 then -- chunks remaining
            nextStatusChunk[device.id] = 0
          else
            nextStatusChunk[device.id] = chunk + 1
          end
          queuePush(CRSF.FRAMETYPE_PARAMETER_SETTINGS_ENTRY, entry)
        else
          if t == CRSF.STRING then
            local chars = {}
            local i = 4
            while data[i] and data[i] ~= 0 do
              chars[#chars + 1] = data[i]
              i = i + 1
            end
            param.value = shim.charsToString(chars)
            if param.id == 20 then
              local echo = findParam(device, 24)
              if echo then
                echo.value = param.value
              end
            end
          elseif t == CRSF.FLOAT then
            local v = bit32.lshift(data[4] or 0, 24)
              + bit32.lshift(data[5] or 0, 16)
              + bit32.lshift(data[6] or 0, 8)
              + (data[7] or 0)
            if v >= 0x80000000 then
              v = v - 0x100000000
            end
            param.value = v
          elseif t == CRSF.UINT16 or t == CRSF.INT16 then
            local v = bit32.lshift(data[4] or 0, 8) + (data[5] or 0)
            if t == CRSF.INT16 and v >= 0x8000 then
              v = v - 0x10000
            end
            param.value = v
          elseif t == CRSF.INT8 then
            local v = writeValue or 0
            if v >= 0x80 then
              v = v - 0x100
            end
            param.value = v
          else
            param.value = writeValue
          end
          -- Dynamic power off hides Fan Thresh
          if device.id == CRSF.ADDRESS_TX and param.id == 8 then
            local fanThresh = findParam(device, 9)
            if fanThresh then
              fanThresh.hidden = (param.value == 0) or nil
            end
          end
          -- Output Ch loads its siblings; sibling edits save back
          if device.id == CRSF.ADDRESS_RX then
            if param.id == 9 then
              local cfg = pwmChannelConfig[param.value]
              if cfg then
                local inputChParam = findParam(device, 10)
                local outputModeParam = findParam(device, 11)
                local invertParam = findParam(device, 12)
                if inputChParam then
                  inputChParam.value = cfg.inputChannel
                end
                if outputModeParam then
                  outputModeParam.value = cfg.mode
                end
                if invertParam then
                  invertParam.value = cfg.inverted
                end
              end
            elseif param.id == 10 or param.id == 11 or param.id == 12 then
              local outputChParam = findParam(device, 9)
              local ch = outputChParam and outputChParam.value or 1
              local cfg = pwmChannelConfig[ch]
              if cfg then
                if param.id == 10 then
                  cfg.inputChannel = param.value
                end
                if param.id == 11 then
                  cfg.mode = param.value
                end
                if param.id == 12 then
                  cfg.inverted = param.value
                end
              end
            end
          end

          -- Firmware updates names in its event loop and pushes no folder
          -- entry after a write; Lua must re-read
          folderNamesReadyAt = getTime() + FOLDER_NAMES_UPDATE_TICKS
          folderNamesDevice = device
        end
      end
    end
    return true
  elseif command == CRSF.FRAMETYPE_MSP_REQ then
    local deviceId = data[1]
    local replyTo = data[2] or CRSF.ADDRESS_HANDSET
    if data[5] == CRSF.MSP_ELRS_RXTX_CONFIG and data[6] == CRSF.MSP_RXTX_UID then
      if deviceId == CRSF.ADDRESS_TX then
        queuePush(CRSF.FRAMETYPE_MSP_RESP, encodeMspUidResponse(deviceId, replyTo, mspUid[deviceId]))
      -- No RX, no answer: exercises the Bind tool's bounded retry
      elseif deviceId == CRSF.ADDRESS_RX and isRxAvailable() then
        queuePushDeferred(CRSF.FRAMETYPE_MSP_RESP, encodeMspUidResponse(deviceId, replyTo, mspUid[deviceId]))
      end
    end
    return true
  elseif command == CRSF.FRAMETYPE_MSP_WRITE then
    -- No ack from firmware
    local deviceId = data[1]
    local reachable = deviceId == CRSF.ADDRESS_TX or (deviceId == CRSF.ADDRESS_RX and isRxAvailable())
    if data[5] == CRSF.MSP_ELRS_RXTX_CONFIG and reachable then
      if data[6] == CRSF.MSP_RXTX_BIND_PHRASE then
        -- size counts subcmd + phrase
        local chars = {}
        for i = 7, 5 + (data[4] or 0) do
          chars[#chars + 1] = data[i]
        end
        mspUid[deviceId] = deriveUid(chars)
      elseif data[6] == CRSF.MSP_RXTX_UID then
        local uid = {}
        for i = 1, 6 do
          uid[i] = data[6 + i] or 0
        end
        mspUid[deviceId] = uid
      end
    end
    return true
  elseif command == CRSF.FRAMETYPE_COMMAND then
    -- Bind/unbind: logged only
    return true
  end

  return true
end

local function mockPop(consumer)
  if not startTime then
    startTime = getTime()
  end

  local now = getTime()
  local i = 1
  while i <= #delayedResponseQueue do
    if now >= delayedResponseQueue[i].deliverAt then
      local entry = shim.tableRemove(delayedResponseQueue, i)
      ---@diagnostic disable-next-line: need-check-nil
      queuePush(entry.command, entry.data)
    else
      i = i + 1
    end
  end

  local command, data = queuePop(consumer)

  if folderNamesDevice and getTime() >= folderNamesReadyAt then
    updateFolderNames(folderNamesDevice)
    updateTlmBandwidth(folderNamesDevice)
    updateVtxAdminOpts(folderNamesDevice)
    folderNamesDevice = nil
  end

  return command, data
end

local moduleFound = (config.scenario ~= "no_module")

-- ============================================================================
-- Telemetry sensors
-- ============================================================================

-- Downlink (TQly/TRSS) runs a few dB behind uplink: RX transmits at lower power
local scenarioTelemetry = {
  normal = {
    TPWR = 50,
    RFMD = 7,
    ["1RSS"] = -87,
    ["2RSS"] = -93,
    RQly = 99,
    RSNR = 8,
    ANT = 1,
    TQly = 100,
    TRSS = -95,
    RxBt = 15.2,
    Curr = 12.5,
    FM = "ACRO",
    Sats = 12,
    GSpd = 25.3,
    Alt = 142,
    GPS = { lat = 54.6872, lon = 25.2797 },
  },
  single_antenna = {
    TPWR = 50,
    RFMD = 7,
    ["1RSS"] = -84,
    ["2RSS"] = 0,
    RQly = 97,
    RSNR = 8,
    ANT = 0,
    TQly = 100,
    TRSS = -91,
    RxBt = 15.1,
    Curr = 11.0,
    FM = "ACRO",
    Sats = 11,
    GSpd = 22.4,
    Alt = 120,
    GPS = { lat = 54.6901, lon = 25.2712 },
  },
  armed = {
    TPWR = 250,
    RFMD = 7,
    ["1RSS"] = -78,
    ["2RSS"] = -82,
    RQly = 100,
    RSNR = 8,
    ANT = 0,
    TQly = 100,
    TRSS = -83,
    RxBt = 14.8,
    Curr = 28.5,
    FM = "ACRO",
    Sats = 14,
    GSpd = 42.7,
    Alt = 85,
    GPS = { lat = 54.7050, lon = 25.3100 },
  },
  -- X150 (v4 index 101)
  xband = {
    TPWR = 100,
    RFMD = 101,
    ["1RSS"] = -84,
    ["2RSS"] = -96,
    RQly = 100,
    RSNR = 6,
    ANT = 0,
    TQly = 100,
    TRSS = -90,
    RxBt = 16.4,
    Curr = 8.0,
    FM = "ANGL",
    Sats = 14,
    GSpd = 18.0,
    Alt = 120,
    GPS = { lat = 54.6872, lon = 25.2797 },
  },
  -- F1000 (v3 index 13)
  flrc = {
    TPWR = 250,
    RFMD = 13,
    ["1RSS"] = -70,
    ["2RSS"] = -74,
    RQly = 100,
    RSNR = 0,
    ANT = 0,
    TQly = 100,
    TRSS = -80,
    RxBt = 16.4,
    Curr = 18.0,
    FM = "ACRO",
    Sats = 10,
    GSpd = 45.0,
    Alt = 30,
    GPS = { lat = 54.6872, lon = 25.2797 },
  },
  -- 9K1000 (v3 index 18), no sensitivity figure
  unrated_rate = {
    TPWR = 250,
    RFMD = 18,
    ["1RSS"] = -79,
    ["2RSS"] = -84,
    RQly = 98,
    RSNR = 8,
    ANT = 0,
    TQly = 100,
    TRSS = -88,
    RxBt = 15.4,
    Curr = 9.8,
    FM = "ACRO",
    Sats = 10,
    GSpd = 18.2,
    Alt = 96,
    GPS = { lat = 54.6872, lon = 25.2797 },
  },
  -- Bench signal: must clear the model-match poll's -70 dBm gate
  model_mismatch = {
    TPWR = 50,
    RFMD = 7,
    ["1RSS"] = -55,
    ["2RSS"] = -58,
    RQly = 95,
    RSNR = 12,
    ANT = 1,
    TQly = 100,
    TRSS = -61,
    RxBt = 15.8,
    Curr = 0.5,
  },
  mismatch_cycle = {
    TPWR = 50,
    RFMD = 7,
    ["1RSS"] = -55,
    ["2RSS"] = -58,
    RQly = 95,
    RSNR = 12,
    ANT = 1,
    TQly = 100,
    TRSS = -61,
    RxBt = 15.8,
    Curr = 0.5,
    FM = "ACRO",
    Sats = 12,
    GSpd = 25.3,
    Alt = 142,
    GPS = { lat = 54.6872, lon = 25.2797 },
  },
  -- No sensorToggle entry: the link must never drop
  mismatch_recovery = {
    TPWR = 50,
    RFMD = 7,
    ["1RSS"] = -55,
    ["2RSS"] = -58,
    RQly = 95,
    RSNR = 12,
    ANT = 1,
    TQly = 100,
    TRSS = -61,
    RxBt = 15.8,
    Curr = 0.5,
  },
  -- Below every poll gate (RQly <= 90, RSSI <= -70 dBm)
  weak_link = {
    TPWR = 250,
    RFMD = 7,
    ["1RSS"] = -85,
    ["2RSS"] = -88,
    RQly = 60,
    RSNR = 2,
    ANT = 0,
    TQly = 62,
    TRSS = -97,
    RxBt = 15.2,
    Curr = 12.5,
    FM = "ACRO",
    Sats = 9,
    GSpd = 31.0,
    Alt = 210,
    GPS = { lat = 54.6600, lon = 25.2400 },
  },
  no_telemetry = {
    -- Sensors left from a previous flight; served as 0
    TPWR = 50,
    RFMD = 7,
    ["1RSS"] = -87,
    ["2RSS"] = -93,
    RQly = 99,
    RSNR = 8,
    ANT = 1,
    TQly = 100,
    TRSS = -95,
    RxBt = 15.2,
    Curr = 12.5,
    FM = "ACRO",
    Sats = 12,
    GSpd = 25.3,
    Alt = 142,
    GPS = { lat = 54.6872, lon = 25.2797 },
  },
  reconnect = {
    TPWR = 50,
    RFMD = 7,
    ["1RSS"] = -87,
    ["2RSS"] = -93,
    RQly = 99,
    RSNR = 8,
    ANT = 1,
    TQly = 100,
    TRSS = -95,
    RxBt = 15.2,
    Curr = 12.5,
  },
  slow_loading = {
    TPWR = 50,
    RFMD = 7,
    ["1RSS"] = -87,
    ["2RSS"] = -93,
    RQly = 99,
    RSNR = 8,
    ANT = 1,
    TQly = 100,
    TRSS = -95,
    RxBt = 15.2,
    Curr = 12.5,
    FM = "ACRO",
    Sats = 12,
    GSpd = 25.3,
    Alt = 142,
    GPS = { lat = 54.6872, lon = 25.2797 },
  },
  critical_error = {
    TPWR = 50,
    RFMD = 7,
    ["1RSS"] = -87,
    ["2RSS"] = -93,
    RQly = 99,
    RSNR = 8,
    ANT = 1,
    TQly = 100,
    TRSS = -95,
    RxBt = 15.2,
    Curr = 12.5,
    FM = "ACRO",
    Sats = 12,
    GSpd = 25.3,
    Alt = 142,
    GPS = { lat = 54.6872, lon = 25.2797 },
  },
}

-- +/- range; unlisted sensors are static
local sensorJitter = {
  ["1RSS"] = 3,
  ["2RSS"] = 3,
  TRSS = 3,
  RQly = 2,
  TQly = 2,
  RSNR = 2,
  RxBt = 0.05,
  Curr = 2.0,
  GSpd = 3.0,
  Alt = 5,
}

local sensorCeiling = {
  RQly = 100,
  TQly = 100,
}

-- Fixed sequences, one step per second; overrides base and jitter
local sensorToggle = {
  normal = {
    ANT = { 1, 1, 1, 1, 1, 0, 0, 0, 0, 0 }, -- ~5 s per antenna
  },
  single_antenna = {
    ["2RSS"] = { 0 },
  },
  xband = {
    ANT = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1 }, -- mostly sub-GHz first
  },
  flrc = {
    RSNR = { 0 },
  },
  mismatch_cycle = {
    RQly = { 95, 95, 95, 95, 95, 95, 95, 95, 95, 95, 0, 0, 0, 0, 0 },
  },
}
local toggleStep = 0

local telemetryCache = {}
local lastTelemetryUpdate = 0
local TELEMETRY_UPDATE_TICKS = 100 -- 1 s

local function updateTelemetryCache()
  local now = getTime()
  if now - lastTelemetryUpdate < TELEMETRY_UPDATE_TICKS then
    return
  end
  lastTelemetryUpdate = now

  local t = scenarioTelemetry[config.scenario]
  telemetryCache = {}
  if not t then
    return
  end

  if isRxAvailable() then
    toggleStep = toggleStep + 1
    local toggles = sensorToggle[config.scenario]
    for sensorId, base in pairs(t) do
      local seq = toggles and toggles[sensorId]
      local jit = sensorJitter[sensorId]
      if seq then
        telemetryCache[sensorId] = seq[(toggleStep % #seq) + 1]
      elseif jit then
        local val = base + (math.random() * 2 - 1) * jit
        if jit == math.floor(jit) then
          val = math.floor(val + 0.5)
        end
        local ceiling = sensorCeiling[sensorId]
        if ceiling and val > ceiling then
          val = ceiling
        end
        telemetryCache[sensorId] = val
      else
        telemetryCache[sensorId] = base
      end
    end
  end

  -- EdgeTX serves 0 for every sensor while RQly is 0 (luaGetValueAndPush)
  if (telemetryCache.RQly or 0) == 0 then
    for sensorId in pairs(t) do
      telemetryCache[sensorId] = 0
    end
  end
end

-- 0 while the link is down (as EdgeTX); nil for sensors the scenario lacks
local function mockGetSensorValue(sensorId)
  updateTelemetryCache()
  return telemetryCache[sensorId]
end

return {
  pop = mockPop,
  push = mockPush,
  moduleFound = moduleFound,
  getSensorValue = mockGetSensorValue,
}
