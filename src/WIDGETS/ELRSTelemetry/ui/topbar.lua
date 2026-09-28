---------------------------------------------------------------------------
-- ELRS Telemetry Widget - Shared Top Bar UI                             --
-- Matches the stock Value widget's layout: RSSI over LQ.                --
---------------------------------------------------------------------------

local ctx = ...
local Display = ctx.Display

local TopBarUI = {}

local VALUE_Y = math.floor(14 * lvgl.LCD_SCALE + 0.5) -- stock Value widget offset

-- PRIMARY2: the top bar is on the dark header.
local function barColor()
  if not Display.isConnected() then
    return COLOR_THEME_DISABLED
  end
  if Display.isMismatch() then
    return COLOR_THEME_WARNING
  end
  return COLOR_THEME_PRIMARY2
end

local function smallText()
  if not Display.isConnected() then
    return "--"
  end
  if Display.isMismatch() then
    return "Mismatch"
  end
  return Display.rssiText()
end

local function bigText()
  if not Display.isConnected() or Display.isMismatch() then
    return "--"
  end
  return table.concat({ Display.lqHeroText(), "%" })
end

function TopBarUI.build(w, h)
  lvgl.build({
    {
      type = lvgl.BOX,
      x = 0,
      y = 0,
      w = w,
      h = h,
      children = {
        {
          type = lvgl.LABEL,
          x = 0,
          y = 0,
          font = STDSIZE,
          color = barColor,
          text = smallText,
        },
        {
          type = lvgl.LABEL,
          x = 0,
          y = VALUE_Y,
          font = MIDSIZE,
          color = barColor,
          text = bigText,
        },
      },
    },
  })
end

return TopBarUI
