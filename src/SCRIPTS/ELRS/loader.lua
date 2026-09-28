---------------------------------------------------------------------------
-- GC-Guarded Script Loader                                              --
-- Collects before each load: without it first-run compiles run B&W      --
-- radios out of memory.                                                 --
---------------------------------------------------------------------------

local function loader(path, ...)
  collectgarbage("collect")
  local chunk = loadScript(path)
  if chunk == nil then
    error(path) -- names the file on the error screen
  end
  return chunk(...)
end

return loader
