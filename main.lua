-- main.lua — app bootstrap (perf HUD removed)
utf8 = require("utf8")

flux       = require("libs.flux")
moonshine  = require("libs.moonshine_register")

local StarMap   = require("star_map")
local UI        = require("ui.ui")
local Startup   = require("startup")
local Composer  = require("ui.composer")

-- Autobatch (optional)
local AB_OK, Autobatch = pcall(require, "autobatch")

-- App state
local appState = "startup" -- "startup" | "main"

local function composerOpen()
  return Composer and Composer.isOpen and Composer.isOpen()
end

function love.load()
  love.window.setTitle("Constellation Memories")
  love.graphics.setBackgroundColor(0.05, 0.05, 0.10)

  -- Autobatch init (if available)
  if AB_OK and Autobatch then
    if Autobatch.install then
      pcall(Autobatch.install)
    elseif Autobatch.init then
      pcall(Autobatch.init)
    end
    if Autobatch.enable then
      pcall(Autobatch.enable, true)
    end
  end

  StarMap.load()
  UI.load()

  Startup.load()
  Startup.setOnComplete(function()
    appState = "main"
  end)
end

function love.update(dt)
  flux.update(dt)

  if appState == "startup" then
    Startup.update(dt)
  elseif appState == "main" then
    StarMap.update(dt)
    UI.update(dt)
  end
end

function love.mousepressed(x, y, button)
  if appState ~= "main" then return end
  local handled = UI.mousepressed(x, y, button)
  if handled or composerOpen() then return end
  if StarMap.mousepressed then StarMap.mousepressed(x, y, button) end
end

function love.mousereleased(x, y, button)
  if appState ~= "main" then return end
  if UI.mousereleased then UI.mousereleased(x, y, button) end
  if composerOpen() then return end
  if StarMap.mousereleased then StarMap.mousereleased(x, y, button) end
end

function love.mousemoved(x, y, dx, dy)
  if appState ~= "main" then return end
  if UI.mousemoved then UI.mousemoved(x, y, dx, dy) end
  if composerOpen() then return end
  if StarMap.mousemoved then StarMap.mousemoved(x, y, dx, dy) end
end

function love.keypressed(key, scancode, isrepeat)
  if appState == "startup" then
    if Startup.keypressed then Startup.keypressed(key) end
    return
  end

  -- Factory reset (Ctrl+F5)
  if key == "f5" and love.keyboard.isDown("lctrl") then
    love.filesystem.remove("user_memories.lua")
    love.filesystem.remove("user_links.lua")
    StarMap.load()
    return
  end

  -- Composer eats keys while open
  if composerOpen() then
    if Composer.keypressed then Composer.keypressed(key, scancode, isrepeat) end
    return
  end

  if UI.keypressed then UI.keypressed(key) end
  if StarMap.keypressed then StarMap.keypressed(key) end
end

function love.keyreleased(key)
  if appState ~= "main" then return end
  if UI.keyreleased then UI.keyreleased(key) end
  if composerOpen() then return end
  if StarMap.keyreleased then StarMap.keyreleased(key) end
end

function love.textinput(t)
  if appState ~= "main" then return end
  if composerOpen() then
    if Composer.textinput then Composer.textinput(t) end
    return
  end
  if UI.textinput then UI.textinput(t) end
  if StarMap.textinput then StarMap.textinput(t) end
end

function love.wheelmoved(dx, dy)
  if appState ~= "main" then return end
  if UI.wheelmoved then UI.wheelmoved(dx, dy) end
  if composerOpen() then return end
  if StarMap.wheelmoved then StarMap.wheelmoved(dx, dy) end
end

function love.draw()
  if appState == "startup" then
    Startup.draw()
    return
  end

  -- Some Autobatch builds like begin()/end() around a frame
  local didBegin = false
  if AB_OK and Autobatch and Autobatch.begin then
    didBegin = pcall(Autobatch.begin)
  end

  StarMap.draw()
  UI.draw()

  if didBegin and Autobatch and Autobatch.end_ then
    pcall(Autobatch.end_)
  elseif didBegin and Autobatch and Autobatch["end"] then
    pcall(Autobatch["end"])
  end
end

function love.filedropped(file)
  local ok, comp = pcall(require, "ui.composer")
  if ok and comp and comp.filedropped then comp.filedropped(file) end
end
