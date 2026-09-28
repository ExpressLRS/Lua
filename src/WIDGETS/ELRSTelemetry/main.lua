---------------------------------------------------------------------------
-- ELRS Telemetry Widget                                                 --
-- Displays ELRS link telemetry: RSSI, LQ, Range, RF Mode, Power,        --
-- Battery, Current, GPS, and Flight Mode.                               --
--                                                                       --
-- Uses the loadable.lua pattern to minimize memory when not in use.     --
-- Requires /SCRIPTS/ELRS on the SD card for shared CRSF transport.      --
---------------------------------------------------------------------------

local name = "ELRSTelemetry"

-- selene: allow(undefined_variable)
local function create(zone, options)
  if not _crsfSingleton then
    local getCRSF = loadScript("/SCRIPTS/ELRS/crsf.lua")
    ---@diagnostic disable-next-line: need-check-nil
    _crsfSingleton = getCRSF()
  end
  if not _elrsTelemetrySingleton then
    local getTelemetry = loadScript(table.concat({ "/WIDGETS/", name, "/telemetry.lua" }))
    ---@diagnostic disable-next-line: need-check-nil
    _elrsTelemetrySingleton = getTelemetry(_crsfSingleton)
  end
  -- Singleton survives model changes; reset on a new model, not on every create()
  local modelId = model.getInfo().name
  if _elrsTelemetrySingleton.modelId ~= modelId then
    _elrsTelemetrySingleton.modelId = modelId
    _elrsTelemetrySingleton.resetModel()
  end
  _elrsTelemetrySingleton.resetModelMatch()
  local loadable = loadScript(table.concat({ "/WIDGETS/", name, "/loadable.lua" }))
  ---@diagnostic disable-next-line: need-check-nil
  return loadable(zone, options, _elrsTelemetrySingleton)
end

local function refresh(widget, event, touchState)
  widget.refresh(event, touchState)
end

local function background(widget)
  widget.background()
end

local function update(widget, options)
  widget.update(options)
end

return {
  name = "ExpressLRS Telemetry",
  create = create,
  refresh = refresh,
  background = background,
  update = update,
  options = {
    { "Transparency", VALUE, 2, 0, 5 },
  },
  useLvgl = true,
}
