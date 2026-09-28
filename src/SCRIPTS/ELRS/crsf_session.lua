---------------------------------------------------------------------------
-- CRSF Parameter Session                                                --
-- Field store, load/write queues and command state for one device.      --
-- One instance per consumer (config tool, each VTX Admin widget).       --
-- Loaded via loadScript("/SCRIPTS/ELRS/crsf_session.lua")(crsf,params). --
---------------------------------------------------------------------------

local crsf, params = ...

-- Scheduler constants (ticks, 10 ms each)
local STATUS_PERIOD = 100 -- link-status cadence (1 s)
local PING_PERIOD = 100 -- discovery ping cadence while no device answered
local WRITE_SPACING = 5 -- minimum gap between parameter writes (50 ms)
local WRITE_SETTLE = 20 -- post-write quiet time before the next read
local CANCEL_GRACE = 200 -- wait for CMD_IDLE after a requested cancel (2 s)
local QUERY_PERIOD = 100 -- command poll cadence without a device timeout (1 s)

local CRSFSession = {}
CRSFSession.__index = CRSFSession

--- opts: deviceId, handsetId, responseTimeout (ticks; 50 local TX, 500
--- remote), acceptUnsolicited (any field; default only the awaited one),
--- discovery (fills .devices), trackStatus (.status at 1 Hz), detectV1
--- (latches .v1Detected), preload (queue subfolders after root load),
--- onFieldUpdate(field), onDeviceUpdate(device, isNew)
function CRSFSession.new(opts)
  opts = opts or {}
  return setmetatable({
    deviceId = opts.deviceId or crsf.CONST.ADDRESS_TX,
    handsetId = opts.handsetId or crsf.CONST.ADDRESS_HANDSET,
    deviceName = nil,
    isElrsTx = nil,
    fieldsCount = 0,
    devices = {},
    command = nil, -- the command field driving the active popup
    commandAt = 0, -- click tick; UIs time grace periods from it
    status = { flags = 0, warning = "" }, -- identity stable; safe to cache
    fieldHiddenChanged = nil,
    v1Detected = nil,
    rx = { chunk = 0, expect = -1 },

    _acceptUnsolicited = opts.acceptUnsolicited,
    _discovery = opts.discovery,
    _trackStatus = opts.trackStatus,
    _detectV1 = opts.detectV1,
    _preload = opts.preload,
    _respTimeout = opts.responseTimeout,
    _onFieldUpdate = opts.onFieldUpdate,
    _onDeviceUpdate = opts.onDeviceUpdate,

    _fields = {}, -- get-or-create: UI closures hold field tables

    _loadQueue = {}, -- LIFO
    _nextReadAt = 0,
    _nextQueryAt = 0,
    _nextStatusAt = 0,
    _nextPingAt = 0,
    _lastWriteAt = 0,
    _pendingFrame = nil,

    _writeQueue = {},
    _writeHead = 1,
    _writeTail = 0,

    _refreshId = nil,
    _refreshAt = 0,
    _refreshLeft = 0,
    _refreshAttempts = 0,

    _hadTelemetry = false,
    _preloadArmed = nil,
    _preloading = nil,
  }, CRSFSession)
end

-- Remote devices answer over the air link: 5 s vs 0.5 s locally
function CRSFSession:_responseTimeout()
  if self._respTimeout then
    return self._respTimeout
  end
  return self.isElrsTx and 50 or 500
end

-- Some devices send timeout 0; never poll every tick
function CRSFSession:_queryPeriod()
  local timeout = self.command.timeout
  if timeout and timeout > 0 then
    return timeout
  end
  return QUERY_PERIOD
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

--- Returns true when the device changed.
function CRSFSession:setDevice(device)
  if not device then
    return false
  end
  if self.deviceId == device.id and self.fieldsCount == device.fieldCount then
    return false
  end

  self.deviceId = device.id
  self.deviceName = device.name
  self.fieldsCount = device.fieldCount
  self.isElrsTx = device.isElrs and device.id == crsf.CONST.ADDRESS_TX or nil
  local st = self.status
  st.flags = 0
  st.connected = nil
  st.modelMismatch = nil
  st.criticalError = nil

  self:reloadAll()
  return true
