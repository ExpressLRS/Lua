---------------------------------------------------------------------------
-- ELRS Telemetry Widget - Shared Top Bar UI                             --
-- Loaded via loadScript() from each per-screen ui/ file with            --
-- ({ Display }); returns the TopBarUI table.                            --
--                                                                       --
-- Same geometry as the stock Value widget in a top-bar zone, so it      --
-- lines up with one placed beside it: a STD row at the origin and a     --
-- MIDSIZE row 14 px (scaled) below, both left aligned, no background.   --
-- The small row carries the RSSI where a stock Value carries its source --
-- name; the big row is the LQ.                                          --
---------------------------------------------------------------------------

local ctx = ...
local Display = ctx.Display

local TopBarUI = {}

local VALUE_Y = math.floor(14 * lvgl.LCD_SCALE + 0.5)

--- The top bar sits on the dark header, so it needs PRIMARY2 where
--- Display.heroColor uses PRIMARY1. Disconnected takes the disabled grey a
--- stock Value gives stale telemetry.
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

--- Top bar: RSSI over LQ, in the stock Value widget's label-over-value layout.
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
