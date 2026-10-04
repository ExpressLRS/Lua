-- TNS|ExpressLRS|TNE
---- #########################################################################
---- #                                                                       #
---- # Copyright (C) OpenTX, adapted for ExpressLRS                          #
---- #                                                                       #
---- # License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html               #
---- #                                                                       #
---- # Unified tool for BW and color LCD radios (EdgeTX 2.11.6+/2.12.1+)     #
---- #########################################################################

local VERSION = "r3"
local useLvgl = (lvgl ~= nil)

---@diagnostic disable-next-line: need-check-nil
local loader = loadScript("/SCRIPTS/ELRS/loader.lua")()

local crsf = loader("/SCRIPTS/ELRS/crsf.lua")
local params = loader("/SCRIPTS/ELRS/crsf_params.lua", crsf)
local CRSFSession = loader("/SCRIPTS/ELRS/crsf_session.lua", crsf, params)
local Navigation = loader("/SCRIPTS/TOOLS/ExpressLRS/navigation.lua")
local isVersionSupported, requiredVersions = loader("/SCRIPTS/ELRS/edgetx_version.lua")
local versionOk = isVersionSupported()

local App = {
  -- Synthetic row types; above 0x7f so no wire field type collides
  DEVICE = 128,
  DEVICE_FOLDER = 129,

  crsfModuleChecked = false,
  crsfModuleFound = false,
  shouldExit = false,
}

local UI
local session

function App.checkCrsfModule()
  if App.crsfModuleChecked then
    return App.crsfModuleFound
  end
  App.crsfModuleChecked = true
  App.crsfModuleFound = crsf.hasCrsfModule()
  return App.crsfModuleFound
end

function App.loadDevice(device)
  if session:setDevice(device) then
    Navigation.reset()
    return true
  end
  return false
end

function App.switchDevice(deviceId, viewState)
  local device = session:getDevice(deviceId)
  if not device then
    return false
  end
  local prevDeviceId = session.deviceId
  if session:setDevice(device) then
    Navigation.openDevice(device.name, prevDeviceId, viewState)
    return true
  end
  return false
end

function App.enterFolder(folderId, folderName, viewState)
  Navigation.openFolder(folderId, folderName, viewState)
  session:loadFolder(folderId)
end

function App.goBack()
  return Navigation.goBack()
end

function App.reloadAtRoot()
  if session.deviceId ~= crsf.CONST.ADDRESS_TX then
    local txDevice = session:getDevice(crsf.CONST.ADDRESS_TX)
    if txDevice then
      App.loadDevice(txDevice)
    end
  else
    session:reloadAll()
  end
  session:discoverDevices()
end

session = CRSFSession.new({
  discovery = true,
  trackStatus = true,
  detectUnsupported = true,
  preload = true,
  onDeviceUpdate = function(device, isNew)
    if device.id == session.deviceId and App.loadDevice(device) then
      UI.onDeviceLoaded()
    end
    if isNew then
      UI.onNewDevice()
    end
  end,
})

local M = {}

local function init()
  local deps = {
    App = App,
    Navigation = Navigation,
    session = session,
    crsf = crsf,
    VERSION = VERSION,
    versionOk = versionOk,
    requiredVersions = requiredVersions,
  }
  if useLvgl then
    UI = loader("/SCRIPTS/TOOLS/ExpressLRS/ui/lvgl.lua", deps)
  else
    UI = loader("/SCRIPTS/TOOLS/ExpressLRS/ui/lcd.lua", deps)
  end
  UI.init()
  -- Returned table stays on the Lua stack; don't pin init's upvalues
  M.init = nil
end

local function run(event, touchState)
  if event == nil then
    return 2
  end

  if UI.preCheck then
    local result = UI.preCheck(event)
    if result ~= nil then
      return result
    end
  end

  session:drain()
  if session.unsupported then
    UI.handleUnsupported()
    return 0
  end
  session:tick()

  local currentFolder = Navigation.getCurrent()
  local folderReady = session:isFolderLoaded(currentFolder)
  if folderReady and not UI.folderWasReady then
    collectgarbage("collect")
    UI.invalidate()
  end
  UI.folderWasReady = folderReady

  if session.fieldHiddenChanged then
    session.fieldHiddenChanged = nil
    UI.visibleFields = nil
  end

  UI.render(event, touchState)

  if App.shouldExit then
    return 2
  end
  return 0
end

M.init = init
M.run = run
M.useLvgl = useLvgl
return M
