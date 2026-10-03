---------------------------------------------------------------------------
-- EdgeTX Version Gate                                                   --
-- Keep edgetx.yml min_edgetx_version in step.                           --
---------------------------------------------------------------------------

-- Keep in step with isSupported
local REQUIRED_VERSIONS = {
  "- 2.11.6 or later",
  "- 2.12.1 or later",
  "- 3.0 or later",
}

local function isSupported()
  local _ver, _radio, maj, minor, rev = getVersion()

  if maj >= 3 then
    return true
  elseif maj == 2 and minor == 12 and rev >= 1 then
    return true
  elseif maj == 2 and minor == 11 and rev >= 6 then
    return true
  end

  return false
end

return isSupported, REQUIRED_VERSIONS
