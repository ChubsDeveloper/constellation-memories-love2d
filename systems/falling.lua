-- systems/falling.lua
-- Falling stars (shooting stars) system — optimized:
--  • Viewport culling for off-screen stars & trails
--  • Adaptive spawn/trail on low FPS (optional)
--  • Fewer state changes inside loops

local Falling = {}

-- injected
local CFG
local COLORS
local spawnSparkle -- function(pool, CFG, x, y, count, col, surfaceR)

-- active list
local list = {}

-- cache width/height per frame to avoid repeated calls
local screenW, screenH = 0, 0
local function refreshViewport()
  screenW, screenH = love.graphics.getWidth(), love.graphics.getHeight()
end

local function angle(dx,dy)
  if dx == 0 then return (dy>=0) and (math.pi/2) or (-math.pi/2) end
  return math.atan(dy/dx) + (dx<0 and math.pi or 0)
end

-- —————————————————————————————————————————————————————
-- Adaptive knobs (safe defaults keep original look)
local ADAPT = {
  enable_fps_adapt = true,    -- turn off if you want strict original
  fps_hi = 120,               -- above this: full quality
  fps_lo = 60,                -- below this: reduce work
  spawn_mult_hi = 1.00,
  spawn_mult_lo = 0.55,       -- fewer stars when slow
  trail_len_mult_hi = 1.00,
  trail_len_mult_lo = 0.60,   -- shorter trails when slow
  spikes_hi = 8,
  spikes_lo = 6,              -- fewer head spikes when slow
}

local function qualityScale()
  if not ADAPT.enable_fps_adapt then return 1 end
  local fps = love.timer.getFPS()
  if fps >= ADAPT.fps_hi then return 1 end
  if fps <= ADAPT.fps_lo then return 0 end
  -- map [fps_lo..fps_hi] -> [0..1]
  return (fps - ADAPT.fps_lo) / (ADAPT.fps_hi - ADAPT.fps_lo)
end

-- —————————————————————————————————————————————————————
local function spawnOne()
  local ang   = math.rad(love.math.random(CFG.FS_ANGLE_DEG.min, CFG.FS_ANGLE_DEG.max))
  local speed = love.math.random(CFG.FS_SPEED.min, CFG.FS_SPEED.max)
  local dir   = love.math.random() < 0.5 and 1 or -1
  local depth = love.math.random()
  local size  = love.math.random(CFG.FS_SIZE.min, CFG.FS_SIZE.max)
  local sx    = love.math.random(0, screenW)

  -- trail length (adaptive)
  local q = qualityScale()
  local trailLen = math.max(3, math.floor(CFG.FS_TRAIL_LENGTH * (ADAPT.trail_len_mult_lo + (ADAPT.trail_len_mult_hi - ADAPT.trail_len_mult_lo) * q)))

  local trail = {}
  for i = 1, trailLen do trail[i] = { x = sx, y = -30 } end

  local dx, dy = math.cos(ang) * speed * dir, math.sin(ang) * speed

  list[#list+1] = {
    x = sx, y = -30, dx = dx, dy = dy,
    life = CFG.FS_LIFE, maxLife = CFG.FS_LIFE,
    alpha = CFG.FS_ALPHA_BASE.min + CFG.FS_ALPHA_BASE.extra * (1 - depth),
    size = size, rot = angle(dx,dy),
    trail = trail, trailTimer = 0,
    trailWidthBoost = 1 + CFG.FS_TRAIL_WIDTH_BOOST_NEAR * (1 - depth),
  }
end

-- —————————————————————————————————————————————————————
function Falling.init(config, palette, sparkleFn)
  CFG = config
  COLORS = palette or {
    gold      = {1.00, 0.88, 0.45},
    deepGold  = {0.95, 0.74, 0.25},
    highlight = {1.00, 0.96, 0.70},
  }
  spawnSparkle = sparkleFn or function() end
  list = {}
  refreshViewport()
end

function Falling.spawn()
  spawnOne()
end

function Falling.clear()
  list = {}
end

