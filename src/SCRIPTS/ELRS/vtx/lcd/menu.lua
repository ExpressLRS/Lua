---------------------------------------------------------------------------
-- B&W VTX Admin Menu                                                    --
-- Loaded via loadScript() with (VTXAdmin, PresetsStorage, labels) on    --
-- ENTER, dropped on exit. run(event) returns true when closed.          --
-- Rows are plain data, not closures: memory is tight here.              --
---------------------------------------------------------------------------

local VTXAdmin, PresetsStorage, labels = ...

local NUMBER = 1
local TOGGLE = 2
local SOURCE = 3
local SEND = 4
local FOLDER = 5
local PRESET = 6

local ROW_H = 8
local ROW_Y = 11
local ROW_COUNT = math.floor((LCD_H - ROW_Y) / ROW_H)
local VALUE_X = LCD_W - 1

local MOVE_THRESHOLD = 300 -- under one step of a 6-switch group

local d = VTXAdmin.desired
local PS = PresetsStorage

local BAND_NAMES = { "Off", "A", "B", "E", "F", "R", "L" }
local POWER_NAMES = { "-", "1", "2", "3", "4", "5", "6", "7", "8" }

local quickChangeRows = {
  { kind = TOGGLE, label = "Enabled", key = "enabled" },
  { kind = SOURCE, label = "Source", key = "source", multiPos = true },
  { kind = TOGGLE, label = "Apply at Startup", key = "applyOnStart" },
  { kind = TOGGLE, label = "Auto Push to VTX", key = "autoPushVtx" },
  { kind = SOURCE, label = "Send VTx Trigger", key = "pushSource" },
}

local presetRows = {
  { kind = NUMBER, label = "Collection", key = "collection", min = 1, max = PS.COLLECTION_COUNT },
}
for i = 1, 6 do
  presetRows[i + 1] = { kind = PRESET, label = "Preset " .. i, slot = i }
end

local rootRows = {
  { kind = NUMBER, label = "Band", key = "band", vtx = true, min = 0, max = 6, names = BAND_NAMES },
  { kind = NUMBER, label = "Channel", key = "channel", vtx = true, min = 1, max = 8 },
  { kind = NUMBER, label = "Power Level", key = "power", vtx = true, min = 0, max = 8, names = POWER_NAMES },
  { kind = TOGGLE, label = "Pit Mode", key = "pitmode", vtx = true },
  { kind = SEND },
  { kind = FOLDER, label = "6POS Quick Change", page = { title = "6POS Quick Change", rows = quickChangeRows } },
  { kind = FOLDER, label = "Presets", page = { title = "Presets", rows = presetRows } },
}
local root = { title = "VTX Admin", rows = rootRows }

local page = root
local cursor = 1
local offset = 0
local stack = {}

local edit

local srcIds, srcStart, srcGroup

local function clamp(v, min, max)
  return math.max(min, math.min(max, v))
end

local function read(row)
  if row.vtx then
    return d[row.key]
  end
  local v = PS[row.key]
  if v == true then
    return 1
  elseif v == false then
    return 0
  end
  return v
end

local function write(row, v)
  local key = row.key
  if row.vtx then
    d[key] = v
    VTXAdmin.writeConfig()
  elseif key == "collection" then
    PS.selectCollection(v)
  else
    if row.kind == TOGGLE then
      v = (v == 1)
    end
    PS[key] = v
    PS.save()
  end
end

