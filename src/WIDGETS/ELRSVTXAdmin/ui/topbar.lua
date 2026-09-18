---------------------------------------------------------------------------
-- VTX Administrator Widget - Shared Top Bar UI                          --
-- Used by all screen-specific UI files for the top bar layout.          --
---------------------------------------------------------------------------

local ctx = ...
local VTXDisplay = ctx.VTXDisplay

local TopBarUI = {}

-- Same geometry as the stock Value widget in a top-bar zone: STD label at the
-- origin, MIDSIZE value 14 px (scaled) below it, both left aligned.
local VALUE_Y = math.floor(14 * lvgl.LCD_SCALE + 0.5)

--- Top bar: label over value, matching EdgeTX's stock Value widget.
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
          color = COLOR_THEME_PRIMARY2,
          text = "VTX",
        },
        {
          type = lvgl.LABEL,
          x = 0,
          y = VALUE_Y,
          font = MIDSIZE,
          color = COLOR_THEME_PRIMARY2,
          text = function()
            if VTXDisplay.showStatus() then
              return "--"
            end
            return VTXDisplay.bandChannel()
          end,
        },
      },
    },
  })
end

return TopBarUI
