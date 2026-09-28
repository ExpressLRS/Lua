---------------------------------------------------------------------------
-- Minimized Display Layer                                               --
-- Loaded via loadScript() from ELRSVTXAdmin/loadable.lua with           --
-- (VTXAdmin, PresetsStorage); returns VTXDisplay, WidgetLayout.         --
---------------------------------------------------------------------------

local VTXAdmin, PresetsStorage = ...

-- ============================================================================
-- WidgetLayout: minimized zone container builders
-- ============================================================================

local WidgetLayout = {}

--- pad overrides borderPad; a table trims vertical padding only.
function WidgetLayout.column(w, h, opa, children, pad)
  lvgl.build({
    {
      type = lvgl.RECTANGLE,
      x = 0,
      y = 0,
      w = w,
      h = h,
      color = COLOR_THEME_PRIMARY2,
      opacity = opa,
      filled = true,
    },
    {
      type = lvgl.BOX,
      x = 0,
      y = 0,
      w = w,
      h = h,
      align = LEFT,
      flexFlow = lvgl.FLOW_COLUMN,
      flexPad = 0,
      borderPad = pad or lvgl.PAD_SMALL,
      children = children,
    },
  })
end

function WidgetLayout.row(w, h, opa, children)
  lvgl.build({
    {
      type = lvgl.RECTANGLE,
      x = 0,
      y = 0,
      w = w,
      h = h,
      color = COLOR_THEME_PRIMARY2,
      opacity = opa,
      filled = true,
    },
    {
      type = lvgl.BOX,
      x = 0,
      y = 0,
      w = w,
      h = h,
      align = LEFT + VCENTER,
      flexFlow = lvgl.FLOW_ROW,
      flexPad = lvgl.PAD_TINY,
      borderPad = lvgl.PAD_SMALL,
      children = children,
    },
  })
end

-- ============================================================================
-- VTXDisplay: shared display formatters for minimized UI
-- ============================================================================

local VTXDisplay = {}

function VTXDisplay.showChannel()
  return VTXAdmin.isTuned()
end

function VTXDisplay.showStatus()
  return not VTXAdmin.isTuned()
end

function VTXDisplay.bandChannel()
  if not VTXAdmin.isTuned() then
    return ""
  end
  return table.concat({ VTXAdmin.state.bandLetter, VTXAdmin.state.channel })
end

function VTXDisplay.statusText()
  if not VTXAdmin.hasModule() then
    return "No module"
  end
  if not VTXAdmin.isActive() then
    return "Loading..."
  end
  if VTXAdmin.state.band == 0 then
    return "VTX Off"
  end
  return ""
end

function VTXDisplay.statusColor()
  if not VTXAdmin.hasModule() then
    return RED
  end
  return COLOR_THEME_SECONDARY1
end

--- Accent colour; red when pit mode is confirmed on.
function VTXDisplay.heroColor()
  if VTXAdmin.state.pitmode then
    return RED
  end
  return COLOR_THEME_FOCUS
end

--- "" without power: ExpressLRS hides pit mode then.
function VTXDisplay.pitHeaderText()
  if not VTXAdmin.hasPower() then
    return ""
  end
  if VTXAdmin.state.pitmode then
    return "PIT ON"
  end
  if VTXAdmin.state.pitmodeAux then
    return table.concat({ "PIT ", VTXAdmin.state.pitmodeAux })
  end
  return "PIT OFF"
end

function VTXDisplay.pitHeaderColor()
  return VTXAdmin.state.pitmode and RED or COLOR_THEME_SECONDARY1
end

--- e.g. "P2"; "" without power.
function VTXDisplay.powerShort()
  if not VTXAdmin.hasPower() then
    return ""
  end
  return table.concat({ "P", VTXAdmin.state.power })
end

--- e.g. "Power 2"; "" without power.
function VTXDisplay.powerLong()
  if not VTXAdmin.hasPower() then
    return ""
  end
  return table.concat({ "Power ", VTXAdmin.state.power })
end

--- Name left, pit state right. A plain box: a right-aligned label needs a width.
function VTXDisplay.buildHeader(w)
  local cw = w - 2 * lvgl.PAD_SMALL
  return {
    type = lvgl.BOX,
    w = cw,
    children = {
      {
        type = lvgl.LABEL,
        x = 0,
        y = 0,
        font = SMLSIZE,
        color = COLOR_THEME_SECONDARY1,
        text = "VTX Admin",
      },
      {
        type = lvgl.LABEL,
        x = 0,
        y = 0,
        w = cw,
        align = RIGHT,
        font = SMLSIZE,
        color = VTXDisplay.pitHeaderColor,
        text = VTXDisplay.pitHeaderText,
        visible = VTXDisplay.showChannel,
      },
    },
  }
end

