---------------------------------------------------------------------------
-- ELRS Telemetry Widget - Drawing Components                            --
-- Functions append lvgl descriptors to a caller-owned list; each        --
-- layout calls lvgl.build() once. Widget zones only use label,          --
-- rectangle and circle: fullscreen-only types fail silently.            --
-- hline has no thickness.                                               --
---------------------------------------------------------------------------

local Display = ...

local Components = {}

local TRACK_OPACITY = 90

local BRAND = "ExpressLRS"
local BRAND_SHORT = "ELRS"

local MISMATCH = "MODEL MISMATCH!"
local MISMATCH_SHORT = "MISMATCH!"

-- Widest string of each signal form, reserved so the row does not reflow.
local SIGNAL_FULL = "-105 -105 / -105 dBm"
local SIGNAL_SHORT = "-105 / -105 dBm"

local function antCell(m)
  return math.floor(m.sml / 2) + 1
end

-- ============================================================================
-- Metrics
-- ============================================================================

--- Font line heights. Measured, as 800x480 ships different fonts.
--- lcd.sizeText still works under LVGL (no LCD-buffer guard).
function Components.measure()
  local m = {
    pad = lvgl.PAD_SMALL,
    gap = lvgl.PAD_TINY,
    lines = {},
  }
  m.sml = Components.lineHeight(m, SMLSIZE)
  m.bold = Components.lineHeight(m, BOLD)
  m.mid = Components.lineHeight(m, MIDSIZE)
  return m
end

--- Line height of a font, cached on m.
function Components.lineHeight(m, font)
  local h = m.lines[font]
  if h == nil then
    h = select(2, lcd.sizeText("0", font))
    m.lines[font] = h
  end
  return h
end

--- Width of a string in a font, for reserving a column.
function Components.textWidth(s, font)
  return (lcd.sizeText(s, font))
end

--- Panel fills the zone; padding matches the VTX Admin widget.
--- inner is relative to the panel.
function Components.frame(w, h, m)
  return {
    panel = { x = 0, y = 0, w = w, h = h },
    inner = { x = m.pad, w = w - m.pad * 2 },
    pad = m.pad,
    h = h,
  }
end

--- Longest widget name that fits availW, or nil.
function Components.brandText(availW)
  if availW >= Components.textWidth(BRAND, SMLSIZE) then
    return BRAND
  end
  if availW >= Components.textWidth(BRAND_SHORT, SMLSIZE) then
    return BRAND_SHORT
  end
  return nil
end

