---------------------------------------------------------------------------
-- Deferred Callback Timer                                               --
-- One pending callback; a new one replaces it. poll() once per run().   --
-- Each loadScript() gives a private slot.                               --
---------------------------------------------------------------------------

local Defer = {
  _cb = nil,
}

--- Calls fn(ctx) after ticks (10 ms units).
function Defer.setTimeout(ticks, fn, ctx)
  Defer._cb = {
    start = getTime(),
    ticks = ticks,
    fn = fn,
    ctx = ctx,
  }
end

function Defer.clear()
  Defer._cb = nil
end

function Defer.poll()
  local cb = Defer._cb
  if cb == nil then
    return
  end
  if getTime() - cb.start < cb.ticks then
    return
  end
  Defer._cb = nil -- cb may schedule a successor
  cb.fn(cb.ctx)
end

return Defer
