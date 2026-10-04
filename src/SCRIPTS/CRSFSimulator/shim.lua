---------------------------------------------------------------------------
-- CRSF simulator polyfills: B&W builds lack table.concat/remove/unpack  --
---------------------------------------------------------------------------

local shim = {}

if table and table.concat then
  shim.tableConcat = table.concat
else
  shim.tableConcat = function(t, sep, i, j)
    i = i or 1
    j = j or #t
    if i > j then
      return ""
    end
    local r = t[i] or ""
    for k = i + 1, j do
      if sep then
        r = r .. sep
      end
      r = r .. (t[k] or "")
    end
    return r
  end
end

if table and table.remove then
  shim.tableRemove = table.remove
else
  shim.tableRemove = function(t, pos)
    local n = #t
    if n == 0 then
      return nil
    end
    pos = pos or n
    local val = t[pos]
    for i = pos, n - 1 do
      t[i] = t[i + 1]
    end
    t[n] = nil
    return val
  end
end

-- string.char(table.unpack(t)); iterative, a recursive unpack would blow the stack
function shim.charsToString(t, i, j)
  local parts = {}
  for k = i or 1, j or #t do
    parts[#parts + 1] = string.char(t[k])
  end
  return shim.tableConcat(parts)
end

return shim
