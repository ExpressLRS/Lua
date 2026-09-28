---------------------------------------------------------------------------
-- Bind Phrase History Storage                                           --
-- Newest first, as keys h1..hN. MAX * 56 bytes must fit FileStorage's   --
-- 512-byte read. No table library on B&W, so shifts are loops.          --
---------------------------------------------------------------------------

local FileStorage = ...

local PATH = "/SCRIPTS/TOOLS/ExpressLRSBind/history.txt"

local MAX = 5

local SAVE_KEYS = {}
for i = 1, MAX do
  SAVE_KEYS[i] = "h" .. i
end

local History = {
  MAX = MAX,
  items = {},
}

local function save()
  local values = {}
  for i = 1, #History.items do
    values[SAVE_KEYS[i]] = History.items[i]
  end
  FileStorage.write(PATH, SAVE_KEYS, values)
end

-- A re-used phrase moves to the front
function History.add(phrase)
  if phrase == nil or phrase == "" then
    return
  end
  local items = History.items
  for i = #items, 1, -1 do
    if items[i] == phrase then
      for j = i, #items - 1 do
        items[j] = items[j + 1]
      end
      items[#items] = nil
    end
  end
  for j = math.min(#items + 1, MAX), 2, -1 do
    items[j] = items[j - 1]
  end
  items[1] = phrase
  save()
end

function History.remove(idx)
  local items = History.items
  if items[idx] == nil then
    return
  end
  for j = idx, #items - 1 do
    items[j] = items[j + 1]
  end
  items[#items] = nil
  save()
end

function History.clear()
  History.items = {}
  save()
end

-- First missing key ends the list
local kv = FileStorage.read(PATH)
if kv then
  for i = 1, MAX do
    local v = kv[SAVE_KEYS[i]]
    if v == nil then
      break
    end
    History.items[i] = v
  end
end

return History
