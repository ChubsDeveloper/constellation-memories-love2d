-- ui.lua — minimalist orchestrator for Viewer + Composer + StarMap link HUD
local UI = {}

-- Modules (rename if your files live under a namespace folder)
local Common   = require("ui.common")
local Viewer   = require("ui.viewer")
local Composer = require("ui.composer")

-- Optional: StarMap for link HUD state
local StarMap
local function tryRequireStarMap()
  if StarMap ~= nil then return StarMap end
  local ok, mod = pcall(require, "star_map")
  StarMap = (ok and type(mod) == "table") and mod or false
  return StarMap or nil
end

local function getLinkState()
  local sm = tryRequireStarMap()
  if not sm then return false, nil end
  if type(sm.isLinkMode) == "function" then
    local on, phase = sm.isLinkMode()
    return not not on, phase
  elseif type(sm.getLinkMode) == "function" then
    local on, phase = sm.getLinkMode()
    return not not on, phase
  elseif sm._isLinkMode ~= nil then
    return not not sm._isLinkMode, sm._linkPhase
  end
  return false, nil
end

-- —————————————————————————————————————————————————————
-- Lifecycle
-- —————————————————————————————————————————————————————
function UI.load()
  if Common and Common.load then Common.load() end
  if Viewer and Viewer.load then Viewer.load() end
  if Composer and Composer.load then Composer.load() end
end

-- Open viewer at a star/memory (just forwards to Viewer)
function UI.showMemory(data, sx, sy)
  if Viewer and Viewer.showMemory then Viewer.showMemory(data, sx, sy) end
end

-- Open composer create flow at a position
function UI.openComposerAt(x, y, seedStyle)
  if not Composer or not Composer.openAt then return end
  Composer.openAt(x, y, seedStyle or (Viewer and Viewer.getLastStyle and Viewer.getLastStyle() or nil), {
    onSave = function(mem)
      -- let Viewer immediately reflect the new/edited memory
      if Viewer and Viewer.showMemory then
        Viewer.showMemory(mem, mem.x or x, mem.y or y)
      end
    end,
    onCancel = function() end,
  })
end

function UI.startCreateAt(x, y, seedStyle)
  return UI.openComposerAt(x, y, seedStyle)
end

-- —————————————————————————————————————————————————————
-- Update / Draw
-- —————————————————————————————————————————————————————
function UI.update(dt)
  if Viewer and Viewer.update then Viewer.update(dt) end
  if Composer and Composer.update then Composer.update(dt) end
end

local function drawLinkHUD()
  local on, phase = getLinkState()
  if not on or not Common or not Common.theme then return end
  local THEME = Common.theme
  local font  = Common.fontBody or love.graphics.getFont()
  local pad = 10
  local msg = (phase == "second")
      and "LINK MODE — pick second star  (Esc to cancel)"
      or  "LINK MODE — pick first star  (Esc to cancel)"
  love.graphics.setFont(font)
  local w = font:getWidth(msg) + pad * 2
  local h = font:getHeight() + pad * 1.2
  local x, y = 12, 10
  love.graphics.setColor((THEME.hudPillBg or {0,0,0,0.9}))
  love.graphics.rectangle("fill", x, y, w, h, 10, 10)
  local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 6)
  local stroke = THEME.hudPillStroke or {1,1,1,0.6}
  love.graphics.setColor(stroke[1], stroke[2], stroke[3], stroke[4] * (0.8 + 0.2 * pulse))
  love.graphics.setLineWidth(1.2)
  love.graphics.rectangle("line", x, y, w, h, 10, 10)
  love.graphics.setColor((THEME.hudPillText or {1,1,1,0.95}))
  love.graphics.print(msg, x + pad, y + (h - font:getHeight()) / 2)
end

function UI.draw()
  if Viewer and Viewer.draw then Viewer.draw() end
  if Composer and Composer.draw then Composer.draw() end
  drawLinkHUD()
  if Common and Common.drawHelpChip then Common.drawHelpChip() end
