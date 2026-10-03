---------------------------------------------------------------------------
-- VTX Administrator Widget - Core                                       --
-- Loaded via loadScript() from ELRSVTXAdmin/main.lua. State is per      --
-- instance, except the shared PresetsStorage (its latch dedupes 6POS).  --
---------------------------------------------------------------------------

local zone, options, crsf, CRSFSession, PresetsStorage = ...

-- ============================================================================
-- VTXAdmin: client of the module's VTX Administrator
-- ============================================================================

-- Passive: also sees fields sibling instances requested
local session

local VTXAdmin = {
  PHASE_INIT = 0,
  PHASE_NO_MODULE = 1,
  PHASE_DISCOVER_ROOT = 2,
  PHASE_DISCOVER_CHILDREN = 3,
  PHASE_DISCOVER_VTX = 4,
  PHASE_READY = 5,
  PHASE_SENDING = 6,

  phase = 0, -- PHASE_INIT

  -- Detects suspension by a standalone tool
  lastTick = 0,

  DEBOUNCE = 20, -- 200ms in getTime() ticks (10ms each)

  -- Discovered by name at runtime
  ids = {
    folder = nil,
    band = nil,
    channel = nil,
    power = nil,
    pitmode = nil,
    send = nil,
  },

  -- Band 0 has no letter: "Off" for the VTX, "--" for an unused preset
  BAND_LETTERS = { "A", "B", "E", "F", "R", "L" },
  BAND_VALUES = { Off = 0, A = 1, B = 2, E = 3, F = 4, R = 5, L = 6 },

  statusText = "Initializing...",

  -- Mutated in place; UI closures hold references
  state = {
    band = 0, -- 0=Off, 1=A, 2=B, 3=E, 4=F, 5=R, 6=L
    bandLetter = "?",
    channel = 0,
    power = 0,
    pitmode = false, -- true only when pit mode is confirmed on
    pitmodeAux = nil, -- switch name when pit mode is bound to an aux switch
  },

  -- Edited in full screen; mutated in place
  desired = {
    band = 5, -- Raceband
    channel = 1,
    power = 0,
    pitmode = 0,
  },
}

