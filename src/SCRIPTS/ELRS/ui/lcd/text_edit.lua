---------------------------------------------------------------------------
-- B&W Text Editor                                                       --
-- Port of the firmware's editName() (stdlcd/draw_functions.cpp).        --
-- Edits apply live; EXIT commits too. Trailing spaces are stripped.     --
---------------------------------------------------------------------------

local TextEdit = {}
TextEdit.__index = TextEdit

-- Firmware nameChars; digits and ',' let a raw UID be typed
local CHARS = " abcdefghijklmnopqrstuvwxyz0123456789_-,."

local function charIdx(c)
  local b = string.byte(c)
  if b >= 65 and b <= 90 then
    c = string.char(b + 32)
  end
  local idx = string.find(CHARS, c, 1, true)
  return idx or 1
end

local function isUpper(c)
  local b = string.byte(c)
  return b ~= nil and b >= 65 and b <= 90
end

local function isLower(c)
  local b = string.byte(c)
  return b ~= nil and b >= 97 and b <= 122
end

--- visible: chars that fit the row
function TextEdit.new(maxLen, visible)
  return setmetatable({
    maxLen = maxLen,
    visible = visible,
    value = "",
    editing = nil,
    cur = 1,
  }, TextEdit)
end

function TextEdit:start()
  self.editing = true
  self.cur = 1
  self.long = nil
end

function TextEdit:_padded()
  local v = self.value
  while #v < self.cur - 1 do
    v = v .. " "
  end
  return v
end

function TextEdit:_setChar(c)
  local v = self:_padded()
  self.value = string.sub(v, 1, self.cur - 1) .. c .. string.sub(v, self.cur + 1)
end

function TextEdit:_toggleCase()
  local c = self:_charAt(self.cur)
  if isUpper(c) then
    self:_setChar(string.char(string.byte(c) + 32))
  elseif isLower(c) then
    self:_setChar(string.char(string.byte(c) - 32))
  end
end

function TextEdit:_charAt(pos)
  local c = string.sub(self.value, pos, pos)
  if c == "" then
    return " "
  end
  return c
end

function TextEdit:_commit()
  self.editing = nil
  local v = self.value
  local last = #v
  while last > 0 and string.byte(v, last) == 32 do
    last = last - 1
  end
  self.value = string.sub(v, 1, last)
end

--- true when the edit committed
function TextEdit:handleEvent(event)
  local c = self:_charAt(self.cur)

  -- Long ENTER is followed by a break Lua cannot kill; act on the break
  local long = self.long
  if event == EVT_VIRTUAL_ENTER_LONG then
    self.long = true
    return
  elseif event == EVT_VIRTUAL_ENTER then
    self.long = nil
  end

  if
    event == EVT_VIRTUAL_EXIT
    or (event == EVT_VIRTUAL_ENTER and long and c == " ")
    or (event == EVT_VIRTUAL_ENTER and not long and self.cur >= self.maxLen)
  then
    self:_commit()
    return true
  end

  if event == EVT_VIRTUAL_ENTER and long then
    self:_toggleCase()
  elseif event == EVT_VIRTUAL_NEXT or event == EVT_VIRTUAL_PREV then
    local idx = charIdx(c)
    if event == EVT_VIRTUAL_NEXT then
      idx = math.min(idx + 1, #CHARS)
    else
      idx = math.max(idx - 1, 1)
    end
    local nc = string.sub(CHARS, idx, idx)
    if isUpper(c) and isLower(nc) then
      nc = string.char(string.byte(nc) - 32)
    end
    self:_setChar(nc)
  elseif event == EVT_VIRTUAL_ENTER then
    self.cur = self.cur + 1
  elseif event == EVT_VIRTUAL_NEXT_PAGE then
    if self.cur <= #self.value and self.cur < self.maxLen then
      self.cur = self.cur + 1
    end
  elseif event == EVT_VIRTUAL_PREV_PAGE then
    self.cur = math.max(self.cur - 1, 1)
  end
end

function TextEdit:draw(x, y, attr)
  if not self.editing then
    local shown = self.value
    if shown == "" then
      shown = "---"
    elseif self.visible and #shown > self.visible then
      shown = string.sub(shown, 1, self.visible)
    end
    lcd.drawText(x, y, shown, attr)
    return
  end

  -- Keep the cursor on screen
  local first = 1
  if self.visible and self.cur > self.visible then
    first = self.cur - self.visible + 1
  end
  local v = self:_padded()
  local prefix = string.sub(v, first, self.cur - 1)
  local suffix = ""
  if self.visible then
    suffix = string.sub(v, self.cur + 1, first + self.visible - 1)
  else
    suffix = string.sub(v, self.cur + 1)
  end

  lcd.drawText(x, y, prefix)
  lcd.drawText(lcd.getLastPos(), y, self:_charAt(self.cur), INVERS)
  if suffix ~= "" then
    lcd.drawText(lcd.getLastPos(), y, suffix)
  end
end

return TextEdit