end

-- —————————————————————————————————————————————————————
-- Input dispatch
-- —————————————————————————————————————————————————————
local function composerOpen()
  return Composer and Composer.isOpen and Composer.isOpen()
end

function UI.mousepressed(x, y, button)
  -- If composer is open, let it handle the click.
  if composerOpen() then
    if Composer and Composer.mousepressed then
      -- If composer says it handled the event, stop here.
      local handled = Composer.mousepressed(x, y, button)
      if handled then return true end
      -- Even if it returns nil/false, we still don't want background to open stuff.
      return true
    end
    return true
  end

  -- Let the viewer handle clicks first; it may return:
  --  - true (consumed)
  --  - a table event (e.g. { action="edit", memory=... })
  --  - nil/false (not handled)
  local ev
  if Viewer and Viewer.mousepressed then
    ev = Viewer.mousepressed(x, y, button)
    if ev == true then
      return true
    end
  end

  -- Handle structured viewer events
  if type(ev) == "table" then
    if ev.action == "edit" and ev.memory then
      if Composer and Composer.openForEdit then
        Composer.openForEdit(ev.memory, ev.sx or x, ev.sy or y, {
          onSave = function(mem)
            if Viewer and Viewer.showMemory then
              Viewer.showMemory(mem, mem.x or ev.sx or x, mem.y or ev.sy or y)
            end
          end,
          onCancel = function() end,
        })
      end
      return true
    elseif ev.action == "delete" and ev.id then
      local sm = tryRequireStarMap()
      if sm and sm.deleteMemory then sm.deleteMemory(ev.id) end
      if Viewer and Viewer.hide then Viewer.hide() end
      return true
    end
  end

  -- Right-click = create *only if* nothing else consumed the click.
  if button == 2 and Composer and Composer.openAt then
    local seed = Viewer and Viewer.getLastStyle and Viewer.getLastStyle() or nil
    Composer.openAt(x, y, seed, {
      onSave = function(mem)
        if Viewer and Viewer.showMemory then
          Viewer.showMemory(mem, mem.x or x, mem.y or y)
        end
      end,
      onCancel = function() end,
    })
    return true
  end

  return false
end

function UI.mousereleased(x, y, button)
  if composerOpen() then
    if Composer.mousereleased then Composer.mousereleased(x, y, button) end
  elseif Viewer and Viewer.mousereleased then
    Viewer.mousereleased(x, y, button)
  end
end

function UI.mousemoved(x, y, dx, dy)
  if composerOpen() then
    if Composer.mousemoved then Composer.mousemoved(x, y, dx, dy) end
  elseif Viewer and Viewer.mousemoved then
    Viewer.mousemoved(x, y, dx, dy)
  end
end

function UI.wheelmoved(dx, dy)
  if composerOpen() then
    if Composer.wheelmoved then Composer.wheelmoved(dx, dy) end
  elseif Viewer and Viewer.wheelmoved then
    Viewer.wheelmoved(dx, dy)
  end
end

function UI.keypressed(key)
  if composerOpen() then
    if key == "escape" and Composer.cancel then
      Composer.cancel() -- optional helper to close composer
      return
    end
    if Composer.keypressed then Composer.keypressed(key) end
  else
    if key == "escape" and Viewer and Viewer.hide then
      Viewer.hide() -- optional helper to dismiss card
      return
    end
    if Viewer and Viewer.keypressed then Viewer.keypressed(key) end
  end
end

function UI.keyreleased(key)
  if composerOpen() then
    if Composer.keyreleased then Composer.keyreleased(key) end
  elseif Viewer and Viewer.keyreleased then
    Viewer.keyreleased(key)
  end
end

function UI.textinput(t)
  if composerOpen() then
    if Composer.textinput then Composer.textinput(t) end
  elseif Viewer and Viewer.textinput then
    Viewer.textinput(t)
  end
end

return UI
