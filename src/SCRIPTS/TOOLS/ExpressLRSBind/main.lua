-- TNS|ExpressLRS Bind|TNE
---- #########################################################################
---- # ExpressLRS bind phrase manager; needs ExpressLRS 4.1+ (MSP)           #
---- # License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html               #
---- #########################################################################

local VERSION = "r1"
local useLvgl = (lvgl ~= nil)

---@diagnostic disable-next-line: need-check-nil
local loader = loadScript("/SCRIPTS/ELRS/loader.lua")()

local crsf = loader("/SCRIPTS/ELRS/crsf.lua")
local msp = loader("/SCRIPTS/ELRS/msp.lua", crsf)
local defer = loader("/SCRIPTS/ELRS/defer.lua")
local FileStorage = loader("/SCRIPTS/ELRS/file_storage.lua")
local History = loader("/SCRIPTS/TOOLS/ExpressLRSBind/history_storage.lua", FileStorage)
local isVersionSupported, requiredVersions = loader("/SCRIPTS/ELRS/edgetx_version.lua")
local versionOk = isVersionSupported()

-- getTime() ticks (10 ms)
local UID_RETRY_TICKS = 50
local UID_MAX_ATTEMPTS = 12 -- 6 s, outlasts a module reboot
local FOLLOWUP_TICKS = 100 -- settle after a write

local App = {
  -- Order matches the UIs' choice lists
  TARGET_TX = 1,
  TARGET_RX = 2,
  TARGET_BOTH = 3,

  target = 1,
  phrase = "",
  bothStep = nil, -- TARGET_RX during Both's RX write
  uid = {}, -- filled by msp.decodeUid
  uidFrom = nil,
  statusText = "Idle", -- nil shows the UID
  uidAttempts = 0,
  -- Bump only for build-time snapshots; a rebuild resets focus
  rev = 0,
  history = History,

  shouldExit = false,
  crsfModuleChecked = false,
  crsfModuleFound = false,
}

function App.checkCrsfModule()
  if App.crsfModuleChecked then
    return App.crsfModuleFound
  end
  App.crsfModuleChecked = true
  App.crsfModuleFound = crsf.hasCrsfModule()
  return App.crsfModuleFound
end

-- RX only answers over a live link
function App.isTargetReachable()
  return App.target == App.TARGET_TX or (App.target == App.TARGET_RX and crsf.hasTelemetry)
end

function App.isTargetReachableOrBoth()
  return App.target == App.TARGET_BOTH or App.isTargetReachable()
end

function App.uidLine()
  if App.statusText then
    return App.statusText
  end
  local u = App.uid
  local prefix = (App.uidFrom == crsf.CONST.ADDRESS_RX) and "RX" or "TX"
  return string.format("%s: %d, %d, %d, %d, %d, %d", prefix, u[1], u[2], u[3], u[4], u[5], u[6])
end

-- Decimal byte, spaces trimmed; no string patterns on B&W
local function parseByte(part)
  local i = 1
  local j = #part
  while i <= j and string.byte(part, i) == 32 do
    i = i + 1
  end
  while j >= i and string.byte(part, j) == 32 do
    j = j - 1
  end
  if i > j or j - i > 2 then
    return nil
  end
  local n = 0
  for k = i, j do
    local b = string.byte(part, k)
    if b < 48 or b > 57 then
      return nil
    end
    n = n * 10 + (b - 48)
  end
  if n > 255 then
    return nil
  end
  return n
end