--- Sticks, pots and physical switches incl. groups; lvgl.source's filter.
local function buildSources()
  srcIds, srcStart, srcGroup = { 0 }, {}, {}
  for id in sources(MIXSRC_FIRST_INPUT, MIXSRC_MIN - 1) do
    local name = (getFieldInfo(id) or {}).name or ""
    if string.sub(name, 1, 5) ~= "input" and string.sub(name, 1, 3) ~= "lua" then
      srcIds[#srcIds + 1] = id
    end
  end
  -- Switches are the only upper-case Lua field names here; groups have none
  for id in sources(MIXSRC_MAX + 1, MIXSRC_CH1 - 1) do
    local info = getFieldInfo(id)
    local head = info and string.sub(info.name, 1, 1) or ""
    if not info or (head ~= "" and head == string.upper(head)) then
      srcIds[#srcIds + 1] = id
      srcGroup[#srcIds] = not info or nil
    end
  end
  for i = 2, #srcIds do
    srcStart[i] = getValue(srcIds[i]) or 0
  end
end

--- Largest move since editing began; a switch turning on beats one turning
--- off, since a group switches both. preferGroup: a moved group wins.
local function movedSource(preferGroup)
  local best, bestScore
  for i = 2, #srcIds do
    local delta = (getValue(srcIds[i]) or 0) - srcStart[i]
    if math.abs(delta) > MOVE_THRESHOLD then
      if preferGroup and srcGroup[i] then
        return i
      end
      local score = math.abs(delta) * 2 + (delta > 0 and 1 or 0)
      if not bestScore or score > bestScore then
        best, bestScore = i, score
      end
    end
  end
  return best
end

local function visibleRows()
  local rows = {}
  for _, row in ipairs(page.rows) do
    -- ExpressLRS hides pit mode while power is "-"
    if row.key ~= "pitmode" or d.power > 0 then
      rows[#rows + 1] = row
    end
  end
  return rows
end

local function enter(row)
  local kind = row.kind
  if not edit then
    if (row.vtx and not VTXAdmin.isActive()) or (kind == SEND and not VTXAdmin.isReady()) then
      return
    end
    if kind == TOGGLE then
      write(row, 1 - read(row))
    elseif kind == SEND then
      VTXAdmin.writeConfig()
      VTXAdmin.pushToVtx()
    elseif kind == FOLDER then
      stack[#stack + 1] = { page, cursor, offset }
      page, cursor, offset = row.page, 1, 0
    elseif kind == PRESET then
      local p = PS.items[row.slot]
      edit = { value = p.band, channel = p.channel, part = 1 }
    elseif kind == SOURCE then
      buildSources()
      edit = { value = 1 }
      for i = 1, #srcIds do
        if srcIds[i] == read(row) then
          edit.value = i
        end
      end
    else
      edit = { value = read(row) }
    end
    return
  end
  if kind == PRESET then
    if edit.part == 1 and edit.value > 0 then
      edit.part = 2
      return
    end
    local p = PS.items[row.slot]
    p.band, p.channel = edit.value, edit.channel
    PS.save()
  elseif kind == SOURCE then
    write(row, srcIds[edit.value])
  else
    write(row, edit.value)
  end
  edit = nil
  srcIds, srcStart, srcGroup = nil, nil, nil
end

local function drawValue(row, y, attr)
  local kind = row.kind
  local editing = edit and attr ~= 0
  local text
  if row.vtx and not VTXAdmin.isActive() then
    text = "--"
  elseif kind == NUMBER then
    local v = editing and edit.value or read(row)
    text = row.names and row.names[v + 1] or tostring(v)
  elseif kind == TOGGLE then
    text = read(row) == 1 and "On" or "Off"
  elseif kind == SOURCE then
    local id = editing and srcIds[edit.value] or read(row)
    if id ~= 0 then
      lcd.drawSource(VALUE_X, y, id, attr + RIGHT)
      return
    end
    text = "---"
  else
    local p = PS.items[row.slot]
    local band, channel = p.band, p.channel
    if editing then
      band, channel = edit.value, edit.channel
    end
    if band > 0 and editing then
      lcd.drawText(VALUE_X, y, tostring(channel), edit.part == 2 and attr + RIGHT or RIGHT)
      lcd.drawText(VALUE_X - 8, y, VTXAdmin.BAND_LETTERS[band], edit.part == 1 and attr + RIGHT or RIGHT)
      return
    end
    text = labels.preset(band, channel)
  end
  lcd.drawText(VALUE_X, y, text, attr + RIGHT)
end

local function run(event)
  local rows = visibleRows()
  local row = rows[cursor]
  if event == EVT_VIRTUAL_EXIT then
    if edit then
      edit = nil
      srcIds, srcStart, srcGroup = nil, nil, nil
    elseif #stack == 0 then
      return true
    else
      local prev = stack[#stack]
      stack[#stack] = nil
      page, cursor, offset = prev[1], prev[2], prev[3]
    end
  elseif event == EVT_VIRTUAL_ENTER then
    enter(row)
  elseif event == EVT_VIRTUAL_NEXT or event == EVT_VIRTUAL_PREV then
    local dir = event == EVT_VIRTUAL_NEXT and 1 or -1
    if not edit then
      cursor = (cursor - 1 + dir) % #rows + 1
    elseif row.kind == SOURCE then
      edit.value = clamp(edit.value + dir, 1, #srcIds)
    elseif row.kind == PRESET and edit.part == 2 then
      edit.channel = clamp(edit.channel + dir, 1, 8)
    elseif row.kind == PRESET then
      edit.value = clamp(edit.value + dir, 0, #VTXAdmin.BAND_LETTERS)
    else
      edit.value = clamp(edit.value + dir, row.min, row.max)
    end
  elseif edit and row.kind == SOURCE then
    edit.value = movedSource(row.multiPos) or edit.value
  end

  rows = visibleRows()
  cursor = clamp(cursor, 1, #rows)
  offset = clamp(offset, cursor - ROW_COUNT, cursor - 1)

  lcd.clear()
  lcd.drawFilledRectangle(0, 0, LCD_W, 9)
  lcd.drawText(1, 1, page.title, INVERS)
  local status = "Off"
  if VTXAdmin.isSending() then
    status = "Sending"
  elseif not VTXAdmin.isActive() then
    status = "Loading"
  elseif VTXAdmin.isTuned() then
    status = labels.preset(VTXAdmin.state.band, VTXAdmin.state.channel)
  end
  lcd.drawText(VALUE_X, 1, status, INVERS + RIGHT)

  for i = 1, math.min(ROW_COUNT, #rows - offset) do
    local r = rows[offset + i]
    local y = ROW_Y + (i - 1) * ROW_H
    local rowAttr, valueAttr = 0, 0
    if offset + i == cursor then
      if edit then
        valueAttr = INVERS + BLINK
      else
        lcd.drawFilledRectangle(0, y - 1, LCD_W, ROW_H)
        rowAttr, valueAttr = INVERS, INVERS
      end
    end
    if r.kind == SEND then
      lcd.drawText(LCD_W / 2, y, VTXAdmin.isSending() and "[Sending...]" or "[Send VTx]", rowAttr + BOLD + CENTER)
    elseif r.kind == FOLDER then
      lcd.drawText(1, y, "> " .. r.label, rowAttr + BOLD)
    else
      lcd.drawText(1, y, r.label, rowAttr)
      drawValue(r, y, valueAttr)
    end
  end
end

return { run = run }
