-- systems/background.lua (spritebatch + culling)
local U = require("core.utils")

local S = {}

-- star data (positions, params)
local bg = {}

-- tiny round dot texture + spritebatch
local dotImg, sb

-- viewport cache
local screenW, screenH = 0, 0
local function refreshViewport()
  screenW, screenH = love.graphics.getWidth(), love.graphics.getHeight()
end

-- create a small round white dot image we can tint/scale
local function ensureDotImage()
  if dotImg then return end
  local sz = 8
  local data = love.image.newImageData(sz, sz)
  local cx, cy = (sz-1)*0.5, (sz-1)*0.5
  local r = (sz-1)*0.5
  data:mapPixel(function(x, y)
    local dx, dy = x - cx, y - cy
    local d2 = dx*dx + dy*dy
    if d2 <= r*r then
      -- soft edge
      local k = 1.0 - math.min(1.0, math.sqrt(d2)/r)
      return 1, 1, 1, k
    else
      return 0, 0, 0, 0
    end
  end)
  dotImg = love.graphics.newImage(data)
  dotImg:setFilter("linear", "linear")
end

local function ensureBatch(minCapacity)
  ensureDotImage()
  if not sb then
    sb = love.graphics.newSpriteBatch(dotImg, minCapacity or 256, "stream")
  else
    if minCapacity and minCapacity > sb:getBufferSize() then
      sb = love.graphics.newSpriteBatch(dotImg, minCapacity, "stream")
    end
  end
end

function S.load(count, CONFIG)
  refreshViewport()
  bg = {}
  for _=1, count do
    local warm = love.math.random() < CONFIG.BG_WARM_BIAS
    local c    = warm and {0.95, 0.90, 0.80} or {1, 1, 1}
    bg[#bg+1] = {
      x = math.floor(U.rrange(0, screenW)),
      y = math.floor(U.rrange(0, screenH)),
      r = U.rrange(CONFIG.BG_RADIUS.min, CONFIG.BG_RADIUS.max),
      a = U.rrange(CONFIG.BG_ALPHA.min,  CONFIG.BG_ALPHA.max),
      tw = U.rrange(CONFIG.BG_TWINKLE_SPEED.min, CONFIG.BG_TWINKLE_SPEED.max),
      off = love.math.random() * math.pi * 2,
      phase = love.math.random() * math.pi * 2,
      fade  = love.math.random(),
      color = c,
    }
  end
  ensureBatch(#bg)
end

function S.update(dt, CONFIG)
  -- if window resized, no need to rebuild stars, but update viewport for culling
  refreshViewport()

  -- twinkle advance
  local fadeSpeed = math.min(1, dt * CONFIG.BG_TWINKLE_FADE_SPEED)
  for i = 1, #bg do
    local s = bg[i]
    s.phase = s.phase + s.tw * dt
    local tgt = 0.5 + 0.5 * math.sin(s.phase + s.off)
    s.fade = s.fade + (tgt - s.fade) * fadeSpeed
  end
end

function S.draw(CONFIG)
  if #bg == 0 then return end
  ensureBatch(#bg)

  sb:clear()

  local amp = math.min(1, math.max(0, CONFIG.BG_TWINKLE_AMPLITUDE))
  local margin = 8            -- small pad for culling
  local baseScale = 1 / (dotImg and dotImg:getWidth() or 8)  -- convert radius to image scale

  -- build spritebatch this frame with current alpha per star
  for i = 1, #bg do
    local s = bg[i]

    -- quick cull off-screen
    if s.x >= -margin and s.x <= screenW + margin and s.y >= -margin and s.y <= screenH + margin then
      local mod = (1 - amp) + amp * s.fade
      local a   = s.a * math.max(0, mod)
      if a > 0.01 then
        -- per-sprite color (tinted by star color and current alpha)
        sb:setColor(s.color[1], s.color[2], s.color[3], a)

        -- scale radius: dotImg is ~unit-sized; we scale uniformly by r * 2 because image is diameter-based
        local sxy = (s.r * 2) * baseScale
        -- center the sprite: dot texture is authored as centered? We'll offset by 0.5 origin via add params (ox, oy)
        local ox, oy = (dotImg:getWidth() * 0.5), (dotImg:getHeight() * 0.5)
        sb:add(s.x, s.y, 0, sxy, sxy, ox, oy)
      end
    end
  end

  -- one draw
  love.graphics.setColor(1,1,1,1)
  love.graphics.draw(sb)
end

return S
