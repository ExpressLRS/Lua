---------------------------------------------------------------------------
-- Telemetry Sensor Reader                                               --
---------------------------------------------------------------------------

local Sensors = {}

Sensors._vCache = {}

--- Call on model change: field IDs are per-model sensor slots.
function Sensors.resetCache()
  Sensors._vCache = {}
end

--- Unknown sensors are retried each call until discovered.
function Sensors.getSensorValue(id)
  local cid = Sensors._vCache[id]
  if cid == nil then
    local info = getFieldInfo(id)
    if info == nil then
      return nil
    end
    cid = info.id
    Sensors._vCache[id] = cid
  end
  return getValue(cid)
end

return Sensors
