---------------------------------------------------------------------------
-- ExpressLRS VTX Admin - B&W telemetry screen                           --
-- Requires /SCRIPTS/ELRS on the SD card.                                --
---------------------------------------------------------------------------

---@diagnostic disable-next-line: need-check-nil
local loader = loadScript("/SCRIPTS/ELRS/loader.lua")()

-- One per Lua state: B&W scripts share the frame queue through it
_crsfSingleton = _crsfSingleton or loader("/SCRIPTS/ELRS/crsf.lua")
local crsf = _crsfSingleton
crsf.resetSensorCache() -- outlives model changes
local params = loader("/SCRIPTS/ELRS/crsf_params.lua", crsf)
local CRSFSession = loader("/SCRIPTS/ELRS/crsf_session.lua", crsf, params)
local FileStorage = loader("/SCRIPTS/ELRS/file_storage.lua")
local PresetsStorage = loader("/SCRIPTS/ELRS/vtx/presets.lua", FileStorage)
local VTXAdmin = loader("/SCRIPTS/ELRS/vtx/admin.lua", crsf, CRSFSession, PresetsStorage)

local PRESET_LABELS = {}
for band = 1, #VTXAdmin.BAND_LETTERS do
  for channel = 1, 8 do
    PRESET_LABELS[band * 10 + channel] = VTXAdmin.BAND_LETTERS[band] .. channel
  end
end

local labels = {}

function labels.preset(band, channel)
  return PRESET_LABELS[band * 10 + channel] or "--"
end

function labels.power(power)
  return "Power " .. power
end

local Dashboard = loader("/SCRIPTS/ELRS/vtx/lcd/dashboard.lua", VTXAdmin, PresetsStorage, labels)
local Menu

local function background()
  VTXAdmin.tick()
end

local function run(event)
  if Menu then
    if Menu.run(event) then
      Menu = nil
      collectgarbage("collect")
      Dashboard.draw()
    end
    return 0
  end
  if event == EVT_VIRTUAL_ENTER and VTXAdmin.hasModule() then
    if VTXAdmin.isReady() then
      VTXAdmin.syncDesiredFromState()
    end
    Menu = loader("/SCRIPTS/ELRS/vtx/lcd/menu.lua", VTXAdmin, PresetsStorage, labels)
    Menu.run(0)
    return 0
  end
  Dashboard.draw()
  return 0
end

return { run = run, background = background }
