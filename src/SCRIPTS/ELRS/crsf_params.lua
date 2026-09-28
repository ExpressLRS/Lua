---------------------------------------------------------------------------
-- CRSF Parameter Codec                                                  --
--                                                                       --
-- PARAMETER_SETTINGS_ENTRY (0x2B) decoding, chunk reassembly and        --
-- parameter frame encoders. Never mutates frame data: reassemble() may  --
-- hand the caller's frame back as the decode buffer.                    --
--                                                                       --
-- Loaded via loadScript("/SCRIPTS/ELRS/crsf_params.lua")(crsf).         --
---------------------------------------------------------------------------

local crsf = ...

local shim = loadScript("/SCRIPTS/ELRS/shim.lua")()

local Params = {}

-- ============================================================================
-- Byte getters
-- ============================================================================

--- Read a big-endian unsigned integer from a byte array.
-- @param data    array of byte values
-- @param offset  1-based start offset
-- @param size    width in bytes
-- @return number
function Params.readValue(data, offset, size)
  local result = 0
  for i = 0, size - 1 do
    result = bit32.lshift(result, 8) + data[offset + i]
  end
  return result
end

--- Read a null-terminated string. Arrow bytes only occur in options.
-- @param data    array of byte values
-- @param offset  1-based start offset
-- @param last    cached previous result: when given, decoding is skipped and
--                it is returned as-is (the offset still advances past the
--                terminator). Only safe while no reload has flagged the
--                content as possibly changed.
-- @return string result (or last as-is), number nextOffset
function Params.readString(data, offset, last)
  if last then
    local b = data[offset]
    while b and b ~= 0 do
      offset = offset + 1
      b = data[offset]
    end
    return last, offset + 1
  end
  local parts = {}
  local b = data[offset]
  while b and b ~= 0 do
    parts[#parts + 1] = string.char(b)
    offset = offset + 1
    b = data[offset]
  end
  return shim.tableConcat(parts), offset + 1
end

--- Refill values in place from a ';'-separated option list. Empty options
-- stay as "" (disabled slots). Maps legacy arrow bytes 0xC0/0xC1 to
-- CHAR_UP/CHAR_DOWN.
-- @param data    array of byte values
-- @param offset  1-based start offset
-- @param values  the caller-owned option table to refill
-- @return number nextOffset, number optCount (count of non-empty options),
--         boolean changed (any slot differs from the previous contents)
function Params.readOptions(data, offset, values)
  local n = 0
  local vcnt = 0
  local changed = false
  local optParts = {}
  local b = data[offset]
  while b do
    offset = offset + 1
    if b == 59 or b == 0 then
      local opt = shim.tableConcat(optParts)
      n = n + 1
      if values[n] ~= opt then
        values[n] = opt
        changed = true
      end
      if #optParts > 0 then
        vcnt = vcnt + 1
        optParts = {}
      end
      if b == 0 then
        break
      end
    elseif b == 192 and CHAR_UP then
      optParts[#optParts + 1] = CHAR_UP
    elseif b == 193 and CHAR_DOWN then
      optParts[#optParts + 1] = CHAR_DOWN
    else
      optParts[#optParts + 1] = string.char(b)
    end
    b = data[offset]
  end
  for i = #values, n + 1, -1 do
    values[i] = nil
    changed = true
  end
  return offset, vcnt, changed
end

-- ============================================================================
-- Per-type field loaders
-- ============================================================================

local function fieldUnsignedLoad(field, data, offset, size, unitoffset)
  field.value = Params.readValue(data, offset, size)
  field.min = Params.readValue(data, offset + size, size)
  field.max = Params.readValue(data, offset + 2 * size, size)
  local unit = Params.readString(data, offset + (unitoffset or (4 * size)), field.unit)
  field.unit = (unit ~= "") and unit or nil
  if size ~= 1 then
    field.size = size
  end
end

local function fieldUnsignedToSigned(field, size)
  local bandval = bit32.lshift(0x80, (size - 1) * 8)
  field.value = field.value - bit32.band(field.value, bandval) * 2
  field.min = field.min - bit32.band(field.min, bandval) * 2
  field.max = field.max - bit32.band(field.max, bandval) * 2
end

local function fieldSignedLoad(field, data, offset, size, unitoffset)
  fieldUnsignedLoad(field, data, offset, size, unitoffset)
  fieldUnsignedToSigned(field, size)
  field.size = -size
end

local function fieldIntLoad(field, data, offset)
  local loadFn = (field.type % 2 == 0) and fieldUnsignedLoad or fieldSignedLoad
  return loadFn(field, data, offset, math.floor(field.type / 2) + 1)
end

local function fieldFloatLoad(field, data, offset)
  fieldSignedLoad(field, data, offset, 4, 21)
  field.prec = data[offset + 16]
  if field.prec > 3 then
    field.prec = 3
  end
  field.step = Params.readValue(data, offset + 17, 4)
  field.fmt = shim.tableConcat({ "%.", tostring(field.prec), "f" })
  field.prec = 10 ^ field.prec
end

local function fieldTextSelLoad(field, data, offset)
  local cached = field.dirty == nil and field.values or nil
  if cached then
    cached, offset = Params.readString(data, offset, cached)
  else
    local values = field.values
    if values == nil then
      values = {}
      field.values = values
    end
    local vcnt, changed
    offset, vcnt, changed = Params.readOptions(data, offset, values)
    field.disabled = (vcnt <= 1) or nil
    if changed then
      -- values keeps its identity; consumers watch this instead
      field.valuesRev = (field.valuesRev or 0) + 1
    end
  end
  field.value = data[offset]
  local unit = Params.readString(data, offset + 4)
  field.unit = (unit ~= "") and unit or nil
  field.dirty = nil
end

local function fieldStringLoad(field, data, offset)
  field.value, offset = Params.readString(data, offset)
  if #data >= offset then
    field.maxlen = data[offset]
  end
end

local function fieldCommandLoad(field, data, offset)
  field.status = data[offset]
  field.timeout = data[offset + 1]
  local info = Params.readString(data, offset + 2)
  field.info = (info ~= "") and info or nil
end

local function fieldFolderLoad(field, data, offset)
  field.children = {}
  while data[offset] and data[offset] ~= crsf.CONST.FIELD_LIST_END do
    field.children[#field.children + 1] = data[offset]
    offset = offset + 1
  end
end

-- Keyed by wire type + 1; UINT32..INT64 unsupported, as in ELRS firmware
local handlers = {
  [crsf.CONST.FIELD_UINT8 + 1] = fieldIntLoad,
  [crsf.CONST.FIELD_INT8 + 1] = fieldIntLoad,
  [crsf.CONST.FIELD_UINT16 + 1] = fieldIntLoad,
  [crsf.CONST.FIELD_INT16 + 1] = fieldIntLoad,
  [crsf.CONST.FIELD_FLOAT + 1] = fieldFloatLoad,
  [crsf.CONST.FIELD_TEXT_SELECTION + 1] = fieldTextSelLoad,
  [crsf.CONST.FIELD_STRING + 1] = fieldStringLoad,
  [crsf.CONST.FIELD_FOLDER + 1] = fieldFolderLoad,
  [crsf.CONST.FIELD_INFO + 1] = fieldStringLoad,
  [crsf.CONST.FIELD_COMMAND + 1] = fieldCommandLoad,
}

-- ============================================================================
-- Chunk reassembly
--
-- PARAMETER_SETTINGS_ENTRY payloads larger than the handset link's frame
-- limit arrive in chunks (CRSFEndpoint::sendParameter). Reassembly state
-- lives in a caller-owned rx table with these keys:
--   chunk   next chunk index to request (readable; do not write)
--   data    reassembly buffer for the in-flight entry
--   dataId  the field id the buffer belongs to
--   expect  duplicate-frame guard (chunks expected to remain)
--   done    field whose multi-chunk entry just completed, to swallow the
--           other consumers' trailing final chunks
-- Consumers initialize rx = { chunk = 0, expect = -1 }.
-- ============================================================================

--- Abandon any in-flight reassembly.
-- @param rx  the reassembly-state table
function Params.resetChunks(rx)
  rx.chunk = 0
  rx.data = nil
  rx.dataId = nil
  rx.done = nil
end

--- Feed one PARAMETER_SETTINGS_ENTRY frame into the reassembly.
-- expectedFieldId selects the consumption model: a caller waiting on one
-- specific field passes its id (nil while idle drops everything), a passive
-- caller (acceptUnsolicited) passes data[3] to accept any field from
-- deviceId -- the dataId gate then keeps a sibling-elicited entry for
-- another field out of an in-flight buffer.
-- Never mutates data, and never retains it: the single-frame fast path
-- returns data itself as the buffer, valid only for the current call.
-- @param rx               the reassembly-state table
-- @param deviceId         the device address answers must come from
-- @param data             the frame's byte array
-- @param expectedFieldId  the field id to accept
-- @return fieldId, buffer, offset  entry complete; buffer[offset] is the
--         parent byte, ready for decodeEntry
-- @return fieldId                  chunk consumed, more expected -- send the
--         next read, which carries the updated rx.chunk
-- @return nil                      frame dropped (wrong device or field,
--         cross-field continuation, duplicate chunk)
function Params.reassemble(rx, deviceId, data, expectedFieldId)
  if data[2] ~= deviceId or data[3] ~= expectedFieldId then
    Params.resetChunks(rx)
    return nil
  end
  -- An in-flight buffer only accepts continuation frames for its own field
  if rx.data and rx.dataId ~= data[3] then
    return nil
  end
  local chunksRemain = data[4]
  -- Other consumers' copies of the final chunk look like a fresh
  -- single-frame entry; drop them until the next request cycle
  if rx.done then
    if rx.done == data[3] then
      if chunksRemain == 0 and not rx.data then
        return nil
      end
    else
      rx.done = nil
    end
  end
  if rx.data and chunksRemain ~= rx.expect then -- duplicate chunk
    return nil
  end

  local buffer
  local offset
  if chunksRemain > 0 or rx.chunk > 0 then
    rx.data = rx.data or {}
    rx.dataId = data[3]
    buffer = rx.data
    for i = 5, #data do
      buffer[#buffer + 1] = data[i]
    end
    offset = 1
  else
    buffer = data
    offset = 5
  end

  if chunksRemain > 0 then
    rx.chunk = rx.chunk + 1
    rx.expect = chunksRemain - 1
    return data[3]
  end

  local wasChunked = rx.chunk > 0
  Params.resetChunks(rx)
  if wasChunked then
    rx.done = data[3]
  end
  return data[3], buffer, offset
end

-- ============================================================================
-- Entry decode
-- ============================================================================

--- Decode a complete PARAMETER_SETTINGS_ENTRY payload into the caller-owned
-- field table. Sets field.id, parent (0 -> nil), type (0x7F-masked), hidden
-- (0x80 bit, true/nil), name, and dispatches the per-type loader, which fills
-- value/min/max/unit (ints, floats), prec/step/fmt (floats), values/disabled
-- (text selections), maxlen (strings), status/timeout/info (commands) or
-- children (folders). min/max of 0 are normalized to nil.
-- @param field       the caller-owned field table to decode into
-- @param fieldId     the field id the payload belongs to
-- @param buffer      byte array holding the payload
-- @param offset      1-based offset of the parent byte within buffer
-- @param cachedName  pass the previous name to skip its decode (see
--                    readString); nil decodes it fresh
-- @return field, or nil when the entry is shorter than parent + type + one
--         name byte (the caller should still drop it from its queue)
function Params.decodeEntry(field, fieldId, buffer, offset, cachedName)
  if #buffer <= offset + 2 then -- parent + type + one name byte
    return nil
  end
  field.id = fieldId
  field.parent = (buffer[offset] ~= 0) and buffer[offset] or nil
  field.type = bit32.band(buffer[offset + 1], 0x7f)
  field.hidden = bit32.btest(buffer[offset + 1], 0x80) or nil
  field.name, offset = Params.readString(buffer, offset + 2, cachedName)
  local load = handlers[field.type + 1]
  if load then
    load(field, buffer, offset)
  end
  if field.min == 0 then
    field.min = nil
  end
  if field.max == 0 then
    field.max = nil
  end
  return field
end

-- ============================================================================
-- Frame encoders
--
-- Each returns (frameType, payload) for crsf.push(). deviceId is the
-- target, handsetId the reply-to address. Layouts per CRSFParameters.h.
-- ============================================================================

--- Encode a request for one chunk of a field's PARAMETER_SETTINGS_ENTRY.
-- Starts a new request cycle on rx; sends rx.chunk (0 = fresh entry).
-- @param rx         the reassembly-state table
-- @param fieldId    the field id to read
function Params.encodeRead(rx, deviceId, handsetId, fieldId)
  rx.done = nil
  return crsf.CONST.FRAMETYPE_PARAMETER_READ, { deviceId, handsetId, fieldId, rx.chunk }
end

--- Encode a PARAMETER_WRITE carrying a field's integer value, big-endian at
-- the field's width. field.size < 0 marks a signed field |size| bytes wide
-- (decodeEntry's convention), sent as two's complement. Default 1 byte.
-- @param field      table with id, value and optional size
function Params.encodeWriteInt(deviceId, handsetId, field)
  local value = field.value
  local size = field.size or 1
  if size < 0 then
    size = -size
    if value < 0 then
      value = bit32.lshift(0x100, (size - 1) * 8) + value
    end
  end

  local frame = { deviceId, handsetId, field.id }
  for i = size - 1, 0, -1 do
    frame[#frame + 1] = bit32.rshift(value, 8 * i) % 256
  end
  return crsf.CONST.FRAMETYPE_PARAMETER_WRITE, frame
end

--- Encode a PARAMETER_WRITE carrying a field's string value, clamped to
-- field.maxlen (default 32), inner NULs stripped, null-terminated.
-- @param field      table with id, value and optional maxlen
function Params.encodeWriteString(deviceId, handsetId, field)
  local frame = { deviceId, handsetId, field.id }
  local val = field.value or ""
  local maxlen = field.maxlen or 32
  if #val > maxlen then
    val = string.sub(val, 1, maxlen)
  end
  for i = 1, #val do
    local b = string.byte(val, i)
    if b ~= 0 then
      frame[#frame + 1] = b
    end
  end
  frame[#frame + 1] = 0
  return crsf.CONST.FRAMETYPE_PARAMETER_WRITE, frame
end

--- Encode a command-step PARAMETER_WRITE: one byte from the commandStep_e
-- machine (crsf.CONST.CMD_CLICK / CMD_CONFIRMED / CMD_CANCEL / CMD_QUERY).
-- @param fieldId    the command field's id
-- @param step       the command step byte
function Params.encodeCommandStep(deviceId, handsetId, fieldId, step)
  return crsf.CONST.FRAMETYPE_PARAMETER_WRITE, { deviceId, handsetId, fieldId, step }
end

-- Pseudo-field: TXModuleEndpoint.cpp calls supressCriticalErrors() on 0x2E
local FIELD_ID_SUPPRESS_CRITICAL_ERRORS = 0x2E

--- Encode the write that asks the module to stop reporting its critical
-- error flags (the bits above crsf.CONST.ELRS_FLAGS_WARNING_THRESHOLD in
-- the ELRS status byte).
function Params.encodeSuppressCriticalErrors(deviceId, handsetId)
  return crsf.CONST.FRAMETYPE_PARAMETER_WRITE, { deviceId, handsetId, FIELD_ID_SUPPRESS_CRITICAL_ERRORS, 0 }
end

return Params
