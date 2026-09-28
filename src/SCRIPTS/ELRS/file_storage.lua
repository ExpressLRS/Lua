---------------------------------------------------------------------------
-- Key=Value File Storage                                                --
---------------------------------------------------------------------------

local shim = loadScript("/SCRIPTS/ELRS/shim.lua")()

local FileStorage = {}

local READ_MAX = 512 -- caps a corrupt file

local function parseKV(line)
  local eq = string.find(line, "=", 1, true)
  if not eq then
    return nil, nil
  end
  return string.sub(line, 1, eq - 1), string.sub(line, eq + 1)
end

--- nil when the file cannot be opened
function FileStorage.read(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local data = io.read(f, READ_MAX)
  io.close(f)
  local kv = {}
  if not data or #data == 0 then
    return kv
  end
  local pos = 1
  while pos <= #data do
    local nl = string.find(data, "\n", pos, true)
    local line
    if nl then
      line = string.sub(data, pos, nl - 1)
      pos = nl + 1
    else
      line = string.sub(data, pos)
      pos = #data + 1
    end
    local key, val = parseKV(line)
    if key and val then
      kv[key] = val
    end
  end
  return kv
end

--- Writes keys in order, skipping absent values; nil when the file cannot be opened
function FileStorage.write(path, keys, values)
  local f = io.open(path, "w")
  if not f then
    return nil
  end
  local lines = {}
  for i = 1, #keys do
    local val = values[keys[i]]
    if val ~= nil then
      lines[#lines + 1] = shim.tableConcat({ keys[i], "=", val, "\n" })
    end
  end
  io.write(f, shim.tableConcat(lines))
  io.close(f)
  return true
end

return FileStorage
