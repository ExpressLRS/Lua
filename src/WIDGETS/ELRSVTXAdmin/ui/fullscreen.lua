---------------------------------------------------------------------------
-- Full-Screen Editor                                                    --
-- Loaded via loadScript() from ELRSVTXAdmin/loadable.lua with           --
-- (VTXAdmin, PresetsStorage); returns the FullScreenUI table.           --
-- Built once per entry and never rebuilt, so focus and scroll survive.  --
-- Values refresh through get(); numberEdit re-polls only on 2.12.1+,    --
-- older firmware catches up on the next entry.                          --
---------------------------------------------------------------------------

local VTXAdmin, PresetsStorage = ...

local FullScreenUI = {}

-- ============================================================================
-- Row helpers
-- ============================================================================

local PORTRAIT = LCD_W < LCD_H
local LABEL_PCT = PORTRAIT and 42 or 50

local COLLECTION_VALUES = {}
for i = 1, PresetsStorage.COLLECTION_COUNT do
  COLLECTION_VALUES[i] = table.concat({ "Collection ", i })
end

local function createHintRow(container, text)
  container:rectangle({
    w = lvgl.PERCENT_SIZE + 100,
    thickness = 0,
    children = {
      {
        type = lvgl.LABEL,
        text = text,
        color = COLOR_THEME_DISABLED,
        font = SMLSIZE,
        w = lvgl.PERCENT_SIZE + 100,
      },
    },
  })
end

local function createRow(container, label, hint, visibleFn)
  -- Portrait: hints go under the row
  local hintBelow = hint and PORTRAIT
  if hintBelow then
    container = container:rectangle({
      w = lvgl.PERCENT_SIZE + 100,
      thickness = 0,
      flexFlow = lvgl.FLOW_COLUMN,
      flexPad = 0,
      visible = visibleFn,
    })
    visibleFn = nil
  end

  local row = container:rectangle({
    w = lvgl.PERCENT_SIZE + 100,
    thickness = 0,
    flexFlow = lvgl.FLOW_ROW,
    flexPad = 0,
    visible = visibleFn,
  })

  local labelChildren = {
    { type = lvgl.LABEL, y = lvgl.PAD_SMALL, text = label, color = COLOR_THEME_PRIMARY1 },
  }
  local hintBeside = hint and not hintBelow
  if hintBeside then
    labelChildren[#labelChildren + 1] = {
      type = lvgl.LABEL,
      text = hint,
      color = COLOR_THEME_DISABLED,
      font = SMLSIZE,
      w = lvgl.PERCENT_SIZE + 100,
    }
  end

  row:rectangle({
    w = lvgl.PERCENT_SIZE + LABEL_PCT,
    thickness = 0,
    flexFlow = hintBeside and lvgl.FLOW_COLUMN or nil,
    h = not hintBeside and lvgl.UI_ELEMENT_HEIGHT or nil,
    children = labelChildren,
  })

  local ctrl = row:rectangle({
    w = lvgl.PERCENT_SIZE + (100 - LABEL_PCT),
    thickness = 0,
    flexFlow = lvgl.FLOW_ROW,
    align = LEFT + VCENTER,
  })

  if hintBelow then
    createHintRow(container, hint)
  end

  return ctrl
end

local function createChoiceRow(container, label, values, getFn, setFn, hint)
  local ctrl = createRow(container, label, hint)
  ctrl:choice({
    title = label,
    values = values,
    get = getFn,
    set = setFn,
  })
end

local function createNumberRow(container, label, min, max, getFn, setFn, editedFn, displayFn)
  local ctrl = createRow(container, label)
  ctrl:numberEdit({
    min = min,
    max = max,
    get = getFn,
    set = setFn,
    edited = editedFn,
    display = displayFn,
  })
end

local function createToggleRow(container, label, getFn, setFn, visibleFn, hint)
  local ctrl = createRow(container, label, hint, visibleFn)
  ctrl:toggle({
    get = getFn,
    set = setFn,
  })
end

