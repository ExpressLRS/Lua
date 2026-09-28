---- #########################################################################
---- # Bind tool UI for colour LVGL radios                                   #
---- #########################################################################

local deps = ...

local App = deps.App
local crsf = deps.crsf
local msp = deps.msp

local Dialogs = loadScript("/SCRIPTS/ELRS/ui/lvgl/dialogs.lua")()

local UI = {
  -- App.rev the page was built for
  builtRev = nil,
  dialogBuilt = false,
}

local function exitTool()
  App.shouldExit = true
end

local function isSetEnabled()
  return App.isTargetReachableOrBoth() and App.phrase ~= ""
end

local function isRxSelected()
  return App.target == App.TARGET_RX
end

local function isRxSelectedConnected()
  return App.target == App.TARGET_RX and crsf.hasTelemetry
end

local function isRxSelectedDisconnected()
  return App.target == App.TARGET_RX and not crsf.hasTelemetry
end

local function buildUi()
  lvgl.clear()

  local pg = lvgl.page({
    title = "ExpressLRS Bind Tool",
    subtitle = App.uidLine,
    back = exitTool,
  })

  local tbox = pg:box({
    w = lvgl.PERCENT_SIZE + 100,
    flexFlow = lvgl.FLOW_COLUMN,
  })

  tbox:setting({
    w = lvgl.PERCENT_SIZE + 100,
    title = "Bind phrase",
    children = {
      {
        type = lvgl.BOX,
        x = 120 * lvgl.LCD_SCALE,
        flexFlow = lvgl.FLOW_ROW,
        flexPad = lvgl.PAD_MEDIUM,
        children = {
          {
            type = lvgl.TEXT_EDIT,
            w = 250 * lvgl.LCD_SCALE,
            value = App.phrase,
            -- Must fit one un-chunked MSP_WRITE frame
            length = msp.CONST.PHRASE_MAX,
            set = function(v)
              App.phrase = v
            end,
            active = App.isTargetReachableOrBoth,
          },
          {
            type = lvgl.BUTTON,
            text = "Set",
            press = App.sendSet,
            active = isSetEnabled,
          },
        },
      },
    },
  })

  tbox:setting({
    w = lvgl.PERCENT_SIZE + 100,
    title = "Target",
    children = {
      {
        type = lvgl.BOX,
        x = 120 * lvgl.LCD_SCALE,
        flexFlow = lvgl.FLOW_ROW,
        flexPad = lvgl.PAD_MEDIUM,
        children = {
          {
            type = lvgl.CHOICE,
            title = "Select Target",
            values = { "Transmitter", "Receiver", "Both" },
            get = function()
              return App.target
            end,
            set = function(n)
              App.target = n
            end,
          },
          {
            type = lvgl.BUTTON,
            text = "Request UID",
            press = App.startUidRequest,
            active = App.isTargetReachable,
          },
          {
            type = lvgl.BUTTON,
            text = "Unbind",
            press = App.sendUnbind,
            visible = isRxSelected,
            active = isRxSelectedConnected,
          },
        },
      },
    },
  })

  pg:box({
    w = lvgl.PERCENT_SIZE + 100,
    y = 2 * lvgl.UI_ELEMENT_HEIGHT + 4 * lvgl.PAD_MEDIUM,
    flexFlow = lvgl.FLOW_ROW,
    flexPad = lvgl.PAD_MEDIUM,
    align = LEFT,
    visible = isRxSelectedDisconnected,
    children = {
      {
        type = lvgl.LABEL,
        w = 4 + lvgl.LCD_SCALE * (120 + 250),
        text = " No receiver connected.\n Use Bind to set bindphrase if RX in bind mode",
      },
      {
        type = lvgl.BUTTON,
        text = "Bind",
        press = App.sendBind,
      },
    },
  })

  local histSection = pg:box({
    w = lvgl.PERCENT_SIZE + 100,
    y = 2 * lvgl.UI_ELEMENT_HEIGHT + 4 * lvgl.PAD_MEDIUM,
    flexFlow = lvgl.FLOW_COLUMN,
    flexPad = 0,
    visible = function()
      return App.history.items[1] ~= nil and App.isTargetReachableOrBoth()
    end,
  })
  histSection:label({
    text = "Bind Phrase History",
    w = lvgl.PERCENT_SIZE + 100,
    align = CENTER,
  })
  for i = 1, App.history.MAX do
    local row = histSection:box({
      w = lvgl.PERCENT_SIZE + 100,
      flexFlow = lvgl.FLOW_ROW,
      flexPad = lvgl.PAD_SMALL,
      visible = function()
        return App.history.items[i] ~= nil
      end,
    })
    row:button({
      w = lvgl.PERCENT_SIZE + 80,
      text = function()
        return App.history.items[i] or ""
      end,
      press = function()
        App.useHistory(i)
      end,
    })
    row:button({
      text = "X",
      textColor = COLOR_THEME_WARNING,
      press = function()
        App.removeHistory(i)
      end,
    })
  end
end

function UI.init() end

function UI.preCheck(_event)
  if deps.versionOk and App.checkCrsfModule() then
    return nil
  end
  if not UI.dialogBuilt then
    if deps.versionOk then
      Dialogs.showNoModule(exitTool)
    else
      Dialogs.showVersionRequired(deps.requiredVersions, exitTool)
    end
    UI.dialogBuilt = true
  end
  if App.shouldExit then
    return 2
  end
  return 0
end

-- TEXT_EDIT's value is a build-time snapshot; rebuild on App.rev
function UI.render(_event, _touchState)
  if UI.builtRev ~= App.rev then
    buildUi()
    UI.builtRev = App.rev
  end
end

return UI
