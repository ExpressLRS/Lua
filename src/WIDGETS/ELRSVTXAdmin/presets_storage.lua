---------------------------------------------------------------------------
-- 6POS Preset Storage                                                   --
-- Loaded via loadScript() from ELRSVTXAdmin/main.lua with (FileStorage) --
-- and shared by every widget instance.                                  --
---------------------------------------------------------------------------

local FileStorage = ...

local PATH = "/WIDGETS/ELRSVTXAdmin/presets.txt"

-- One slot per 6POS position
local COLLECTION_COUNT = 6
local SLOT_COUNT = 6

-- Worst case ~240 bytes. FileStorage reads 512; past that the tail
-- collections are lost and reset to defaults on the next save.
local SAVE_KEYS = { "enabled", "source", "applyOnStart", "autoPushVtx", "pushSource", "collection" }
local COLLECTION_KEYS = {}
for c = 1, COLLECTION_COUNT do
  COLLECTION_KEYS[c] = table.concat({ "c", c })
  SAVE_KEYS[#SAVE_KEYS + 1] = COLLECTION_KEYS[c]
end

local PresetsStorage = {
  COLLECTION_COUNT = COLLECTION_COUNT,

  -- collections[c][i] = { band, channel }
  collections = {},

  -- Alias of collections[collection]; read it each time, never cache it
  items = {},

  collection = 1,

  -- Not persisted; shared so each edge is consumed once per radio
  latch = {
    lastPos = -1, -- last consumed 6POS position
    sourceSeen = 0, -- source lastPos came from
    lastCollection = -1,
    stablePos = -1, -- debounce candidate
    stableTime = 0,
    ---@type boolean?
    pushLastHigh = nil,
    pushSourceSeen = 0, -- source pushLastHigh came from
  },

  enabled = false,
  source = 0, -- 6POS source ID (0 = not configured)
  applyOnStart = false, -- apply the switch's preset on the first reading
  autoPushVtx = false, -- auto push to VTX on 6POS change
  pushSource = 0, -- source ID for manual "Send VTx" trigger (0 = not configured)
}

local function splitBandChannel(val)
  local comma = string.find(val, ",", 1, true)
  if not comma then
    return nil, nil
  end
  return tonumber(string.sub(val, 1, comma - 1)), tonumber(string.sub(val, comma + 1))
end

--- Invalid segments stay nil and get defaults.
local function splitSlots(val)
  local slots = {}
  local pos = 1
  for i = 1, SLOT_COUNT do
    local semi = string.find(val, ";", pos, true)
    local segment
    if semi then
      segment = string.sub(val, pos, semi - 1)
      pos = semi + 1
    else
      segment = string.sub(val, pos)
      pos = #val + 1
    end
    local band, channel = splitBandChannel(segment)
    if band and channel then
      slots[i] = { band = band, channel = channel }
    end
  end
  return slots
end

--- presets.txt: enabled/applyOnStart/autoPushVtx "1"/"0", source/pushSource are source
--- IDs, collection 1..6, c1..c6 = "band,channel;...". Default slots R1..R6.
function PresetsStorage.load()
  local kv = FileStorage.read(PATH) or {}
  PresetsStorage.enabled = (kv.enabled == "1")
  PresetsStorage.source = tonumber(kv.source) or 0
  PresetsStorage.applyOnStart = (kv.applyOnStart == "1")
  PresetsStorage.autoPushVtx = (kv.autoPushVtx == "1")
  PresetsStorage.pushSource = tonumber(kv.pushSource) or 0

  local collections = {}
  for c = 1, COLLECTION_COUNT do
    local slots = splitSlots(kv[COLLECTION_KEYS[c]] or "")
    for i = 1, SLOT_COUNT do
      if not slots[i] then
        slots[i] = { band = 5, channel = i }
      end
    end
    collections[c] = slots
  end
  PresetsStorage.collections = collections

  local collection = tonumber(kv.collection) or 1
  if collection < 1 or collection > COLLECTION_COUNT then
    collection = 1
  end
  PresetsStorage.collection = collection
  PresetsStorage.items = collections[collection]
end

function PresetsStorage.save()
  local values = {
    enabled = PresetsStorage.enabled and "1" or "0",
    source = PresetsStorage.source,
    applyOnStart = PresetsStorage.applyOnStart and "1" or "0",
    autoPushVtx = PresetsStorage.autoPushVtx and "1" or "0",
    pushSource = PresetsStorage.pushSource,
    collection = PresetsStorage.collection,
  }
  for c = 1, COLLECTION_COUNT do
    local slots = PresetsStorage.collections[c]
    local parts = {}
    for i = 1, SLOT_COUNT do
      parts[i] = table.concat({ slots[i].band, ",", slots[i].channel })
    end
    values[COLLECTION_KEYS[c]] = table.concat(parts, ";")
  end
  FileStorage.write(PATH, SAVE_KEYS, values)
end

--- Swap items in one assignment: LVGL callbacks may read it any frame.
function PresetsStorage.selectCollection(c)
  if c < 1 or c > COLLECTION_COUNT then
    return
  end
  if c == PresetsStorage.collection then
    return
  end
  PresetsStorage.collection = c
  PresetsStorage.items = PresetsStorage.collections[c]
  PresetsStorage.save()
end

PresetsStorage.load()

return PresetsStorage