local function createSourceRow(container, label, getFn, setFn, filter, hint)
  local ctrl = createRow(container, label, hint)
  ctrl:source({
    get = getFn,
    set = setFn,
    filter = filter,
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

-- ============================================================================
-- Full-screen layout
-- ============================================================================

function FullScreenUI.build()
  lvgl.clear()

  local d = VTXAdmin.desired

  local pg = lvgl.page({
    title = "ExpressLRS",
    subtitle = function()
      if VTXAdmin.isActive() then
        return "VTX Administrator"
      end
      return VTXAdmin.statusText
    end,
    back = function()
      lvgl.exitFullScreen()
    end,
  })

  if not VTXAdmin.hasModule() then
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

  createSectionHeader(fields, "VTX Settings")

  createChoiceRow(fields, "Band", { "Off", "A", "B", "E", "F", "R", "L" }, function()
    return d.band + 1
  end, function(idx)
    d.band = idx - 1
    VTXAdmin.writeConfig()
  end)

  createNumberRow(fields, "Channel", 1, 8, function()
    return d.channel
  end, function(v)
    d.channel = v
  end, function(v)
    d.channel = v
    VTXAdmin.writeConfig()
  end)

  createNumberRow(fields, "Power Level", 0, 8, function()
    return d.power
  end, function(v)
    d.power = v
  end, function(v)
    d.power = v
    VTXAdmin.writeConfig()
  end, function(v)
    return v == 0 and "-" or tostring(v)
  end)

  -- ExpressLRS hides pit mode while power is "-"
  createToggleRow(fields, "Pit Mode", function()
    return d.pitmode
  end, function(v)
    d.pitmode = v
    VTXAdmin.writeConfig()
  end, function()
    return d.power > 0
  end)

  local sendWrapper = fields:box({
    w = lvgl.PERCENT_SIZE + 100,
    flexFlow = lvgl.FLOW_COLUMN,
    align = CENTER,
    borderPad = { top = lvgl.PAD_SMALL, bottom = lvgl.PAD_SMALL },
  })
  sendWrapper:button({
    text = function()
      if VTXAdmin.isSending() then
        return "Sending..."
      end
      return "Send VTx"
    end,
    w = lvgl.PERCENT_SIZE + 99,
    press = function()
      VTXAdmin.writeConfig()
      VTXAdmin.pushToVtx()
    end,
    active = function()
      return VTXAdmin.isReady()
    end,
  })

  createSectionHeader(fields, "6POS Quick Change")

  createToggleRow(fields, "Enabled", function()
    return PresetsStorage.enabled and 1 or 0
  end, function(v)
    PresetsStorage.enabled = (v == 1)
    PresetsStorage.save()
  end)

  createSourceRow(fields, "Source", function()
    return PresetsStorage.source
  end, function(v)
    PresetsStorage.source = v or 0
    PresetsStorage.save()
  end, lvgl.SRC_STICK + lvgl.SRC_POT + lvgl.SRC_SWITCH)

  createToggleRow(
    fields,
    "Apply at Startup",
    function()
      return PresetsStorage.applyOnStart and 1 or 0
    end,
    function(v)
      PresetsStorage.applyOnStart = (v == 1)
      PresetsStorage.save()
    end,
    nil,
    "Apply the current 6POS preset to the VTX when the model loads. Leave off if your 6POS resets to position 1 at power-on."
  )

  createToggleRow(fields, "Auto Push to VTX", function()
    return PresetsStorage.autoPushVtx and 1 or 0
  end, function(v)
    PresetsStorage.autoPushVtx = (v == 1)
    PresetsStorage.save()
  end, nil, "Send to the VTX as soon as the 6POS position changes. When off, use the trigger below.")

  createSourceRow(
    fields,
    "Send VTx Trigger",
    function()
      return PresetsStorage.pushSource
    end,
    function(v)
      PresetsStorage.pushSource = v or 0
      PresetsStorage.save()
    end,
    lvgl.SRC_STICK + lvgl.SRC_POT + lvgl.SRC_SWITCH,
    "Assign a switch or button to manually push the current VTX config to the receiver."
  )

  createSectionHeader(fields, "Presets")

  createChoiceRow(fields, "Collection", COLLECTION_VALUES, function()
    return PresetsStorage.collection
  end, function(idx)
    PresetsStorage.selectCollection(idx)
  end, "Assign a Band and Channel to each 6POS switch position. Switching collection swaps all six.")

  local bandValues = { "--", "A", "B", "E", "F", "R", "L" }
  for i = 1, 6 do
    local idx = i
    local ctrl = createRow(fields, table.concat({ "Preset ", idx }))

    ctrl:choice({
      values = bandValues,
      get = function()
        return PresetsStorage.items[idx].band + 1
      end,
      set = function(v)
        PresetsStorage.items[idx].band = v - 1
        PresetsStorage.save()
      end,
    })

    ctrl:numberEdit({
      min = 1,
      max = 8,
      get = function()
        return PresetsStorage.items[idx].channel
      end,
      set = function(v)
        PresetsStorage.items[idx].channel = v
        PresetsStorage.save()
      end,
      visible = function()
        return PresetsStorage.items[idx].band > 0
      end,
    })
  end
end

return FullScreenUI
