---------------------------------------------------------------------------
-- VTX Administrator Widget - UI for 480x320 (SD Tall)                   --
-- Jumper T15, T15 Pro, TX15, ST16, PL18                                 --
---------------------------------------------------------------------------

local ctx = ...
local bgOpacity = ctx.bgOpacity
local VTXDisplay = ctx.VTXDisplay
local WidgetLayout = ctx.WidgetLayout

local WidgetUI = {}

-- Breakpoints for 480x320.
WidgetUI.breakpoints = {
  topBarW = 100,
  sixthH = 50,
  -- 1/6 zones stack the cells on a second row from here up
  sixthStackH = 40,
  sixthStackW = 180,
  quarterH = 62,
  thirdH = 118,
  halfH = 147,
  -- Full-width zone; gates cells on the 1/6 inline row
  wideW = 340,
}

-- cellH is the preset cell height; cells is its font.
-- 1/3 zones start at 62px: too short for MIDSIZE over the cells.
WidgetUI.fonts = {
  sixth = { status = BOLD, cells = SMLSIZE, cellH = 16 },
  quarter = { status = BOLD, cells = SMLSIZE, cellH = 20 },
  third = { hero = BOLD, cells = SMLSIZE, cellH = 20 },
  half = { hero = MIDSIZE, cells = STDSIZE, cellH = 24 },
  full = { hero = DBLSIZE, cells = STDSIZE, cellH = 26 },
}

local CELL_ROUNDED = 4

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

--- 1/6 zones. Two rows fit only by trimming vertical padding; otherwise one
--- inline row.
function WidgetUI.buildSixth(w, h, opa)
  local bp = WidgetUI.breakpoints
  local f = WidgetUI.fonts.sixth
  if h >= bp.sixthStackH and w >= bp.sixthStackW then
    local cellRow = cells(f, w)
    if cellRow then
      WidgetLayout.column(w, h, opa, {
        VTXDisplay.buildHeadline(w, f.status, { statusLabel() }),
        cellRow,
      }, {
        left = lvgl.PAD_SMALL,
        right = lvgl.PAD_SMALL,
        top = lvgl.PAD_TINY,
        -- Cells flush against the edge look clipped
        bottom = lvgl.PAD_SMALL,
      })
      return
    end
  end

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
  WidgetLayout.column(w, h, opa, rows, {
    left = lvgl.PAD_SMALL,
    right = lvgl.PAD_SMALL,
    top = lvgl.PAD_SMALL,
    -- Cells flush against the edge look clipped
    bottom = lvgl.PAD_SMALL + lvgl.PAD_TINY,
  })
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
