---- #########################################################################
---- # BW LCD UI: Rendering, input handling, cursor management            #
---- #########################################################################

local deps = ...

local App = deps.App
local Navigation = deps.Navigation
local session = deps.session
local crsf = deps.crsf
local VERSION = deps.VERSION

local Dialogs = loadScript("/SCRIPTS/ELRS/ui/lcd/dialogs.lua")()

-- 10 ms ticks; also paces the idle repaint
local WARN_FLASH_PERIOD = 100

local UI = {
  lineIndex = 1,
  pageOffset = 0,
  edit = nil,

  visibleFields = nil,

  -- 128x64; UI.init adjusts for 212 wide / 96 tall
  COL1 = 0,
  COL2 = 70,
  maxLineIndex = 6,
  textSize = 8,
  textYoffset = 3,

  forceRedraw = true,
  folderWasReady = false,
  wasLoading = false,

  titleShowWarn = nil,
  titleShowWarnTimeout = 0,
  titleWarnFlags = nil,

  warningDismissedAt = nil,

  commandRunningIndicator = 1,
}

function UI.init()
  if LCD_W == 212 then
    UI.COL2 = 110
  end
  if LCD_H == 96 then
    UI.maxLineIndex = 9
  end
end

function UI.preCheck(event)
  if not deps.versionOk then
    Dialogs.drawVersionRequired(deps.requiredVersions)
    if event == EVT_VIRTUAL_EXIT then
      App.shouldExit = true
      return 2
    end
    return 0
  end
  if not App.checkCrsfModule() then
    Dialogs.drawNoModule()
    return 0
  end
  return nil
end

-- Keeps the cursor; onDeviceLoaded() resets it
function UI.invalidate()
  UI.forceRedraw = true
  UI.visibleFields = nil
end

function UI.onDeviceLoaded()
  UI.lineIndex = 1
  UI.pageOffset = 0
  UI.invalidate()
end

function UI.onNewDevice()
  UI.invalidate()
end

function UI.handleUnsupported()
  Dialogs.draw("Unsupported", {
    "ELRS 1.x firmware",
    "detected. Update to",
    "3.5.4 or later.",
  })
end

function UI.render(event, _touchState)
  -- Flags change restarts the flash on its visible half
  local time = getTime()
  local flags = session.status.flags
  if flags ~= UI.titleWarnFlags then
    UI.titleWarnFlags = flags
    UI.titleShowWarn = (flags > crsf.CONST.ELRS_FLAGS_STATUS_MASK) or nil
    UI.titleShowWarnTimeout = time + WARN_FLASH_PERIOD
    UI.forceRedraw = true
  elseif time > UI.titleShowWarnTimeout then
    UI.titleShowWarn = (flags > crsf.CONST.ELRS_FLAGS_STATUS_MASK and not UI.titleShowWarn) or nil
    UI.titleShowWarnTimeout = time + WARN_FLASH_PERIOD
    UI.forceRedraw = true
  end

  if UI.warningDismissedAt and time - UI.warningDismissedAt > 6000 then -- re-show 60 s after dismiss
    UI.warningDismissedAt = nil
  end

  if session.status.modelMismatch and not UI.warningDismissedAt then
    if event == EVT_VIRTUAL_ENTER then
      UI.warningDismissedAt = getTime()
      UI.forceRedraw = true
      return
    elseif event == EVT_VIRTUAL_EXIT then
      App.shouldExit = true
      return
    end
    Dialogs.draw("Model Mismatch", {
      "RX connected but",
      "Model ID doesn't match.",
      "Toggle Model Match",
      "to re-sync",
    }, { left = "[OK]", right = "[RTN] Change model" })
    return
  end

  -- Redraw once more after the queue empties, or the last response never shows
  local loading = session:isLoading()
  if loading or UI.wasLoading then
    UI.forceRedraw = true
  end
  UI.wasLoading = loading

  if session.command ~= nil then
    UI.drawPopup(event)
  elseif session.commandResult then
    UI.drawResultPopup(event)
  elseif event ~= 0 or UI.forceRedraw or UI.edit then
    UI.drawPage(event)
    UI.forceRedraw = false
  end
end

