---------------------------------------------------------------------------
-- ELRS RF Mode Tables                                                   --
-- Loaded via loadScript() from ELRSTelemetry/telemetry.lua with no      --
-- arguments; returns the RfModes table.                                 --
--                                                                       --
-- Packet-rate names and sensitivity floors per ELRS major version.      --
-- RFMD is 0-based; callers pass the raw sensor value.                   --
---------------------------------------------------------------------------

local RfModes = {}

-- nil until a module answers a device ping
---@type table?
RfModes._names = nil
---@type table?
RfModes._floors = nil

---@type number?
RfModes._maj = nil

-- ============================================================================
-- Selection
-- ============================================================================

-- Newer firmware falls back to the newest known table
function RfModes.select(vMaj)
  local effMaj
  if vMaj >= 4 then
    effMaj = 4
  elseif vMaj == 3 then
    effMaj = 3
  end
  if RfModes._maj == effMaj then
    return
  end
  RfModes._maj = effMaj

  if effMaj == 4 then
    -- selene: allow(mixed_table)
    RfModes._names = {
      "25Hz",
      "50Hz",
      "100Hz",
      "100HzFull",
      "150Hz",
      "200Hz",
      "200HzFull",
      "250Hz",
      "333HzFull",
      "500Hz",
      "D50",
      "K1000Full",
      [21] = "25Hz",
      [22] = "50Hz",
      [23] = "100Hz",
      [24] = "100HzFull",
      [25] = "150Hz",
      [26] = "200Hz",
      [27] = "200HzFull",
      [28] = "250Hz",
      [29] = "333HzFull",
      [30] = "500Hz",
      [31] = "D250",
      [32] = "D500",
      [33] = "F500",
      [34] = "F1000",
      [35] = "DK250",
      [36] = "DK500",
      [37] = "K1000",
      [101] = "X100Full",
      [102] = "X150",
    }
    -- selene: allow(mixed_table)
    RfModes._floors = {
      -123,
      -120,
      -117,
      -112,
      0,
      -112,
      -111,
      -111,
      0,
      0,
      -112,
      -101,
      [21] = 0,
      [22] = -115,
      [23] = 0,
      [24] = -112,
      [25] = -112,
      [26] = 0,
      [27] = 0,
      [28] = -108,
      [29] = -105,
      [30] = -105,
      [31] = -104,
      [32] = -104,
      [33] = -104,
      [34] = -104,
      [35] = -103,
      [36] = -103,
      [37] = -103,
      [101] = -112,
      [102] = -112,
    }
  elseif effMaj == 3 then
    RfModes._names = {
      "",
      "25Hz",
      "50Hz",
      "100Hz",
      "100HzFull",
      "150Hz",
      "200Hz",
      "250Hz",
      "333HzFull",
      "500Hz",
      "D250",
      "D500",
      "F500",
      "F1000",
      "D50",
      "200HzFull",
      "DK500",
      "K1000",
      "9K1000",
      "K1000Full",
    }
    RfModes._floors = {
      0,
      -123,
      -115,
      -117,
      -112,
      -112,
      -112,
      -108,
      -105,
      -105,
      -104,
      -104,
      -104,
      -104,
      -112,
      -111,
      -103,
      -103,
      0,
      -101,
    }
  else
    RfModes._names = nil
    RfModes._floors = nil
  end
end

-- ============================================================================
-- Lookup
-- ============================================================================

function RfModes.name(rfmd)
  local names = RfModes._names
  return (names and names[rfmd + 1]) or table.concat({ "RFMD", tostring(rfmd) })
end

function RfModes.floor(rfmd)
  local floors = RfModes._floors
  local dbm = floors and floors[rfmd + 1]
  -- 0 = unrated; nil so callers' "or" defaults apply
  if dbm == 0 then
    return nil
  end
  return dbm
end

-- FLRC rates report no SNR
local NO_SNR = { D250 = true, D500 = true, F500 = true, F1000 = true }

function RfModes.hasSnr(rfmd)
  local names = RfModes._names
  local name = names and names[rfmd + 1]
  return not (name and NO_SNR[name])
end

-- Path 1 sub-GHz, path 2 2.4 GHz
local X_BAND = { X100Full = true, X150 = true }

function RfModes.isXband(rfmd)
  local names = RfModes._names
  local name = names and names[rfmd + 1]
  return name ~= nil and X_BAND[name] == true
end

-- ============================================================================
-- Return module
-- ============================================================================

return RfModes
