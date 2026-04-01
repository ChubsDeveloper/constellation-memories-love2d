-- ui/init.lua
local Common  = require("ui.common")
local Viewer  = require("ui.viewer")
local Composer= require("ui.composer")

local UI = {}

-- public load
function UI.load()
  Common.load()
end

-- viewer API
function UI.showMemory(data, sx, sy) Viewer.showMemory(data, sx, sy) end

-- composer API
function UI.openComposerAt(x, y, seedStyle) Composer.openAt(x, y, seedStyle) end
function UI.startCreateAt(x, y, seedStyle) return UI.openComposerAt(x, y, seedStyle) end

-- update/draw
function UI.update(dt)
  Viewer.update(dt)
  Composer.update(dt)
end

function UI.draw()
  Viewer.draw()
  Composer.draw()
end

-- input plumbing
function UI.mousepressed(x,y,button)
  local act, mem, sx, sy = Viewer.mousepressed(x,y,button)
  if act=="edit" and mem then
    Composer.editAt(sx, sy, mem)
    return
  end
  Composer.mousepressed(x,y,button)
end

function UI.mousereleased(x,y,button) end
function UI.mousemoved(x,y,dx,dy) end

function UI.keypressed(key)
  Viewer.keypressed(key)
end
function UI.keyreleased(key) end
function UI.textinput(t)
  -- (text editing omitted for brevity; can be wired similarly if you want inline editing now)
end
function UI.wheelmoved(dx,dy) end

return UI
