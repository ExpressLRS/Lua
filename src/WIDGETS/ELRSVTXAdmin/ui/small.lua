---------------------------------------------------------------------------
-- VTX Administrator Widget - UI for 320x240 (Small)                     --
-- Small color LCD (PA01)                                                --
---------------------------------------------------------------------------

local ctx = ...
local bgOpacity = ctx.bgOpacity
local VTXDisplay = ctx.VTXDisplay
local WidgetLayout = ctx.WidgetLayout

local WidgetUI = {}

-- Breakpoints for 320x240. 1/6 zones are too short to stack.
WidgetUI.breakpoints = {
  topBarW = 80,
  sixthH = 38,
  quarterH = 54,
  thirdH = 76,
  halfH = 100,
  -- Full-width zone; gates cells on the 1/6 inline row
  wideW = 240,
}

-- cellH is the preset cell height; cells is its font.
WidgetUI.fonts = {
  -- 1/6 inline row sizes cells to the zone
  sixth = { status = BOLD, cells = SMLSIZE },
  quarter = { status = BOLD, cells = SMLSIZE, cellH = 16 },
  third = { hero = BOLD, cells = SMLSIZE, cellH = 16 },
  half = { hero = MIDSIZE, cells = SMLSIZE, cellH = 20 },
  full = { hero = DBLSIZE, cells = STDSIZE, cellH = 22 },
}

local CELL_ROUNDED = 3

local TopBarUI = loadScript("/WIDGETS/ELRSVTXAdmin/ui/topbar.lua")({
  VTXDisplay = VTXDisplay,
})

local function statusLabel()
  return {
    type = lvgl.LABEL,
    align = LEFT,
    font = BOLD,
    color = VTXDisplay.statusColor,
    text = VTXDisplay.statusText,
    visible = VTXDisplay.showStatus,
  }
end

--- nil when presets are off.
local function cells(f, w, cellH)
  return VTXDisplay.buildCells({
    cellH = cellH or f.cellH,
    font = f.cells,
    rounded = CELL_ROUNDED,
    w = w - 2 * lvgl.PAD_SMALL,
  })
end

--- Header, band/channel with power, preset cells.
local function cardRows(f, w)
  local heroStatus, hero = VTXDisplay.buildHero(f.hero)
  local rows = { VTXDisplay.buildHeader(w), heroStatus, hero }
  rows[#rows + 1] = cells(f, w)
  return rows
end

--- 1/6 zones: one inline row.
function WidgetUI.buildSixth(w, h, opa)
  local bp = WidgetUI.breakpoints
  local f = WidgetUI.fonts.sixth
  local columns = {}
  if w >= bp.wideW then
    columns[#columns + 1] = {
      type = lvgl.LABEL,
      align = LEFT,
      font = SMLSIZE,
      color = COLOR_THEME_SECONDARY1,
      text = "VTX Admin",
    }
  end
  columns[#columns + 1] = statusLabel()
  columns[#columns + 1] = {
    type = lvgl.LABEL,
    -- Fixed width so the row doesn't shift
    w = (lcd.sizeText("R8", f.status)) + lvgl.PAD_SMALL,
    font = f.status,
    color = VTXDisplay.heroColor,
    text = VTXDisplay.bandChannel,
    visible = VTXDisplay.showChannel,
  }
  columns[#columns + 1] = {
    type = lvgl.LABEL,
    align = LEFT,
    font = SMLSIZE,
    color = COLOR_THEME_SECONDARY1,
    text = VTXDisplay.powerShort,
    visible = VTXDisplay.showChannel,
  }
  if w >= bp.wideW then
    local fontH = select(2, lcd.sizeText("0", f.cells))
    columns[#columns + 1] = cells(f, w, math.min(h - 2 * lvgl.PAD_SMALL, fontH + 2 * lvgl.PAD_SMALL))
  end

  WidgetLayout.row(w, h, opa, columns)
end

--- 1/4 zones.
function WidgetUI.buildQuarter(w, h, opa)
  local f = WidgetUI.fonts.quarter
  local rows = {
    VTXDisplay.buildHeadline(w, f.status, { statusLabel() }),
  }
  rows[#rows + 1] = cells(f, w)
  WidgetLayout.column(w, h, opa, rows)
end

--- 1/3 zones.
function WidgetUI.buildThird(w, h, opa)
  WidgetLayout.column(w, h, opa, cardRows(WidgetUI.fonts.third, w))
end

--- 1/2 zones.
function WidgetUI.buildHalf(w, h, opa)
  WidgetLayout.column(w, h, opa, cardRows(WidgetUI.fonts.half, w))
end

--- Full zone.
function WidgetUI.buildFull(w, h, opa)
  WidgetLayout.column(w, h, opa, cardRows(WidgetUI.fonts.full, w))
end

function WidgetUI.build(wgtZone, opts)
  lvgl.clear()
  local w, h = wgtZone.w, wgtZone.h
  local opa = bgOpacity(opts)
  local bp = WidgetUI.breakpoints
  if w < bp.topBarW then
    TopBarUI.build(w, h)
  elseif h < bp.sixthH then
    WidgetUI.buildSixth(w, h, opa)
  elseif h < bp.quarterH then
    WidgetUI.buildQuarter(w, h, opa)
  elseif h < bp.thirdH then
    WidgetUI.buildThird(w, h, opa)
  elseif h < bp.halfH then
    WidgetUI.buildHalf(w, h, opa)
  else
    WidgetUI.buildFull(w, h, opa)
  end
end

return WidgetUI