--- Status or band/channel with power on its baseline; two flex children,
--- only the visible one takes a row.
function VTXDisplay.buildHero(font)
  local heroH = select(2, lcd.sizeText("0", font))
  -- 4/5: line boxes include descender room
  local drop = math.max(0, math.floor((heroH - select(2, lcd.sizeText("0", SMLSIZE))) * 4 / 5))
  return {
    type = lvgl.BOX,
    h = heroH,
    visible = VTXDisplay.showStatus,
    children = {
      {
        type = lvgl.LABEL,
        x = 0,
        y = math.max(0, math.floor((heroH - select(2, lcd.sizeText("0", BOLD))) / 2)),
        font = BOLD,
        color = VTXDisplay.statusColor,
        text = VTXDisplay.statusText,
      },
    },
  }, {
    type = lvgl.BOX,
    h = heroH,
    visible = VTXDisplay.showChannel,
    children = {
      {
        type = lvgl.LABEL,
        x = 0,
        y = 0,
        font = font,
        color = VTXDisplay.heroColor,
        text = VTXDisplay.bandChannel,
      },
      {
        type = lvgl.LABEL,
        x = (lcd.sizeText("R8", font)) + lvgl.PAD_MEDIUM,
        y = drop,
        font = SMLSIZE,
        color = COLOR_THEME_SECONDARY1,
        text = VTXDisplay.powerLong,
      },
    },
  }
end

--- Six fixed cells, the latched one lit; unset presets show "--".
--- nil when presets are off or there is no module.
function VTXDisplay.buildCells(spec)
  if not (VTXAdmin.hasModule() and PresetsStorage.enabled) then
    return nil
  end
  local gap = 4
  local font = spec.font or SMLSIZE
  local cellW = math.max((lcd.sizeText("R8", font)), (lcd.sizeText("--", font))) + 2 * lvgl.PAD_SMALL
  -- Squeeze, then drop to SMLSIZE, rather than clip
  if spec.w then
    local fit = math.floor((spec.w - 5 * gap) / 6)
    if font ~= SMLSIZE and fit < cellW and fit < (lcd.sizeText("R8", font)) + 2 * lvgl.PAD_TINY then
      font = SMLSIZE
      cellW = math.max((lcd.sizeText("R8", font)), (lcd.sizeText("--", font))) + 2 * lvgl.PAD_SMALL
    end
    cellW = math.min(cellW, math.max(fit, (lcd.sizeText("--", font))))
  end
  local function isActive(idx)
    return PresetsStorage.latch.lastPos == idx
  end
  local function cellText(idx)
    local p = PresetsStorage.items[idx]
    if p.band == 0 then
      return "--"
    end
    return table.concat({ VTXAdmin.BAND_LETTERS[p.band] or "?", p.channel })
  end
  local cells = {}
  for idx = 1, 6 do
    cells[idx] = {
      type = lvgl.RECTANGLE,
      w = cellW,
      h = spec.cellH,
      filled = true,
      rounded = spec.rounded,
      color = function()
        return isActive(idx) and COLOR_THEME_FOCUS or COLOR_THEME_DISABLED
      end,
      -- Background-only opacity; labels keep full weight
      opacity = function()
        return isActive(idx) and 255 or 90
      end,
      children = {
        {
          type = lvgl.LABEL,
          w = cellW,
          align = CENTER + VCENTER,
          font = font,
          color = function()
            return isActive(idx) and COLOR_THEME_PRIMARY2 or COLOR_THEME_SECONDARY1
          end,
          text = function()
            return cellText(idx)
          end,
        },
      },
    }
  end
  return {
    type = lvgl.BOX,
    flexFlow = lvgl.FLOW_ROW,
    borderPad = 0,
    flexPad = gap,
    align = LEFT,
    visible = VTXAdmin.hasModule,
    children = cells,
  }
end

--- Name then band/channel on one line; extras are appended labels.
function VTXDisplay.buildHeadline(w, font, extras)
  local children = {
    {
      type = lvgl.LABEL,
      align = LEFT,
      font = SMLSIZE,
      color = COLOR_THEME_SECONDARY1,
      text = "VTX Admin",
    },
    {
      type = lvgl.LABEL,
      align = LEFT,
      font = font,
      color = VTXDisplay.heroColor,
      text = VTXDisplay.bandChannel,
      visible = VTXDisplay.showChannel,
    },
    {
      type = lvgl.LABEL,
      align = LEFT,
      font = SMLSIZE,
      color = COLOR_THEME_SECONDARY1,
      text = VTXDisplay.powerShort,
      visible = VTXDisplay.showChannel,
    },
  }
  for i = 1, extras and #extras or 0 do
    children[#children + 1] = extras[i]
  end
  return {
    type = lvgl.BOX,
    w = w,
    align = LEFT + VCENTER,
    flexFlow = lvgl.FLOW_ROW,
    -- PAD_TINY runs "VTX Admin" and "R1" together
    flexPad = lvgl.PAD_MEDIUM,
    borderPad = 0,
    children = children,
  }
end

return VTXDisplay, WidgetLayout
