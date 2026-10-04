---------------------------------------------------------------------------
-- B&W Compatibility Layer                                               --
-- B&W radios have no table library.                                     --
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

return shim