function Falling.update(dt)
  refreshViewport()

  -- adaptive spawn rate
  local q = qualityScale()
  local spawnMult = ADAPT.spawn_mult_lo + (ADAPT.spawn_mult_hi - ADAPT.spawn_mult_lo) * q
  local spawnRate = 0.25 * spawnMult
  if love.math.random() < dt * spawnRate then
    spawnOne()
  end

  -- update active
  local H_OUT = screenH + 60
  for i = #list, 1, -1 do
    local f = list[i]
    f.x = f.x + f.dx * dt
    f.y = f.y + f.dy * dt
    f.life = f.life - dt

    f.trailTimer = f.trailTimer + dt
    if f.trailTimer > 0.02 then
      -- move trail forward
      table.remove(f.trail, 1)
      f.trail[#f.trail+1] = { x = f.x, y = f.y }
      f.trailTimer = 0

      -- sparkle (cheap) — keep original probability
      if love.math.random() > 0.7 then
        spawnSparkle(f.x, f.y, 2, COLORS.gold)
      end
    end

    -- kill when off-screen far or dead
    if f.life <= 0 or f.y > H_OUT then
      table.remove(list, i)
    end
  end
end

-- fast rect-line overlap check (coarse)
local function segWithinScreen(x1,y1,x2,y2)
  local minx = (x1 < x2) and x1 or x2
  local maxx = (x1 > x2) and x1 or x2
  local miny = (y1 < y2) and y1 or y2
  local maxy = (y1 > y2) and y1 or y2
  -- expand a bit
  local pad = 6
  if maxx < -pad or minx > screenW + pad or maxy < -pad or miny > screenH + pad then
    return false
  end
  return true
end

function Falling.draw()
  if #list == 0 then return end

  -- cache colors we reuse
  local dg, hi, go = COLORS.deepGold, COLORS.highlight, COLORS.gold

  for _, f in ipairs(list) do
    local lifeRatio = f.life / f.maxLife

    -- trail (cull segments completely off-screen)
    local tLen = #f.trail
    if tLen >= 2 then
      for i = tLen, 2, -1 do
        local p1, p2 = f.trail[i], f.trail[i-1]
        if p1 and p2 and segWithinScreen(p1.x, p1.y, p2.x, p2.y) then
          local tt = i / tLen
          local a  = tt * f.alpha * lifeRatio

          -- blended color along trail
          local r = dg[1] * tt + hi[1] * (1 - tt)
          local g = dg[2] * tt + hi[2] * (1 - tt)
          local b = dg[3] * tt + hi[3] * (1 - tt)

          love.graphics.setColor(r, g, b, a * 0.6)
          love.graphics.setLineWidth(CFG.FS_TRAIL_WIDTH_BASE + i * CFG.FS_TRAIL_WIDTH_STEP * f.trailWidthBoost)
          love.graphics.line(p1.x, p1.y, p2.x, p2.y)
        end
      end
    end

    -- head (skip if far off-screen)
    if f.x > -40 and f.x < screenW + 40 and f.y > -40 and f.y < screenH + 80 then
      love.graphics.push()
      love.graphics.translate(f.x, f.y)
      love.graphics.rotate(f.rot)

      local rC        = f.size * 0.65
      local spikeLen  = rC * 1.5
      local spikeW    = math.max(0.8, rC * 0.18)
      local spikeA    = 0.16 * (f.alpha * lifeRatio)

      -- core discs
      love.graphics.setColor(dg[1], dg[2], dg[3], f.alpha * lifeRatio)
      love.graphics.circle("fill", 0, 0, rC)
      love.graphics.setColor(hi[1], hi[2], hi[3], 0.5 * (f.alpha * lifeRatio))
      love.graphics.circle("fill", 0, 0, rC * 0.52)
      love.graphics.setColor(1, 1, 1, 0.3 * (f.alpha * lifeRatio))
      love.graphics.circle("fill", 0, 0, rC * 0.2)

      -- star spikes (adaptive count)
      local spikes = math.floor(ADAPT.spikes_lo + (ADAPT.spikes_hi - ADAPT.spikes_lo) * qualityScale())
      spikes = math.max(4, spikes)
      local step = (math.pi * 2) / spikes
      love.graphics.setColor(go[1], go[2], go[3], spikeA)
      for i = 0, spikes - 1 do
        local a  = i * step
        local ca = math.cos(a)
        local sa = math.sin(a)
        local x1, y1 = ca * spikeLen, sa * spikeLen
        local x2, y2 = -sa * (spikeW * 0.5),  ca * (spikeW * 0.5)
        local x3, y3 =  sa * (spikeW * 0.5), -ca * (spikeW * 0.5)
        love.graphics.polygon("fill", x1,y1, x2,y2, x3,y3)
      end

      love.graphics.pop()
    end
  end
end

function Falling._getActive()
  return list
end

return Falling
