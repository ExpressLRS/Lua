---------------------------------------------------------------------------
-- ELRS Telemetry Widget - Full-Screen Page                              --
-- Built on entry only; values refresh via callbacks.                    --
---------------------------------------------------------------------------

local Telemetry, Display = ...

local FullScreenUI = {}

-- Narrower labels on portrait.
local LABEL_PCT = (LCD_W < LCD_H) and 42 or 50

-- "--" while the link is down.
local function whenConnected(fn)
  return function()
    if not Telemetry.isConnected() then
      return "--"
    end
    return fn()
  end
end

local function createDisplayRow(container, label, valueFn, colorFn)
  container:rectangle({
    w = lvgl.PERCENT_SIZE + 100,
    thickness = 0,
    flexFlow = lvgl.FLOW_ROW,
    flexPad = 0,
    children = {
      {
        type = lvgl.LABEL,
        text = label,
        color = COLOR_THEME_PRIMARY1,
        w = lvgl.PERCENT_SIZE + LABEL_PCT,
        y = lvgl.PAD_SMALL,
      },
      {
        type = lvgl.LABEL,
        text = valueFn,
        color = colorFn or COLOR_THEME_SECONDARY1,
        w = lvgl.PERCENT_SIZE + (100 - LABEL_PCT),
        y = lvgl.PAD_SMALL,
      },
    },
  })
end

local function createSectionHeader(container, title)
  container:build({
    {
      type = lvgl.RECTANGLE,
      w = lvgl.PERCENT_SIZE + 100,
      h = lvgl.PAD_SMALL,
      thickness = 0,
    },
    {
      type = lvgl.LABEL,
      font = BOLD,
      color = COLOR_THEME_PRIMARY1,
      text = title,
    },
  })
end

function FullScreenUI.build()
  lvgl.clear()

  local pg = lvgl.page({
    title = "ExpressLRS",
    subtitle = Display.pageSubtitle,
    back = function()
      lvgl.exitFullScreen()
    end,
  })

  -- Rebuilt on re-entry, so checking once is enough.
  if not Telemetry.hasModule() then
    local Dialogs = loadScript("/SCRIPTS/ELRS/ui/lvgl/dialogs.lua")()
    local heading = { type = lvgl.LABEL, text = "No module found. Check Model Setup:", color = COLOR_THEME_PRIMARY1 }
    local rows = Dialogs.noModuleChecklist(COLOR_THEME_DISABLED)
    table.insert(rows, 1, heading)
    pg:rectangle({
      w = lvgl.PERCENT_SIZE + 100,
      thickness = 0,
      flexFlow = lvgl.FLOW_COLUMN,
      flexPad = lvgl.PAD_MEDIUM,
      children = rows,
    })
    return
  end

  local fields = pg:rectangle({
    w = lvgl.PERCENT_SIZE + 100,
    thickness = 0,
    flexFlow = lvgl.FLOW_COLUMN,
  })

  fields:build({
    {
      type = lvgl.LABEL,
      font = BOLD,
      color = COLOR_THEME_WARNING,
      text = "Model Mismatch — RC commands not sent",
      visible = Display.isMismatch,
    },
  })

  createSectionHeader(fields, "Link Status")

  createDisplayRow(fields, "RF Mode", Display.rfModeText)

  createDisplayRow(fields, "Link Quality", Display.lqValueText)

  createDisplayRow(
    fields,
    "RSSI",
    whenConnected(function()
      local rssi1 = Telemetry.link.rssi1
      if rssi1 == nil then
        return "--"
      end
      if Telemetry.hasDiversity() then
        return table.concat({ tostring(rssi1), " / ", tostring(Telemetry.link.rssi2), " dBm" })
      end
      return table.concat({ tostring(rssi1), " dBm" })
    end)
  )

  createDisplayRow(
    fields,
    "SNR",
    whenConnected(function()
      local rsnr = Telemetry.link.rsnr
      if rsnr == nil then
        return "--"
      end
      if not Telemetry.hasSnr() then
        return "n/a" -- FLRC: the sensor is a permanent 0, not a reading
      end
      return table.concat({ tostring(rsnr), " dB" })
    end)
  )

  createDisplayRow(
    fields,
    "Active Antenna",
    whenConnected(function()
      if not Telemetry.hasDiversity() then
        return "N/A"
      end
      -- 1-based on purpose; EdgeTX shows raw ANT 0/1
      if Telemetry.link.ant == 0 then
        return "Ant 1"
      end
      if Telemetry.link.ant == 1 then
        return "Ant 2"
      end
      return "--"
    end)
  )

  createDisplayRow(
    fields,
    "Sensitivity",
    whenConnected(function()
      local sens = Telemetry.link.sens
      if sens == nil then
        return "--"
      end
      return table.concat({ tostring(sens), " dBm @ ", Display.rfModeText() })
    end)
  )

  createDisplayRow(
    fields,
    "Link Margin",
    whenConnected(function()
      local db = Telemetry.marginDb()
      if db == nil then
        return "--"
      end
      return string.format("%+d dB", db)
    end),
    Display.detailColor
  )

  createSectionHeader(fields, "Power")

  createDisplayRow(
    fields,
    "TX Power",
    whenConnected(function()
      local tpwr = Telemetry.link.tpwr
      if tpwr == nil then
        return "--"
      end
      return table.concat({ tostring(tpwr), " mW" })
    end)
  )

  createSectionHeader(fields, "Flight Controller")

  createDisplayRow(fields, "Battery", Display.batteryTextVerbose)

  createDisplayRow(fields, "Current", function()
    local curr = Telemetry.link.curr
    if curr == nil or curr <= 0 then
      return "--"
    end
    return string.format("%.2f A", curr)
  end)

  createDisplayRow(fields, "Flight Mode", function()
    local fm = Telemetry.link.fm
    if fm == nil or fm == 0 then
      return "--"
    end
    return tostring(fm)
  end)

  createSectionHeader(fields, "GPS")

  createDisplayRow(
    fields,
    "Satellites",
    whenConnected(function()
      local sats = Telemetry.link.sats
      if sats == nil then
        return "--"
      end
      return tostring(sats)
    end)
  )

  createDisplayRow(
    fields,
    "Speed",
    whenConnected(function()
      local gspd = Telemetry.link.gspd
      if gspd == nil then
        return "--"
      end
      return string.format("%.1f", gspd)
    end)
  )

  createDisplayRow(
    fields,
    "Altitude",
    whenConnected(function()
      local alt = Telemetry.link.alt
      if alt == nil then
        return "--"
      end
      return tostring(alt)
    end)
  )

  -- Last known position survives link loss.
  createDisplayRow(fields, "Latitude", function()
    if Telemetry.gps == nil then
      return "--"
    end
    return tostring(Telemetry.gps.lat)
  end)

  createDisplayRow(fields, "Longitude", function()
    if Telemetry.gps == nil then
      return "--"
    end
    return tostring(Telemetry.gps.lon)
  end)
end

return FullScreenUI
