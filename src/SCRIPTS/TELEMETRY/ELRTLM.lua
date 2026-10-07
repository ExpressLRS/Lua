---------------------------------------------------------------------------
-- ExpressLRS Telemetry - B&W telemetry screen                           --
-- Requires /SCRIPTS/ELRS on the SD card.                                --
---------------------------------------------------------------------------

---@diagnostic disable-next-line: need-check-nil
local loader = loadScript("/SCRIPTS/ELRS/loader.lua")()

local crsf = loader("/SCRIPTS/ELRS/crsf.lua")
local Telemetry = loader("/SCRIPTS/ELRS/telemetry/state.lua", crsf)
local Dashboard = loader("/SCRIPTS/ELRS/telemetry/lcd/dashboard.lua", Telemetry)
local Details

local function background()
  Telemetry.drain()
  Telemetry.update()
end

local function run(event)
  if Details then
    if Details.run(event) then
      Details = nil
      collectgarbage("collect")
      Dashboard.draw()
    end
    return 0
  end
  if event == EVT_VIRTUAL_ENTER and Telemetry.hasModule() then
    Details = loader("/SCRIPTS/ELRS/telemetry/lcd/details.lua", Telemetry, Dashboard)
    Details.run(0)
    return 0
  end
  Dashboard.draw()
  return 0
end

return { run = run, background = background }
