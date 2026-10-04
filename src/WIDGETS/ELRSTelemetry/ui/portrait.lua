---------------------------------------------------------------------------
-- ELRS Telemetry Widget - UI for 320x480 (Portrait)                     --
-- FlySky EL18 — vertical screen                                         --
---------------------------------------------------------------------------

local ctx = ...
local Display = ctx.Display
local bgOpacity = ctx.bgOpacity
local Components = ctx.Components

local WidgetUI = {}

local metrics
local function measured()
  if not metrics then
    metrics = Components.measure()
  end
  return metrics
end

-- Breakpoints for 320x480 portrait.
-- No half layout: portrait zones past 1/3 fit the full one.
WidgetUI.breakpoints = {
  topBarW = 80,
  quarterH = 78,
  thirdH = 110,
}

-- The full layout uses the largest LQ font that fits.
WidgetUI.fonts = {
  compact = { hero = SMLSIZE },
  third = { hero = BOLD },
  full = { heroLadder = { DBLSIZE, MIDSIZE, BOLD } },
}

-- Max bar thickness.
local BAR_H = 5

local TopBarUI = loadScript("/WIDGETS/ELRSTelemetry/ui/topbar.lua")({ Display = Display })

--- 1/4 and 1/6 zones.
function WidgetUI.buildCompact(w, h, opa)
  local m = measured()
  Components.compactTier(w, h, opa, m, {
    heroFont = WidgetUI.fonts.compact.hero,
    barH = BAR_H,
  })
end

--- 1/3 zones.
function WidgetUI.buildThird(w, h, opa)
  local m = measured()
  Components.thirdTier(w, h, opa, m, {
    heroFont = WidgetUI.fonts.third.hero,
    barH = BAR_H,
  })
end

--- Full zone.
function WidgetUI.buildFull(w, h, opa)
  local m = measured()
  Components.fullTier(w, h, opa, m, {
    heroLadder = WidgetUI.fonts.full.heroLadder,
    barH = BAR_H,
  })
end

function WidgetUI.build(wgtZone, opts)
  lvgl.clear()
  local w, h = wgtZone.w, wgtZone.h
  local opa = bgOpacity(opts)
  local bp = WidgetUI.breakpoints
  if w < bp.topBarW then
    TopBarUI.build(w, h)
  elseif h < bp.quarterH then
    WidgetUI.buildCompact(w, h, opa)
  elseif h < bp.thirdH then
    WidgetUI.buildThird(w, h, opa)
  else
    WidgetUI.buildFull(w, h, opa)
  end
end

return WidgetUI
