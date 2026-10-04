---------------------------------------------------------------------------
-- VTX Administrator Widget - Shared Top Bar UI                          --
-- Used by all screen-specific UI files for the top bar layout.          --
---------------------------------------------------------------------------

local ctx = ...
local VTXDisplay = ctx.VTXDisplay

local TopBarUI = {}

local VALUE_Y = math.floor(14 * lvgl.LCD_SCALE + 0.5) -- stock Value widget offset

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