--- Parse "VTX Admin (BAND:CHANNEL[:POWER[:PITMODE]])" into state.
--- PITMODE is "P", or an aux label plus up/down arrow when switch-bound.
--- Band Off drops the suffix, power "-" drops power and pit mode.
--- Aux binding sets pitmodeAux only: the name never has the switch position.
local function parseFolderName(name)
  local s = VTXAdmin.state
  local content = string.match(name, "%((.+)%)")
  if not content then
    s.band = 0
    s.bandLetter = "Off"
    s.channel = 0
    s.power = 0
    s.pitmode = false
    s.pitmodeAux = nil
    return true
  end

  local parts = {}
  for part in string.gmatch(content, "([^:]+)") do
    parts[#parts + 1] = part
  end
  if #parts < 2 then
    return false
  end

  s.bandLetter = parts[1]
  s.band = VTXAdmin.BAND_VALUES[parts[1]] or 0
  s.channel = tonumber(parts[2]) or 0
  s.power = tonumber(parts[3]) or 0
  if #parts < 4 then
    s.pitmode = false
    s.pitmodeAux = nil
  elseif parts[4] == "P" then
    s.pitmode = true
    s.pitmodeAux = nil
  else
    -- Strip the trailing arrow (multi-byte CHAR_UP/CHAR_DOWN)
    s.pitmode = false
    local part = parts[4]
    if CHAR_UP and string.sub(part, -#CHAR_UP) == CHAR_UP then
      s.pitmodeAux = string.sub(part, 1, -#CHAR_UP - 1)
    elseif CHAR_DOWN and string.sub(part, -#CHAR_DOWN) == CHAR_DOWN then
      s.pitmodeAux = string.sub(part, 1, -#CHAR_DOWN - 1)
    else
      s.pitmodeAux = string.sub(part, 1, -2)
    end
  end
  return true
end

function VTXAdmin.isTuned()
  return VTXAdmin.isActive() and VTXAdmin.state.band > 0
end

function VTXAdmin.isDisabled()
  return VTXAdmin.isActive() and VTXAdmin.state.band == 0
end

--- Power "-" drops power and pit mode from the folder name.
function VTXAdmin.hasPower()
  return VTXAdmin.isTuned() and VTXAdmin.state.power > 0
end

function VTXAdmin.syncDesiredFromState()
  local s = VTXAdmin.state
  local d = VTXAdmin.desired
  d.band = s.band
  d.channel = s.channel
  d.power = s.power
  d.pitmode = s.pitmode and 1 or 0
end

-- ============================================================================
-- VTXAdmin: state machine query helpers
-- ============================================================================

function VTXAdmin.isReady()
  return VTXAdmin.phase == VTXAdmin.PHASE_READY
end

function VTXAdmin.isSending()
  return VTXAdmin.phase == VTXAdmin.PHASE_SENDING
end

function VTXAdmin.isActive()
  return VTXAdmin.phase == VTXAdmin.PHASE_READY or VTXAdmin.phase == VTXAdmin.PHASE_SENDING
end

--- Presets are local, so they show before discovery finishes.
function VTXAdmin.hasModule()
  return VTXAdmin.phase ~= VTXAdmin.PHASE_NO_MODULE
end

-- ============================================================================
-- VTXAdmin: field handler (session onFieldUpdate callback)
-- ============================================================================

local function onField(field)
  local fieldId = field.id
  local fieldName = field.name

  if VTXAdmin.phase == VTXAdmin.PHASE_DISCOVER_ROOT then
    if fieldId == 0 and field.type == crsf.CONST.FIELD_FOLDER then
      -- Session auto-queues the root children
      VTXAdmin.phase = VTXAdmin.PHASE_DISCOVER_CHILDREN
      VTXAdmin.statusText = "Discovering fields..."
    end
  elseif VTXAdmin.phase == VTXAdmin.PHASE_DISCOVER_CHILDREN then
    if field.type == crsf.CONST.FIELD_FOLDER and string.sub(fieldName, 1, 9) == "VTX Admin" then
      VTXAdmin.ids.folder = fieldId
      parseFolderName(fieldName)
      session:loadFolder(fieldId)
      VTXAdmin.phase = VTXAdmin.PHASE_DISCOVER_VTX
      VTXAdmin.statusText = "Loading VTX fields..."
    elseif not session:isLoading() and VTXAdmin.ids.folder == nil then
      VTXAdmin.statusText = "VTX Admin not found"
    end
  elseif VTXAdmin.phase == VTXAdmin.PHASE_DISCOVER_VTX then
    if fieldName == "Band" or fieldName == "Band/Enable" then
      VTXAdmin.ids.band = fieldId
    elseif fieldName == "Channel" then
      VTXAdmin.ids.channel = fieldId
    elseif fieldName == "Pwr Lvl" then
      VTXAdmin.ids.power = fieldId
    elseif fieldName == "Pitmode" then
      VTXAdmin.ids.pitmode = fieldId
    elseif fieldName == "Send VTx" then
      VTXAdmin.ids.send = fieldId
    end

    if not session:isLoading() then
      if
        VTXAdmin.ids.band
        and VTXAdmin.ids.channel
        and VTXAdmin.ids.power
        and VTXAdmin.ids.pitmode
        and VTXAdmin.ids.send
      then
        VTXAdmin.phase = VTXAdmin.PHASE_READY
        VTXAdmin.statusText = ""
        VTXAdmin.syncDesiredFromState()
      else
        VTXAdmin.statusText = "VTX fields incomplete"
      end
    end
  elseif VTXAdmin.phase == VTXAdmin.PHASE_READY then
    if fieldId == VTXAdmin.ids.folder then
      parseFolderName(fieldName)
    end
  end
end

session = CRSFSession.new({
  acceptUnsolicited = true,
  responseTimeout = 50, -- always the local TX module
  onFieldUpdate = onField,
})

-- ============================================================================
-- VTXAdmin: 6POS quick-change and push-trigger automation
-- ============================================================================

local function mapTo6Pos(value)
  local pos = math.floor((value + 1024) * 6 / 2049) + 1
  if pos < 1 then
    pos = 1
  end
  if pos > 6 then
    pos = 6
  end
  return pos
end

--- Shared latch: one write per edge per radio, not per instance.
local function process6Pos()
  if not PresetsStorage.enabled then
    return
  end
  if PresetsStorage.source == 0 then
    return
  end

  local value = getValue(PresetsStorage.source)
  if value == nil then
    return
  end

  local latch = PresetsStorage.latch
  local pos = mapTo6Pos(value)
  local now = getTime()

  -- Debounce; shared, as the source is radio state
  if pos ~= latch.stablePos then
    latch.stablePos = pos
    latch.stableTime = now
    return
  end
  if now - latch.stableTime < VTXAdmin.DEBOUNCE then
    return
  end

  -- Latch only once writable, or the edge is lost for every instance.
  -- This also applies the boot position on the first ready tick.
  if not VTXAdmin.isReady() then
    return
  end

  -- A collection change also retunes
  if pos == latch.lastPos and PresetsStorage.collection == latch.lastCollection then
    return
  end
  latch.lastPos = pos
  latch.lastCollection = PresetsStorage.collection

  -- Unused slot: leave the VTX alone, no retry
  local preset = PresetsStorage.items[pos]
  if not preset or preset.band == 0 then
    return
  end

  VTXAdmin.applyPreset(preset.band, preset.channel)
  if PresetsStorage.autoPushVtx then
    VTXAdmin.pushToVtx()
  end
end

--- Rising edge on pushSource sends config; one push per radio.
local function processPushTrigger()
  if PresetsStorage.autoPushVtx then
    return
  end
  if PresetsStorage.pushSource == 0 then
    return
  end

  local val = getValue(PresetsStorage.pushSource)
  if val == nil then
    return
  end

  local latch = PresetsStorage.latch
  local high = val > 0

  -- New source: adopt its level without firing (also seeds at boot)
  if PresetsStorage.pushSource ~= latch.pushSourceSeen then
    latch.pushSourceSeen = PresetsStorage.pushSource
    latch.pushLastHigh = high
    return
  end

  -- Latch only once sendable, or the edge is lost
  if not VTXAdmin.isReady() and not VTXAdmin.isSending() then
    return
  end

  local wasHigh = latch.pushLastHigh
  latch.pushLastHigh = high

  if high and not wasHigh then
    VTXAdmin.pushToVtx()
  end
end

-- ============================================================================
-- VTXAdmin: state machine tick
-- ============================================================================

function VTXAdmin.tick()
  local now = getTime()

  -- Resumed after >1 s: a tool may have changed config, so read back once.
  -- Never poll: each read replaces an RC frame.
  if VTXAdmin.lastTick > 0 and now - VTXAdmin.lastTick > 100 and VTXAdmin.phase == VTXAdmin.PHASE_READY then
    session:refreshField(VTXAdmin.ids.folder, 0, 3)
  end
  VTXAdmin.lastTick = now

  if VTXAdmin.phase == VTXAdmin.PHASE_INIT then
    if crsf.hasCrsfModule() then
      VTXAdmin.phase = VTXAdmin.PHASE_DISCOVER_ROOT
      VTXAdmin.statusText = "Discovering..."
      session:reloadAll()
    else
      VTXAdmin.phase = VTXAdmin.PHASE_NO_MODULE
      VTXAdmin.statusText = "No CRSF module"
    end
  elseif VTXAdmin.phase == VTXAdmin.PHASE_SENDING and not session:isWriting() then
    print("VTXAdmin: write queue drained")
    VTXAdmin.phase = VTXAdmin.PHASE_READY
    -- ~100 ms for the module to apply the change
    session:refreshField(VTXAdmin.ids.folder, 10, 3)
  end

  session:tick()

  -- After the pump, so queued writes go out next tick
  process6Pos()
  processPushTrigger()
end

-- ============================================================================
-- VTXAdmin: write queue builder
-- ============================================================================

--- Write changed fields; pushToVtx() sends them to the VTX.
function VTXAdmin.writeConfig()
  if not VTXAdmin.isReady() then
    print("VTXAdmin: writeConfig() skipped - not ready")
    return
  end

  local s = VTXAdmin.state
  local d = VTXAdmin.desired

  print(table.concat({
    "VTXAdmin: writeConfig() desired: band=",
    d.band,
    " ch=",
    d.channel,
    " pwr=",
    d.power,
    " pit=",
    tostring(d.pitmode),
  }))
  print(table.concat({
    "VTXAdmin: writeConfig() current: band=",
    s.band,
    " ch=",
    s.channel,
    " pwr=",
    s.power,
    " pit=",
    tostring(s.pitmode),
  }))

  local wrote = 0
  if d.band ~= s.band then
    session:writeField({ id = VTXAdmin.ids.band, value = d.band })
    wrote = wrote + 1
  end
  if d.channel ~= s.channel then
    session:writeField({ id = VTXAdmin.ids.channel, value = d.channel })
    wrote = wrote + 1
  end
  if d.power ~= s.power then
    session:writeField({ id = VTXAdmin.ids.power, value = d.power })
    wrote = wrote + 1
  end

  local desiredPit = d.pitmode
  local currentPit = s.pitmode and 1 or 0
  if desiredPit ~= currentPit then
    session:writeField({ id = VTXAdmin.ids.pitmode, value = desiredPit })
    wrote = wrote + 1
  end

  print(table.concat({ "VTXAdmin: writeConfig() wrote ", wrote, " field(s)" }))

  if wrote > 0 then
    VTXAdmin.phase = VTXAdmin.PHASE_SENDING
  end
end

--- Re-sync first: desired may hold stale power/pitmode.
function VTXAdmin.applyPreset(band, channel)
  VTXAdmin.syncDesiredFromState()
  VTXAdmin.desired.band = band
  VTXAdmin.desired.channel = channel
  VTXAdmin.writeConfig()
end

function VTXAdmin.pushToVtx()
  if not VTXAdmin.isReady() and VTXAdmin.phase ~= VTXAdmin.PHASE_SENDING then
    print("VTXAdmin: pushToVtx() skipped - not ready")
    return
  end

  print("VTXAdmin: pushToVtx() - sending Send VTx command")
  session:writeField({ id = VTXAdmin.ids.send, value = crsf.CONST.CMD_CLICK })
  VTXAdmin.phase = VTXAdmin.PHASE_SENDING
end

-- ============================================================================
-- Display components
-- ============================================================================

local VTXDisplay, WidgetLayout = loadScript("/WIDGETS/ELRSVTXAdmin/ui/display.lua")(VTXAdmin, PresetsStorage)

-- ============================================================================
-- Screen detection and UI loading
-- ============================================================================

local function getScreenId()
  local w, h = LCD_W, LCD_H
  if w >= 800 then
    return "hd" -- 800x480
  elseif w < h then
    return "portrait" -- 320x480 (EL18)
  elseif w <= 320 then
    return "small" -- 320x240
  elseif h >= 320 then
    return "sd_tall" -- 480x320 (T15, T15 Pro, TX15, ST16, PL18)
  else
    return "sd" -- 480x272 (TX16S, MAX, Mk II)
  end
end

--- Transparency option 0-5 -> opacity 255-0
local function bgOpacity(opts)
  local t = (opts and opts.Transparency) or 2
  return math.max(0, 255 - 51 * t)
end

local screenId = getScreenId()
local uiPath = table.concat({ "/WIDGETS/ELRSVTXAdmin/ui/", screenId, ".lua" })
local WidgetUI = loadScript(uiPath)({
  VTXAdmin = VTXAdmin,
  bgOpacity = bgOpacity,
  VTXDisplay = VTXDisplay,
  WidgetLayout = WidgetLayout,
})

-- ============================================================================
-- Widget lifecycle
-- ============================================================================

local wgt = {
  zone = zone,
  options = options,
}

function wgt.background()
  session:drain()
  VTXAdmin.tick()
end

function wgt.refresh(_event, _touchState)
  wgt.background()
end

local FullScreenUI

--- Loaded on first use: only one widget is full screen at a time.
local function buildFullScreen()
  if not FullScreenUI then
    FullScreenUI = loadScript("/WIDGETS/ELRSVTXAdmin/ui/fullscreen.lua")(VTXAdmin, PresetsStorage)
  end
  FullScreenUI.build()
end

function wgt.update(newOptions)
  wgt.options = newOptions
  if lvgl.isFullScreen() then
    if VTXAdmin.isReady() then
      VTXAdmin.syncDesiredFromState()
    end
    buildFullScreen()
  else
    WidgetUI.build(wgt.zone, wgt.options)
  end
end

WidgetUI.build(wgt.zone, wgt.options)

return wgt