-- 4-6 comma-separated bytes, zero-padded to 6; nil for a phrase
function App.parseUidText(text)
  local bytes = {}
  local pos = 1
  while pos <= #text do
    local comma = string.find(text, ",", pos, true)
    local part
    if comma then
      part = string.sub(text, pos, comma - 1)
      pos = comma + 1
    else
      part = string.sub(text, pos)
      pos = #text + 1
    end
    local n = parseByte(part)
    if n == nil then
      return nil
    end
    bytes[#bytes + 1] = n
  end
  local count = #bytes
  if count < 4 or count > 6 then
    return nil
  end
  local uid = { 0, 0, 0, 0, 0, 0 }
  for i = 1, count do
    uid[6 - count + i] = bytes[i]
  end
  return uid
end

-- Bounded: pre-4.1 devices never answer
function App.requestUid()
  if not App.isTargetReachable() then
    App.statusText = "Idle"
    return
  end
  if App.uidAttempts >= UID_MAX_ATTEMPTS then
    App.statusText = "No response (needs ELRS 4.1+)"
    return
  end
  App.uidAttempts = App.uidAttempts + 1
  App.statusText = "Updating..."
  local dest = (App.target == App.TARGET_TX) and crsf.CONST.ADDRESS_TX or crsf.CONST.ADDRESS_RX
  crsf.push(msp.encodeUidRead(dest, crsf.CONST.ADDRESS_HANDSET))
  defer.setTimeout(UID_RETRY_TICKS, App.requestUid)
end

function App.startUidRequest()
  App.uidAttempts = 0
  App.requestUid()
end

-- Both: RX first, as the write drops it off the link, then TX
function App.sendSet()
  if App.phrase == "" then
    return
  end
  if App.target == App.TARGET_BOTH then
    if App.bothStep == nil then
      App.bothStep = App.TARGET_RX
    else
      App.bothStep = nil
      -- CHOICE shows its build-time value; rebuild
      App.target = App.TARGET_TX
      App.rev = App.rev + 1
    end
  end
  local effective = App.bothStep or App.target
  if App.bothStep == nil then
    App.statusText = (App.target == App.TARGET_TX) and "Setting transmitter..." or "Setting receiver..."
  else
    App.statusText = "Setting RX and disconnecting..."
  end
  local dest = (effective == App.TARGET_TX) and crsf.CONST.ADDRESS_TX or crsf.CONST.ADDRESS_RX
  local uid = App.parseUidText(App.phrase)
  if uid then
    crsf.push(msp.encodeUidWrite(dest, crsf.CONST.ADDRESS_HANDSET, uid))
  else
    crsf.push(msp.encodePhraseWrite(dest, crsf.CONST.ADDRESS_HANDSET, App.phrase))
  end
  History.add(App.phrase)
  if App.bothStep == nil then
    defer.setTimeout(FOLLOWUP_TICKS, App.startUidRequest)
  else
    defer.setTimeout(FOLLOWUP_TICKS, App.sendSet)
  end
end

local function markSent()
  App.statusText = "Sent"
end

function App.sendBind()
  App.statusText = "Sending bind command..."
  crsf:sendBindCommand(crsf.CONST.ADDRESS_TX)
  defer.setTimeout(FOLLOWUP_TICKS, markSent)
end

function App.sendUnbind()
  App.statusText = "Sending unbind to RX..."
  crsf:sendBindCommand(crsf.CONST.ADDRESS_RX)
  defer.setTimeout(FOLLOWUP_TICKS, markSent)
end

function App.useHistory(i)
  local phrase = History.items[i]
  if phrase == nil then
    return
  end
  App.phrase = phrase
  App.rev = App.rev + 1
end

function App.removeHistory(i)
  History.remove(i)
end

function App.clearHistory()
  History.clear()
end

function App.onFrame(_consumer, command, data)
  if command ~= crsf.CONST.FRAMETYPE_MSP_RESP then
    return
  end
  local srcId = msp.decodeUid(data, App.uid)
  if srcId == nil then
    return
  end
  defer.clear()
  App.uidFrom = srcId
  App.statusText = nil
  App.uidAttempts = 0
end

local UI

-- Forward-declared so init() can drop itself
local M = {}

local function init()
  local deps = {
    App = App,
    crsf = crsf,
    msp = msp,
    VERSION = VERSION,
    versionOk = versionOk,
    requiredVersions = requiredVersions,
  }
  App.phrase = History.items[1] or ""
  if useLvgl then
    UI = loader("/SCRIPTS/TOOLS/ExpressLRSBind/ui/lvgl.lua", deps)
  else
    UI = loader("/SCRIPTS/TOOLS/ExpressLRSBind/ui/lcd.lua", deps)
  end
  UI.init()
  -- Wait for run()'s first drain to create the telemetry queue
  defer.setTimeout(1, App.startUidRequest)
  -- The returned table stays on the Lua stack and would pin init()
  M.init = nil
end

local function run(event, touchState)
  if event == nil then
    return 2
  end

  if UI.preCheck then
    local result = UI.preCheck(event)
    if result ~= nil then
      return result
    end
  end

  crsf.drain(App, App.onFrame)
  -- After drain, so a push is answered before its follow-up
  defer.poll()

  UI.render(event, touchState)

  if App.shouldExit then
    return 2
  end
  return 0
end

M.init = init
M.run = run
M.useLvgl = useLvgl
return M
