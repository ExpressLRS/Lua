---------------------------------------------------------------------------
-- VTX Administrator Widget - Loadable                                   --
---------------------------------------------------------------------------

local zone, options, crsf, CRSFSession, PresetsStorage = ...

local VTXAdmin = loadScript("/SCRIPTS/ELRS/vtx/admin.lua")(crsf, CRSFSession, PresetsStorage)

-- ============================================================================
-- Display components
-- ============================================================================

local VTXDisplay, WidgetLayout = loadScript("/WIDGETS/ELRSVTXAdmin/ui/display.lua")(VTXAdmin, PresetsStorage)

-- ============================================================================
-- Screen detection and UI loading
-- ============================================================================

local function getScreenId()
  local w, h = LCD_W, LCD_H
  if w >= 800 then
    return "hd" -- 800x480
  elseif w < h then
    return "portrait" -- 320x480 (EL18)
  elseif w <= 320 then
    return "small" -- 320x240
  elseif h >= 320 then
    return "sd_tall" -- 480x320 (T15, T15 Pro, TX15, ST16, PL18)
  else
    return "sd" -- 480x272 (TX16S, MAX, Mk II)
  end
end

--- Transparency option 0-5 -> opacity 255-0
local function bgOpacity(opts)
  local t = (opts and opts.Transparency) or 2
  return math.max(0, 255 - 51 * t)
end

local screenId = getScreenId()
local uiPath = table.concat({ "/WIDGETS/ELRSVTXAdmin/ui/", screenId, ".lua" })
local WidgetUI = loadScript(uiPath)({
  VTXAdmin = VTXAdmin,
  bgOpacity = bgOpacity,
  VTXDisplay = VTXDisplay,
  WidgetLayout = WidgetLayout,
})

-- ============================================================================
-- Widget lifecycle
-- ============================================================================

local wgt = {
  zone = zone,
  options = options,
}

function wgt.background()
  VTXAdmin.tick()
end

function wgt.refresh(_event, _touchState)
  wgt.background()
end

local FullScreenUI

--- Loaded on first use: only one widget is full screen at a time.
local function buildFullScreen()
  if not FullScreenUI then
    FullScreenUI = loadScript("/WIDGETS/ELRSVTXAdmin/ui/fullscreen.lua")(VTXAdmin, PresetsStorage)
  end
  FullScreenUI.build()
end

function wgt.update(newOptions)
  wgt.options = newOptions
  if lvgl.isFullScreen() then
    if VTXAdmin.isReady() then
      VTXAdmin.syncDesiredFromState()
    end
    buildFullScreen()
  else
    WidgetUI.build(wgt.zone, wgt.options)
  end
end

WidgetUI.build(wgt.zone, wgt.options)

return wgt