end

function CRSFSession:drain()
  crsf.drain(self, self._onFrame)
end

function CRSFSession:discoverDevices()
  crsf:pingDevices()
end

-- ============================================================================
-- Frame handlers
-- ============================================================================

function CRSFSession:_onFrame(command, data)
  if command == crsf.CONST.FRAMETYPE_PARAMETER_SETTINGS_ENTRY then
    self:_onEntry(data)
  elseif command == crsf.CONST.FRAMETYPE_DEVICE_INFO then
    if self._discovery then
      self:_onDeviceInfo(data)
    end
  elseif command == crsf.CONST.FRAMETYPE_ELRS_STATUS then
    if self._trackStatus then
      self:_onStatus(data)
    end
  elseif command == crsf.CONST.FRAMETYPE_PARAMETER_WRITE then
    if self._detectV1 then
      self:_onWrite(data)
    end
  end
end

function CRSFSession:_onDeviceInfo(data)
  local info = crsf:decodeDeviceInfo(data)
  if not info then
    return
  end
  local device = self:getDevice(info.id)
  local isNew = device == nil
  if isNew then
    device = { id = info.id }
    self.devices[#self.devices + 1] = device
  end
  device.name = info.name
  device.fieldCount = info.fieldCount
  device.isElrs = info.isElrs
  if self._onDeviceUpdate then
    self._onDeviceUpdate(device, isNew)
  end
end

function CRSFSession:_onStatus(data)
  local status = crsf:decodeElrsStatus(data)
  if not status then
    return
  end
  if status.id ~= self.deviceId then
    -- Another device's status interrupts our chunk stream
    params.resetChunks(self.rx)
    return
  end
  local st = self.status
  st.lostPackets = status.lostPackets
  st.receivedPackets = status.receivedPackets
  st.flags = status.flags
  st.connected = status.connected
  st.modelMismatch = status.modelMismatch
  st.criticalError = status.criticalError
  st.warning = status.warning
end

function CRSFSession:_onWrite(data)
  if crsf:isElrsV1Frame(data) then
    self.v1Detected = true
  end
end

function CRSFSession:_onEntry(data)
  local expectedId
  if self._acceptUnsolicited then
    expectedId = data[3]
  else
    expectedId = (self.command and self.command.id) or self._loadQueue[#self._loadQueue] or self._refreshId
  end
  local fieldId, buffer, offset = params.reassemble(self.rx, self.deviceId, data, expectedId)
  if not fieldId then
    return
  end
  local now = getTime()
  if not buffer then
    -- Request the next chunk now; commands continue only on CMD_QUERY
    if self.command and self.command.id == fieldId then
      self._nextQueryAt = 0
    elseif self._loadQueue[#self._loadQueue] == fieldId then
      self._nextReadAt = 0
    elseif self._refreshId == fieldId then
      self._refreshAt = now
      self._refreshLeft = self._refreshAttempts
    end
    return
  end

  -- Pop only if this answers the head; command answers arrive mid-load
  local answeredHead = self._loadQueue[#self._loadQueue] == fieldId
  if answeredHead then
    self._loadQueue[#self._loadQueue] = nil
  end
  if self._refreshId == fieldId then
    self._refreshId = nil
  end

  local field = self._fields[fieldId]
  if not field then
    field = {}
    self._fields[fieldId] = field
  end

  local wasHidden = field.hidden
  -- Strict: reuse the name unless flagged stale. Passive: only folder
  -- names embed values
  local cachedName
  if not self._acceptUnsolicited then
    cachedName = (not field.nameStale and not field.reloading) and field.name or nil
  elseif field.type ~= crsf.CONST.FIELD_FOLDER then
    cachedName = field.name
  end
  if params.decodeEntry(field, fieldId, buffer, offset, cachedName) then
    field.nameStale = nil
    field.reloading = nil
    if field.hidden ~= wasHidden then
      self.fieldHiddenChanged = true
    end

    if field.type == crsf.CONST.FIELD_COMMAND and field.status == crsf.CONST.CMD_IDLE and self.command == field then
      -- Command finished: re-read what it may have changed. Only the active
      -- command; idle command fields also load while browsing
      self:_reloadRelated(field)
      self.command = nil
      self._pendingFrame = nil
    end

    -- Only off our own read; siblings see every root answer
    if
      answeredHead
      and field.type == crsf.CONST.FIELD_FOLDER
      and field.children
      and (fieldId == 0 or self._preloading)
    then
      for i = #field.children, 1, -1 do
        self._loadQueue[#self._loadQueue + 1] = field.children[i]
      end
    end

    if self._onFieldUpdate then
      self._onFieldUpdate(field)
    end
  end

  if self.command then
    self._nextQueryAt = now + self:_queryPeriod()
  end
  if self._loadQueue[1] then
    self._nextReadAt = 0
  elseif self._preloadArmed and self:isFolderLoaded(nil) then
    self._preloadArmed = nil
    self:preloadAll()
  end
end

-- ============================================================================
-- Store queries
-- ============================================================================

function CRSFSession:getDevice(id)
  for _, device in ipairs(self.devices) do
    if device.id == id then
      return device
    end
  end
end

--- folderId nil means root.
function CRSFSession:fieldsInFolder(folderId)
  local folder = self._fields[folderId or 0]
  if not folder or not folder.children then
    return {}
  end
  local result = {}
  for _, childId in ipairs(folder.children) do
    local child = self._fields[childId]
    if child and child.name then
      result[#result + 1] = child
    end
  end
  return result
end

function CRSFSession:isFolderLoaded(folderId)
  local folder = self._fields[folderId or 0]
  if not folder or not folder.children then
    return false
  end
  for _, childId in ipairs(folder.children) do
    local child = self._fields[childId]
    if not child or not child.name or child.nameStale then
      return false
    end
  end
  return true
end

--- Returns loaded, total; nil while the children are unknown.
function CRSFSession:folderLoadProgress(folderId)
  local folder = self._fields[folderId or 0]
  if not folder or not folder.children then
    return nil
  end
  local total = #folder.children
  local loaded = 0
  for _, childId in ipairs(folder.children) do
    local child = self._fields[childId]
    if child and child.name and not child.reloading then
      loaded = loaded + 1
    end
  end
  return loaded, total
end

function CRSFSession:isLoading()
  return self._loadQueue[1] ~= nil
end

function CRSFSession:isReceivingChunks()
  return self.rx.chunk > 0
end

function CRSFSession:isWriting()
  return self._writeHead <= self._writeTail
end

-- ============================================================================
-- Loading
-- ============================================================================

function CRSFSession:reloadAll()
  self._fields = {}
  self._loadQueue = { 0 }
  self._nextReadAt = 0
  self._preloadArmed = self._preload
  self._preloading = nil
  params.resetChunks(self.rx)
end

function CRSFSession:reloadField(field)
  self._nextReadAt = 0
  params.resetChunks(self.rx)
  self._loadQueue[#self._loadQueue + 1] = field.id
end

function CRSFSession:loadFolder(folderId)
  local folder = self._fields[folderId]
  if not folder or not folder.children then
    return
  end
  for i = #folder.children, 1, -1 do
    local childId = folder.children[i]
    local child = self._fields[childId]
    if not (child and child.name) then
      self._loadQueue[#self._loadQueue + 1] = childId
    end
  end
  if self._loadQueue[1] then
    self._nextReadAt = 0
  end
end

function CRSFSession:preloadAll()
  self._preloading = true
  for id = 1, self.fieldsCount do
    local field = self._fields[id]
    if field and field.type == crsf.CONST.FIELD_FOLDER and field.children then
      for j = #field.children, 1, -1 do
        local childId = field.children[j]
        local child = self._fields[childId]
        if not (child and child.name) then
          self._loadQueue[#self._loadQueue + 1] = childId
        end
      end
    end
  end
  if self._loadQueue[1] then
    self._nextReadAt = 0
  end
end

--- One-off re-read after delay ticks, attempts default 3; not for polling.
function CRSFSession:refreshField(fieldId, delay, attempts)
  self._refreshId = fieldId
  self._refreshAt = getTime() + (delay or 0)
  self._refreshAttempts = attempts or 3
  self._refreshLeft = self._refreshAttempts
  params.resetChunks(self.rx) -- don't inherit an interrupted read's chunks
end

-- ============================================================================
-- Writing
-- ============================================================================

-- Parent name may embed values; siblings can hide or change options
function CRSFSession:_reloadRelated(field)
  if field.parent and self._fields[field.parent] then
    self._fields[field.parent].nameStale = true
    self._loadQueue[#self._loadQueue + 1] = field.parent
  end

  for fieldId = self.fieldsCount, 1, -1 do
    local sibling = self._fields[fieldId]
    if sibling and fieldId ~= field.id and sibling.parent == field.parent then
      local siblingType = sibling.type or 99
      if
        siblingType < crsf.CONST.FIELD_FOLDER
        or siblingType == crsf.CONST.FIELD_INFO
        or siblingType == crsf.CONST.FIELD_COMMAND
      then
        sibling.dirty = true
        sibling.reloading = true
        self._loadQueue[#self._loadQueue + 1] = fieldId
      end
    end
  end

  field.dirty = true
  field.reloading = true
  self._loadQueue[#self._loadQueue + 1] = field.id
  self:_afterWrite()
end

function CRSFSession:_afterWrite()
  local now = getTime()
  self._nextReadAt = now + WRITE_SETTLE
  local statusAt = now + WRITE_SETTLE + STATUS_PERIOD
  if self._nextStatusAt < statusAt then
    self._nextStatusAt = statusAt
  end
end

--- Each push replaces an RC-channels frame, so writes are paced.
--- Strict sessions re-read related fields; passive ones must refreshField().
function CRSFSession:writeField(field)
  local frameType, payload
  if field.type == crsf.CONST.FIELD_STRING then
    frameType, payload = params.encodeWriteString(self.deviceId, self.handsetId, field)
  else
    frameType, payload = params.encodeWriteInt(self.deviceId, self.handsetId, field)
  end

  local now = getTime()
  if self._writeHead > self._writeTail and now - self._lastWriteAt >= WRITE_SPACING then
    crsf.push(frameType, payload)
    self._lastWriteAt = now
  else
    self._writeTail = self._writeTail + 1
    self._writeQueue[self._writeTail] = { frameType, payload }
  end

  if not self._acceptUnsolicited then
    self:_reloadRelated(field)
  end
end

-- ============================================================================
-- Commands
-- ============================================================================

-- The radio's one Lua outbound slot may be busy; tick() retries
function CRSFSession:_sendStep(fieldId, step)
  local frameType, payload = params.encodeCommandStep(self.deviceId, self.handsetId, fieldId, step)
  if crsf.push(frameType, payload) then
    self._pendingFrame = nil
    self:_onStepSent(step)
  else
    self._pendingFrame = payload -- a newer step (e.g. cancel) replaces an unsent one
  end
end

-- Device restarts its answer at chunk 0 unless we are mid-entry. The reset
-- also clears rx.done, or a 1-chunk CMD_IDLE after a 2-chunk EXECUTING is
-- dropped as a duplicate
function CRSFSession:_onStepSent(step)
  if step ~= crsf.CONST.CMD_QUERY or self.rx.chunk == 0 then
    params.resetChunks(self.rx)
  end
end

function CRSFSession:execCommand(field)
  -- self.command is the guard; field.status is stale after a cancel
  if self.command or field.status == nil then
    return
  end
  field.status = crsf.CONST.CMD_CLICK
  self.command = field
  self.commandAt = getTime()
  self:_sendStep(field.id, crsf.CONST.CMD_CLICK)
  -- Re-query, never re-click: that would run Bind twice
  self._nextQueryAt = self.commandAt + self:_responseTimeout()
end

function CRSFSession:confirmCommand()
  if self.command then
    self.command.status = crsf.CONST.CMD_CONFIRMED
    self:_sendStep(self.command.id, crsf.CONST.CMD_CONFIRMED)
    self._nextQueryAt = getTime() + self:_responseTimeout()
  end
end

function CRSFSession:cancelCommand()
  if self.command then
    self:_sendStep(self.command.id, crsf.CONST.CMD_CANCEL)
    self.command = nil
  end
end

--- Keeps the popup until the device reports CMD_IDLE.
function CRSFSession:requestCancelCommand()
  if self.command then
    self:_sendStep(self.command.id, crsf.CONST.CMD_CANCEL)
    self._nextQueryAt = getTime() + CANCEL_GRACE
  end
end

-- ============================================================================
-- Status
-- ============================================================================

function CRSFSession:suppressCriticalErrors()
  self.status.flags = 0
  crsf.push(params.encodeSuppressCriticalErrors(self.deviceId, self.handsetId))
end

-- ============================================================================
-- Scheduler
-- ============================================================================

--- At most one frame per call: parked step > command > writes > status >
--- reads.
function CRSFSession:tick()
  local now = getTime()

  if self._discovery then
    -- Device may have changed
    local connected = self.status.connected
    if connected and not self._hadTelemetry then
      crsf:pingDevices()
    end
    self._hadTelemetry = connected
    if #self.devices == 0 and now > self._nextPingAt then
      crsf:pingDevices()
      self._nextPingAt = now + PING_PERIOD
    end
  end

  -- Even with no live command: a cancel must still go out
  if self._pendingFrame then
    if crsf.push(crsf.CONST.FRAMETYPE_PARAMETER_WRITE, self._pendingFrame) then
      local step = self._pendingFrame[4]
      self._pendingFrame = nil
      self:_onStepSent(step)
    end
    return
  end

  if self.command then
    if now > self._nextQueryAt and self.command.status ~= crsf.CONST.CMD_ASKCONFIRM then
      self:_sendStep(self.command.id, crsf.CONST.CMD_QUERY)
      self._nextQueryAt = now + self:_queryPeriod()
    end
    return -- reads starve while a command runs, by design
  end

  if self._writeHead <= self._writeTail then
    if now - self._lastWriteAt >= WRITE_SPACING then
      local write = self._writeQueue[self._writeHead]
      self._writeQueue[self._writeHead] = nil
      self._writeHead = self._writeHead + 1
      if self._writeHead > self._writeTail then
        self._writeHead = 1
        self._writeTail = 0
      end
      crsf.push(write[1], write[2])
      self._lastWriteAt = now
    end
    return
  end

  if self._trackStatus and now > self._nextStatusAt then
    if self.isElrsTx then
      -- Hardcodes ADDRESS_TX, which isElrsTx implies
      crsf:requestElrsStatus()
    else
      self.status.receivedPackets = nil
      self.status.lostPackets = nil
    end
    self._nextStatusAt = now + STATUS_PERIOD
    return
  end

  if self._refreshId then
    if now >= self._refreshAt then
      if self._refreshLeft > 0 then
        self._refreshLeft = self._refreshLeft - 1
        self._refreshAt = now + self:_responseTimeout()
        crsf.push(params.encodeRead(self.rx, self.deviceId, self.handsetId, self._refreshId))
      else
        self._refreshId = nil
      end
    end
    return
  end

  if now > self._nextReadAt then
    if self._loadQueue[1] then
      crsf.push(params.encodeRead(self.rx, self.deviceId, self.handsetId, self._loadQueue[#self._loadQueue]))
      self._nextReadAt = now + self:_responseTimeout()
    else
      self._preloading = nil
    end
  end
end

return CRSFSession