--- Largest font in the list that fits the budget, else the last one.
function Components.heroFromLadder(m, ladder, budget)
  for i = 1, #ladder do
    local font = ladder[i]
    local fh = Components.lineHeight(m, font)
    if fh <= budget then
      return font, fh
    end
  end
  local last = ladder[#ladder]
  return last, Components.lineHeight(m, last)
end

-- ============================================================================
-- Elements
-- ============================================================================

--- Fill plus a borderless container, so opacity does not fade the content.
--- Returns the container's child list.
function Components.panel(dst, rect, spec)
  local children = {}
  dst[#dst + 1] = {
    type = lvgl.RECTANGLE,
    x = rect.x,
    y = rect.y,
    w = rect.w,
    h = rect.h,
    color = COLOR_THEME_PRIMARY2,
    opacity = spec.opacity,
    filled = true,
  }
  dst[#dst + 1] = {
    type = lvgl.RECTANGLE,
    x = rect.x,
    y = rect.y,
    w = rect.w,
    h = rect.h,
    thickness = 0,
    children = children,
  }
  return children
end

function Components.label(dst, spec)
  dst[#dst + 1] = {
    type = lvgl.LABEL,
    x = spec.x,
    y = spec.y,
    w = spec.w,
    align = spec.align or LEFT,
    font = spec.font,
    color = spec.color or COLOR_THEME_PRIMARY1,
    text = spec.text,
    visible = spec.visible,
  }
end

--- Horizontal bar. spec.pct returns 0-100; spec.visible hides the fill.
function Components.bar(dst, rect, y, spec)
  local h = spec.h
  local w = rect.w
  local r = math.floor(h / 2)
  dst[#dst + 1] = {
    type = lvgl.RECTANGLE,
    x = rect.x,
    y = y,
    w = w,
    h = h,
    color = COLOR_THEME_DISABLED,
    opacity = TRACK_OPACITY,
    filled = true,
    rounded = r,
  }
  dst[#dst + 1] = {
    type = lvgl.RECTANGLE,
    x = rect.x,
    y = y,
    w = w,
    h = h,
    color = spec.color,
    filled = true,
    rounded = r,
    -- luaL_checkunsigned; 0 would be a real zero-width object
    size = function()
      local fill = math.floor(w * (spec.pct() or 0) / 100)
      if fill < 1 then
        fill = 1
      elseif fill > w then
        fill = w
      end
      return fill, h
    end,
    visible = spec.visible,
  }
  return y + h
end

--- LED in a fixed lane; returns the x where text starts.
function Components.ledLane(dst, rect, y, m)
  local lane = math.floor(m.sml / 2) + 2
  Components.led(dst, {
    x = rect.x + math.floor(lane / 2),
    y = y + math.floor(m.sml / 2),
    radius = math.floor(m.sml / 4) + 1,
    color = Display.ledColor,
  })
  return rect.x + lane + m.pad
end

--- Status LED. x and y are the centre.
function Components.led(dst, spec)
  dst[#dst + 1] = {
    type = lvgl.CIRCLE,
    x = spec.x,
    y = spec.y,
    radius = spec.radius,
    filled = true,
    color = spec.color,
  }
end

--- Antenna dots, the active one lit.
function Components.antenna(dst, rect, y, m)
  local cell = antCell(m)
  local gap = m.gap
  local cx = rect.x
  local r = math.floor(cell / 2)
  for i = 1, 2 do
    dst[#dst + 1] = {
      type = lvgl.CIRCLE,
      x = cx + (i - 1) * (cell + gap) + r,
      y = y + math.floor(m.sml / 2),
      radius = r,
      color = Display.antColor(i),
      filled = true,
      visible = (i == 2) and function()
        return Display.isNotMismatch() and Display.hasDiversity()
      end or Display.isNotMismatch,
    }
  end
  return cx + 2 * cell + gap
end

-- ============================================================================
-- Blocks
-- ============================================================================

--- LED, name, RF mode and antenna dots; a model mismatch banner replaces
--- all but the LED. Returns the next free y.
function Components.headerRow(dst, rect, y, m, spec)
  local h = m.sml + 4
  local textX = Components.ledLane(dst, rect, y, m)
  local antW = 2 * antCell(m) + m.gap
  local antX = rect.x + rect.w - antW

  -- Widest rate name, so the row does not shift
  local modeW = Components.textWidth(spec.detail and "K1000Full 2000mW" or "K1000Full", SMLSIZE)
  local nameGap = m.pad * 2
  -- "Ant" caption only if the full name still fits
  local antLeft = antX
  local antCapW = Components.textWidth("Ant", SMLSIZE) + m.pad
  if antX - antCapW - m.pad - textX - modeW - nameGap >= Components.textWidth(BRAND, SMLSIZE) then
    antLeft = antX - antCapW
    Components.label(dst, {
      x = antLeft,
      y = y,
      font = SMLSIZE,
      color = COLOR_THEME_SECONDARY1,
      text = "Ant",
      visible = Display.isNotMismatch,
    })
  end
  local brand = Components.brandText(antLeft - m.pad - textX - modeW - nameGap)
  local nameX = textX
  if brand then
    textX = textX + Components.textWidth(brand, SMLSIZE) + nameGap
  end

  local bannerLimit = rect.x + rect.w
  local banner = MISMATCH
  if Components.textWidth(banner, BOLD) > bannerLimit - textX then
    banner = MISMATCH_SHORT
  end
  -- Still no room: hide the name during a mismatch
  local nameHides = Components.textWidth(banner, BOLD) > bannerLimit - textX
  local bannerX = textX
  if nameHides then
    bannerX = nameX
  end

  if brand then
    Components.label(dst, {
      x = nameX,
      y = y,
      font = SMLSIZE,
      color = COLOR_THEME_SECONDARY1,
      text = brand,
      visible = nameHides and Display.isNotMismatch or nil,
    })
  end
  Components.label(dst, {
    x = textX,
    y = y,
    font = SMLSIZE,
    color = COLOR_THEME_PRIMARY1,
    text = spec.detail and Display.rfDetailText or Display.rfModeText,
    visible = Display.isNotMismatch,
  })
  Components.label(dst, {
    x = bannerX,
    y = y,
    font = BOLD,
    color = COLOR_THEME_WARNING,
    text = banner,
    visible = Display.isMismatch,
  })

  Components.antenna(dst, { x = antX }, y, m)
  return y + h
end

--- LQ number with an "LQ %" caption; spec.right adds a small reading at the
--- right edge.
function Components.hero(dst, rect, y, m, spec)
  Components.label(dst, {
    x = rect.x,
    y = y,
    font = spec.font,
    color = Display.lqTextColor,
    text = Display.lqHeroText,
  })
  -- Baseline-align the caption; 4/5 as line boxes include descender room
  local drop = math.max(0, math.floor((spec.h - m.sml) * 4 / 5))
  Components.label(dst, {
    x = rect.x + Components.textWidth("100", spec.font) + m.pad,
    y = y + drop,
    font = SMLSIZE,
    color = COLOR_THEME_SECONDARY1,
    text = "LQ %",
  })
  if spec.right then
    Components.label(dst, {
      x = rect.x,
      y = y + drop,
      w = rect.w,
      align = RIGHT,
      font = SMLSIZE,
      color = Display.detailColor,
      text = spec.right,
    })
  end
  return y + spec.h
end

--- Caption on the left, value right-aligned.
function Components.valueRow(dst, rect, y, m, spec)
  Components.label(dst, {
    x = rect.x,
    y = y,
    font = SMLSIZE,
    color = COLOR_THEME_SECONDARY1,
    text = spec.caption,
  })
  Components.label(dst, {
    x = rect.x,
    y = y,
    w = rect.w,
    align = RIGHT,
    font = SMLSIZE,
    color = spec.color or COLOR_THEME_PRIMARY1,
    text = spec.text,
  })
  return y + m.sml
end

--- Per column: widest caption and widest reserved value.
local function gridColumns(rows)
  local cols = {}
  for i = 1, #rows do
    for j = 1, #rows[i] do
      local cell = rows[i][j]
      local col = cols[j]
      if col == nil then
        col = { caption = 0, value = 0 }
        cols[j] = col
      end
      col.caption = math.max(col.caption, Components.textWidth(cell.caption, SMLSIZE))
      col.value = math.max(col.value, Components.textWidth(cell.reserve, SMLSIZE))
    end
  end
  return cols
end

local function gridMinColW(m, rows)
  local need = 0
  local cols = gridColumns(rows)
  for j = 1, #cols do
    need = math.max(need, cols[j].caption + m.pad + cols[j].value)
  end
  return need
end

--- Two columns of { caption, text, reserve } cells, one per line when too
--- narrow. reserve is the widest string the value can render.
function Components.grid(dst, rect, y, m, rows)
  local colW = math.floor((rect.w - m.pad) / 2)
  if colW < gridMinColW(m, rows) then
    local flat = {}
    for i = 1, #rows do
      for j = 1, #rows[i] do
        flat[#flat + 1] = { rows[i][j] }
      end
    end
    rows = flat
    colW = rect.w
  end
  local cols = gridColumns(rows)
  for i = 1, #rows do
    local row = rows[i]
    for j = 1, #row do
      local cell = row[j]
      local cx = rect.x + (j - 1) * (colW + m.pad)
      Components.label(dst, {
        x = cx,
        y = y,
        font = SMLSIZE,
        color = COLOR_THEME_SECONDARY1,
        text = cell.caption,
      })
      Components.label(dst, {
        x = cx + cols[j].caption + m.pad,
        y = y,
        font = SMLSIZE,
        color = COLOR_THEME_PRIMARY1,
        text = cell.text,
      })
    end
    y = y + m.sml
    if i < #rows then
      y = y + m.gap
    end
  end
  return y
end

local function gridRows()
  return {
    {
      { caption = "PWR", text = Display.powerText, reserve = "2000 mW" },
      { caption = "TQly", text = Display.tqlyText, reserve = "100 %" },
    },
    {
      { caption = "BATT", text = Display.cellText, reserve = "4S 3.75 V" },
      { caption = "TRSS", text = Display.trssText, reserve = "-105 dBm" },
    },
  }
end

--- Widest signal form that fits availW.
local function signalFit(availW)
  if availW >= Components.textWidth(SIGNAL_FULL, SMLSIZE) then
    return Display.signalText
  end
  if availW >= Components.textWidth(SIGNAL_SHORT, SMLSIZE) then
    return Display.signalShortText
  end
  return Display.rssiText
end

-- ============================================================================
-- Layouts by zone size
-- ============================================================================

--- Header, LQ, LQ bar, RSSI row and bar, reading grid.
function Components.fullTier(w, h, opa, m, spec)
  local f = Components.frame(w, h, m)
  local pad, inner = f.pad, f.inner

  local rows = gridRows()
  local gridLines = 2
  if math.floor((inner.w - m.pad) / 2) < gridMinColW(m, rows) then
    gridLines = 4
  end
  local gridH = m.sml * gridLines + m.gap * (gridLines - 1)
  local MIN_BAR = 4
  -- Must match what the blocks below consume
  local fixedNoHero = pad * 2
    + (m.sml + 4) -- header row
    + m.gap -- header to LQ
    + m.gap -- LQ to LQ bar
    + m.sml -- RSSI row
    + m.gap -- RSSI row to its bar
    + gridH
  local heroFont, heroH = Components.heroFromLadder(m, spec.heroLadder, f.h - fixedNoHero - MIN_BAR * 2 - m.gap * 2)

  local slack = f.h - fixedNoHero - heroH
  local barH = math.max(MIN_BAR, math.min(math.floor(slack * 0.12), spec.barH))
  local air = math.max(m.gap, math.min(math.floor(slack / 6), m.sml))

  local root = {}
  local panel = Components.panel(root, f.panel, { opacity = opa })

  local y = Components.headerRow(panel, inner, pad, m, {})
  y = Components.hero(panel, inner, y + m.gap, m, { font = heroFont, h = heroH })
  y = Components.bar(panel, inner, y + m.gap, {
    h = barH,
    pct = Display.lqPct,
    color = Display.lqBarColor,
  })
  y = Components.valueRow(panel, inner, y + air, m, {
    caption = "RSSI",
    text = signalFit(inner.w - Components.textWidth("RSSI", SMLSIZE) - m.pad),
    color = Display.detailColor,
  })
  y = Components.bar(panel, inner, y + m.gap, {
    h = barH,
    pct = Display.headroomPct,
    color = Display.headroomBarColor,
    -- Needs a rated floor to scale
    visible = Display.hasHeadroom,
  })
  Components.grid(panel, inner, y + air, m, rows)

  lvgl.build(root)
end

--- Header with power, LQ, both bars, and the BATT/TRSS row when it fits.
function Components.halfTier(w, h, opa, m, spec)
  local f = Components.frame(w, h, m)
  local pad, inner = f.pad, f.inner
  local heroH = Components.lineHeight(m, spec.heroFont)
  local AIR_GAPS = 2
  local MIN_BAR = 3
  local fixed = pad * 2
    + (m.sml + 4) -- header row
    + heroH
    + m.gap -- LQ to LQ bar
    + m.sml -- RSSI row
    + m.gap -- RSSI row to its bar

  -- Drop the grid row before squeezing the bars
  local gridRow = { gridRows()[2] }
  local showGrid = (f.h - fixed - (m.sml + m.gap)) >= MIN_BAR * 2
    and math.floor((inner.w - m.pad) / 2) >= gridMinColW(m, gridRow)
  if showGrid then
    fixed = fixed + m.sml + m.gap
  end

  local slack = f.h - fixed
  local barH = math.max(MIN_BAR, math.min(math.floor(slack * 0.28), spec.barH))
  local air = math.max(0, math.floor((slack - barH * 2) / AIR_GAPS))

  local root = {}
  local panel = Components.panel(root, f.panel, { opacity = opa })

  local y = Components.headerRow(panel, inner, pad, m, { detail = true })
  y = Components.hero(panel, inner, y + air, m, { font = spec.heroFont, h = heroH })
  y = Components.bar(panel, inner, y + m.gap, {
    h = barH,
    pct = Display.lqPct,
    color = Display.lqBarColor,
  })
  y = Components.valueRow(panel, inner, y + air, m, {
    caption = "RSSI",
    text = signalFit(inner.w - Components.textWidth("RSSI", SMLSIZE) - m.pad),
    color = Display.detailColor,
  })
  y = Components.bar(panel, inner, y + m.gap, {
    h = barH,
    pct = Display.headroomPct,
    color = Display.headroomBarColor,
    visible = Display.hasHeadroom,
  })
  if showGrid then
    Components.grid(panel, inner, y + m.gap, m, gridRow)
  end

  lvgl.build(root)
end

--- Header, LQ with the signal on its baseline, RSSI bar.
function Components.thirdTier(w, h, opa, m, spec)
  local f = Components.frame(w, h, m)
  local pad, inner = f.pad, f.inner
  local heroH = Components.lineHeight(m, spec.heroFont)
  local AIR_GAPS = 2
  local MIN_BAR = 3
  local fixed = pad * 2
    + (m.sml + 4) -- header row
    + heroH
  local slack = f.h - fixed
  local barH = math.max(MIN_BAR, math.min(math.floor(slack * 0.45), spec.barH))
  local air = math.max(0, math.floor((slack - barH) / AIR_GAPS))

  local root = {}
  local panel = Components.panel(root, f.panel, { opacity = opa })

  local y = Components.headerRow(panel, inner, pad, m, { detail = true })
  local rightAvail = inner.w
    - Components.textWidth("100", spec.heroFont)
    - Components.textWidth("LQ %", SMLSIZE)
    - m.pad * 2
  y = Components.hero(panel, inner, y + air, m, {
    font = spec.heroFont,
    h = heroH,
    right = signalFit(rightAvail),
  })
  Components.bar(panel, inner, y + air, {
    h = barH,
    pct = Display.headroomPct,
    color = Display.headroomBarColor,
    visible = Display.hasHeadroom,
  })

  lvgl.build(root)
end

--- 1/4 and 1/6 zones: one row (name, RF detail, LQ, signal) over the RSSI
--- bar. The LQ spot shows the status text when there is one.
function Components.compactTier(w, h, opa, m, spec)
  local f = Components.frame(w, h, m)
  local pad, inner = f.pad, f.inner
  local heroH = Components.lineHeight(m, spec.heroFont)
  local MIN_BAR = 3
  local vpad = pad
  local slack = f.h - (vpad * 2 + heroH)
  if slack < MIN_BAR then
    -- 1/6 zone: shrink vertical padding to keep a bar
    vpad = m.gap
    slack = f.h - (vpad * 2 + heroH)
  end
  local barH = slack >= MIN_BAR and math.max(MIN_BAR, math.min(math.floor(slack * 0.3), spec.barH)) or 0
  local air = math.max(0, slack - barH)
  -- Baseline-align small text with the LQ
  local drop = math.max(0, heroH - m.sml)

  local root = {}
  local panel = Components.panel(root, f.panel, { opacity = opa })
  -- Centre the row when there is no bar
  local y = vpad + (barH > 0 and 0 or math.floor(air / 2))

  local textX = Components.ledLane(panel, inner, y + drop, m)
  local textRight = inner.x + inner.w
  local detailW = Components.textWidth("K1000Full 2000mW", SMLSIZE)
  local heroW = Components.textWidth("LQ 100%", spec.heroFont)
  -- Short signal rather than losing the name or the LQ
  local gap = m.pad * 2
  local brandW = Components.textWidth(BRAND_SHORT, SMLSIZE) + gap
  local signalW = Components.textWidth(SIGNAL_SHORT, SMLSIZE)
  local signalText = Display.signalShortText
  local avail = textRight - textX - signalW - heroW - gap
  if avail < brandW then
    local shortW = Components.textWidth("-105dBm", SMLSIZE)
    local shortAvail = textRight - textX - shortW - heroW - gap
    if shortAvail >= brandW or avail < 0 then
      signalW = shortW
      signalText = Display.rssiText
      avail = shortAvail
    end
  end
  local showDetail = avail >= detailW + gap
  if showDetail then
    avail = avail - detailW - gap
  end
  local brand = Components.brandText(avail - gap)

  if brand then
    Components.label(panel, {
      x = textX,
      y = y + drop,
      font = SMLSIZE,
      color = COLOR_THEME_SECONDARY1,
      text = brand,
    })
    textX = textX + Components.textWidth(brand, SMLSIZE) + gap
  end
  if showDetail then
    Components.label(panel, {
      x = textX,
      y = y + drop,
      font = SMLSIZE,
      color = COLOR_THEME_SECONDARY1,
      text = Display.rfDetailText,
      visible = Display.isNotMismatch,
    })
    textX = textX + detailW + gap
  end
  -- LQ and status swap in one spot; status is content-sized so it cannot wrap
  local heroRight = textRight - signalW - gap
  Components.label(panel, {
    x = textX,
    y = y,
    w = math.max(1, heroRight - textX),
    align = RIGHT,
    font = spec.heroFont,
    text = Display.lqText,
    visible = Display.noStatus,
  })
  Components.label(panel, {
    x = textX,
    y = y,
    font = spec.heroFont,
    color = Display.heroColor,
    text = Display.statusText,
    visible = Display.hasStatus,
  })
  Components.label(panel, {
    x = textRight - signalW,
    y = y + drop,
    w = signalW,
    align = RIGHT,
    font = SMLSIZE,
    color = Display.detailColor,
    text = signalText,
    visible = Display.isNotMismatch,
  })

  if barH > 0 then
    Components.bar(panel, inner, vpad + heroH + math.min(air, m.gap * 2), {
      h = barH,
      pct = Display.headroomPct,
      color = Display.headroomBarColor,
      visible = Display.hasHeadroom,
    })
  end

  lvgl.build(root)
end

return Components
