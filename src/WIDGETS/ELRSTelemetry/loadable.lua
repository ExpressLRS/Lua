---------------------------------------------------------------------------
-- ELRS Telemetry Widget - Wiring                                        --
-- Loaded via loadScript() from ELRSTelemetry/main.lua with              --
-- (zone, options, Telemetry); returns the widget instance table.        --
---------------------------------------------------------------------------

local zone, options, Telemetry = ...

-- ============================================================================
-- Display components
-- ============================================================================

local Display = loadScript("/WIDGETS/ELRSTelemetry/ui/display.lua")(Telemetry)
local Components = loadScript("/WIDGETS/ELRSTelemetry/ui/components.lua")(Display)

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

--- Convert Transparency option (0-5) to LVGL opacity (255-0).
local function bgOpacity(opts)
  local t = (opts and opts.Transparency) or 2
  return math.max(0, 255 - 51 * t)
end

local screenId = getScreenId()
local uiPath = table.concat({ "/WIDGETS/ELRSTelemetry/ui/", screenId, ".lua" })
local WidgetUI = loadScript(uiPath)({
  Display = Display,
  bgOpacity = bgOpacity,
  Components = Components,
})

-- ============================================================================
-- Widget lifecycle
-- ============================================================================

local wgt = {
  zone = zone,
  options = options,
}

-- drain() per instance (each owns a pop queue); update() runs once per tick
function wgt.background()
  Telemetry.drain()
  Telemetry.update()
end

function wgt.refresh(_event, _touchState)
  wgt.background()
end

local FullScreenUI

-- Loaded lazily; only one widget can be full screen
local function buildFullScreen()
  if not FullScreenUI then
    FullScreenUI = loadScript("/WIDGETS/ELRSTelemetry/ui/fullscreen.lua")(Telemetry, Display)
  end
  FullScreenUI.build()
end

function wgt.update(newOptions)
  wgt.options = newOptions
  if lvgl.isFullScreen() then
    buildFullScreen()
  else
    WidgetUI.build(wgt.zone, wgt.options)
  end
end

-- Label callbacks can fire before the first refresh()
Telemetry.update()

WidgetUI.build(wgt.zone, wgt.options)

return wgt