function UI.openFolder(folderId, folderName)
  App.enterFolder(folderId, folderName, { li = UI.lineIndex, po = UI.pageOffset })
  UI.lineIndex = 1
  UI.pageOffset = 0
  UI.invalidate()
end

function UI.switchDevice(deviceId)
  if App.switchDevice(deviceId, { li = UI.lineIndex, po = UI.pageOffset }) then
    UI.lineIndex = 1
    UI.pageOffset = 0
    UI.invalidate()
  end
end

function UI.handleBack()
  if Navigation.isAtRoot() then
    App.reloadAtRoot()
  else
    local entry = App.goBack()
    if entry then
      UI.lineIndex = entry.li or 1
      UI.pageOffset = entry.po or 0
      if entry.type == Navigation.TYPE_DEVICE and entry.prevDeviceId then
        local prevDevice = session:getDevice(entry.prevDeviceId)
        if prevDevice then
          session:setDevice(prevDevice)
        end
      end
    end
  end
  UI.invalidate()
end

function UI.buildVisibleFields()
  local currentFolder = Navigation.getCurrent()
  local vf = {}

  if currentFolder == Navigation.FOLDER_OTHER_DEVICES then
    for _, device in ipairs(session.devices) do
      if device.id ~= session.deviceId then
        vf[#vf + 1] = { id = device.id, name = device.name, type = App.DEVICE }
      end
    end
  else
    local fields = session:fieldsInFolder(currentFolder)
    for _, field in ipairs(fields) do
      if not field.hidden then
        vf[#vf + 1] = field
      end
    end

    if currentFolder == nil and #session.devices > 1 and not Navigation.hasDeviceEntry() then
      vf[#vf + 1] = { name = "Other Devices", type = App.DEVICE_FOLDER }
    end
  end

  UI.visibleFields = vf
end

function UI.getField(line)
  if not UI.visibleFields then
    UI.buildVisibleFields()
  end
  return UI.visibleFields[line]
end

function UI.getFieldCount()
  if not UI.visibleFields then
    UI.buildVisibleFields()
  end
  return #UI.visibleFields
end

function UI.getSelectableCount()
  return UI.getFieldCount() + 1
end

function UI.isOnBackExit()
  return UI.lineIndex > UI.getFieldCount()
end

function UI.getBackExitLabel()
  if Navigation.isAtRoot() then
    return "-- EXIT (" .. VERSION .. ") --"
  else
    return "---- BACK ----"
  end
end

function UI.incrField(step)
  local field = UI.getField(UI.lineIndex)
  if not field then
    return
  end
  local min, max = 0, 0
  if field.type <= crsf.CONST.FIELD_FLOAT then
    min = field.min or 0
    max = field.max or 0
    step = (field.step or 1) * step
  elseif field.type == crsf.CONST.FIELD_TEXT_SELECTION then
    min = 0
    max = #field.values - 1
  end

  local newval = field.value
  repeat
    newval = newval + step
    if newval < min then
      newval = min
    elseif newval > max then
      newval = max
    end

    if field.values == nil or #field.values[newval + 1] ~= 0 then
      field.value = newval
      return
    end
  until newval == min or newval == max
end

function UI.selectField(step)
  local count = UI.getSelectableCount()
  local fieldCount = UI.getFieldCount()
  local newLineIndex = UI.lineIndex
  repeat
    newLineIndex = newLineIndex + step
    if newLineIndex <= 0 then
      newLineIndex = count
    elseif newLineIndex > count then
      newLineIndex = 1
      UI.pageOffset = 0
    end
    if newLineIndex > fieldCount then
      break
    end
    local field = UI.getField(newLineIndex)
    if field and field.name then
      break
    end
  until newLineIndex == UI.lineIndex
  UI.lineIndex = newLineIndex
  if UI.lineIndex > UI.maxLineIndex + UI.pageOffset then
    UI.pageOffset = UI.lineIndex - UI.maxLineIndex
  elseif UI.lineIndex <= UI.pageOffset then
    UI.pageOffset = UI.lineIndex - 1
  end
end

local function fieldIntDisplay(field, y, attr)
  lcd.drawText(UI.COL2, y, field.value .. (field.unit or ""), attr)
end

local function fieldFloatDisplay(field, y, attr)
  lcd.drawText(UI.COL2, y, string.format(field.fmt, field.value / field.prec) .. (field.unit or ""), attr)
end

local function fieldTextSelDisplay(field, y, attr)
  lcd.drawText(UI.COL2, y, (field.values[field.value + 1] or "ERR") .. (field.unit or ""), attr)
end

local function fieldStringDisplay(field, y, attr)
  lcd.drawText(UI.COL2, y, field.value or "", attr)
end

local function fieldFolderDisplay(field, y, attr)
  lcd.drawText(UI.COL1, y, "> " .. field.name, attr + BOLD)
end

local function fieldCommandDisplay(field, y, attr)
  lcd.drawText(10, y, "[" .. field.name .. "]", attr + BOLD)
end

local displayHandlers = {}
displayHandlers[crsf.CONST.FIELD_UINT8] = fieldIntDisplay
displayHandlers[crsf.CONST.FIELD_INT8] = fieldIntDisplay
displayHandlers[crsf.CONST.FIELD_UINT16] = fieldIntDisplay
displayHandlers[crsf.CONST.FIELD_INT16] = fieldIntDisplay
displayHandlers[crsf.CONST.FIELD_FLOAT] = fieldFloatDisplay
displayHandlers[crsf.CONST.FIELD_TEXT_SELECTION] = fieldTextSelDisplay
displayHandlers[crsf.CONST.FIELD_STRING] = fieldStringDisplay
displayHandlers[crsf.CONST.FIELD_INFO] = fieldStringDisplay
displayHandlers[crsf.CONST.FIELD_FOLDER] = fieldFolderDisplay
displayHandlers[crsf.CONST.FIELD_COMMAND] = fieldCommandDisplay
displayHandlers[App.DEVICE] = fieldCommandDisplay
displayHandlers[App.DEVICE_FOLDER] = fieldFolderDisplay

function UI.drawTitle()
  local barHeight = 9
  local goodBadPkt = ""
  local status = session.status
  if status.receivedPackets then
    local state = status.connected and "C" or "-"
    goodBadPkt = string.format("%u/%u   %s", status.lostPackets, status.receivedPackets, state)
  end

  local loaded, total = session:folderLoadProgress(Navigation.getCurrent())
  if not UI.titleShowWarn then
    lcd.drawText(LCD_W - 1, 1, goodBadPkt, RIGHT)
    lcd.drawLine(LCD_W - 10, 0, LCD_W - 10, barHeight - 1, SOLID, INVERS)
  end

  if loaded and total and total > 0 and loaded < total then
    lcd.drawFilledRectangle(UI.COL2, 0, LCD_W, barHeight, GREY_DEFAULT)
    lcd.drawGauge(0, 0, UI.COL2, barHeight, loaded, total, 0)
  else
    lcd.drawFilledRectangle(0, 0, LCD_W, barHeight, GREY_DEFAULT)
    if UI.titleShowWarn then
      lcd.drawText(UI.COL1, 1, session.status.warning, INVERS)
    else
      lcd.drawText(UI.COL1, 1, session.deviceName or "Searching...", INVERS)
    end
  end
end

function UI.drawWarning()
  lcd.drawText(UI.COL1, UI.textSize * 2, "Error:")
  lcd.drawText(UI.COL1, UI.textSize * 3, session.status.warning)
  lcd.drawText(LCD_W / 2, UI.textSize * 5, "[OK]", BLINK + INVERS + CENTER)
end

function UI.handleEvent(event)
  if event == EVT_VIRTUAL_EXIT then
    if UI.edit then
      UI.edit = nil
      local field = UI.getField(UI.lineIndex)
      if field and field.id then
        session:reloadField(field)
      end
    else
      UI.handleBack()
    end
  elseif event == EVT_VIRTUAL_ENTER then
    if session.status.flags > crsf.CONST.ELRS_FLAGS_WARNING_THRESHOLD then
      session:suppressCriticalErrors()
    elseif UI.isOnBackExit() then
      if Navigation.isAtRoot() then
        App.shouldExit = true
      else
        UI.handleBack()
      end
    else
      local field = UI.getField(UI.lineIndex)
      if field and field.name then
        local ft = field.type

        if ft == crsf.CONST.FIELD_FOLDER then
          UI.openFolder(field.id, field.name)
        elseif ft == App.DEVICE_FOLDER then
          UI.openFolder(Navigation.FOLDER_OTHER_DEVICES, "Other Devices")
        elseif ft == App.DEVICE then
          UI.switchDevice(field.id)
        elseif ft == crsf.CONST.FIELD_COMMAND then
          session:execCommand(field)
        elseif not field.disabled and ft <= crsf.CONST.FIELD_TEXT_SELECTION then
          UI.edit = not UI.edit
          if not UI.edit then
            session:writeField(field)
          end
        end
      end
    end
  elseif UI.edit then
    if event == EVT_VIRTUAL_NEXT then
      UI.incrField(1)
    elseif event == EVT_VIRTUAL_PREV then
      UI.incrField(-1)
    end
  else
    if event == EVT_VIRTUAL_NEXT then
      UI.selectField(1)
    elseif event == EVT_VIRTUAL_PREV then
      UI.selectField(-1)
    end
  end
end

function UI.drawPage(event)
  UI.handleEvent(event)

  lcd.clear()
  UI.drawTitle()

  if session.status.flags > crsf.CONST.ELRS_FLAGS_WARNING_THRESHOLD then
    UI.drawWarning()
  else
    local totalCount = UI.getSelectableCount()
    for y = 1, UI.maxLineIndex + 1 do
      local idx = UI.pageOffset + y
      if idx > totalCount then
        break
      end
      local yPos = y * UI.textSize + UI.textYoffset
      local isSelected = (UI.lineIndex == idx)
      local attr = isSelected and ((UI.edit and BLINK or 0) + INVERS) or 0

      if idx > UI.getFieldCount() then
        lcd.drawText(10, yPos, "[" .. UI.getBackExitLabel() .. "]", attr + BOLD)
      else
        local field = UI.getField(idx)
        if field and field.name then
          local ft = field.type
          if ft < crsf.CONST.FIELD_FOLDER or ft == crsf.CONST.FIELD_INFO then
            lcd.drawText(UI.COL1, yPos, field.name, 0)
          end
          local displayFn = displayHandlers[ft]
          if displayFn then
            displayFn(field, yPos, attr)
          end
        end
      end
    end
  end
end

-- Precomputed: no table.concat on BW radios
local SENDING_FRAMES = { "Sending... [|]", "Sending... [/]", "Sending... [-]", "Sending... [\\]" }
-- 200 ms: a healthy link answers first, so nothing flashes
local PENDING_POPUP_DELAY = 20

function UI.drawResultPopup(event)
  if popupConfirmation(session.commandResult.info, "Press [OK] to close", event) then
    session.commandResult = nil
    UI.invalidate()
  end
end

function UI.drawPopup(event)
  local command = session.command
  local status = command.status
  if status == crsf.CONST.CMD_ASKCONFIRM then
    local result = popupConfirmation(command.info or "", "PRESS [OK] to confirm", event)
    if result == "OK" then
      session:confirmCommand()
    elseif result == "CANCEL" then
      session:cancelCommand()
      UI.invalidate() -- nothing else repaints once the popup drops
    end
  elseif status == crsf.CONST.CMD_EXECUTING then
    if not session:isReceivingChunks() then
      UI.commandRunningIndicator = (UI.commandRunningIndicator % 4) + 1
    end
    local result = popupConfirmation(
      (command.info or "") .. " [" .. string.sub("|/-\\", UI.commandRunningIndicator, UI.commandRunningIndicator) .. "]",
      "Press [RTN] to exit",
      event
    )
    if result == "CANCEL" then
      session:cancelCommand()
      UI.invalidate()
    end
  else
    -- Awaiting reply; EXIT cancels, popup tracks until CMD_IDLE
    if event == EVT_VIRTUAL_EXIT then
      session:requestCancelCommand()
    end
    if getTime() - session.commandAt >= PENDING_POPUP_DELAY then
      if not session:isReceivingChunks() then
        UI.commandRunningIndicator = (UI.commandRunningIndicator % 4) + 1
      end
      popupConfirmation(SENDING_FRAMES[UI.commandRunningIndicator], "Press [RTN] to cancel", event)
    end
  end
end

return UI
