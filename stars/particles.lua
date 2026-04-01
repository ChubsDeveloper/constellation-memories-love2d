local U = require("core.utils")
local COLORS = require("core.colors")

local M = {}

function M.spawnSparkle(pool, CONFIG, x, y, count, col, surfaceR)
  pool = pool or {}
  count      = count  or CONFIG.SPARKLE_COUNT_DEFAULT
  col        = col    or COLORS.gold
  surfaceR   = surfaceR or 0
  for _=1,count do
    local ang = love.math.random() * math.pi * 2
    local startR = surfaceR + U.rrange(0, 4)
    local sx = x + math.cos(ang) * startR
    local sy = y + math.sin(ang) * startR
    table.insert(pool, {
      x=sx, y=sy,
      vx=math.cos(ang) * U.rrange(CONFIG.SPARKLE_SPEED.min, CONFIG.SPARKLE_SPEED.max),
      vy=math.sin(ang) * U.rrange(CONFIG.SPARKLE_SPEED.min, CONFIG.SPARKLE_SPEED.max),
      size=U.rrange(CONFIG.SPARKLE_SIZE.min, CONFIG.SPARKLE_SIZE.max),
      life=U.rrange(CONFIG.SPARKLE_LIFE.min, CONFIG.SPARKLE_LIFE.max),
      maxLife=1,
      color={(col[1] or 1), (col[2] or 1), (col[3] or 1)}
    })
  end
  return pool
end

function M.createGalaxyParticles(star, CONFIG, StarClasses)
  if not CONFIG.STAR_PARTICLES.enabled then star.particles=nil; return end
  local class = StarClasses[star.starClass] or StarClasses.power
  local particles = {}
  local count = math.max(0, math.floor(class.particleCount * (CONFIG.STAR_PARTICLES.count_mult or 1.0)))
  for i = 1, count do
    local ang = love.math.random() * math.pi * 2
    local base = love.math.random(CONFIG.STAR_PARTICLES.orbit.min, CONFIG.STAR_PARTICLES.orbit.max)
    if CONFIG.STAR_PARTICLES.orbit.add_core then
      local core = (star.style and star.style.radius) or class.coreSize or CONFIG.MEM_RADIUS_BASE
      base = base + core
    end
    particles[i] = {
      x = star.x + math.cos(ang) * base,
      y = star.y + math.sin(ang) * base,
      baseAngle  = ang,
      distance   = base,
      baseDistance = base,
      orbitSpeed = love.math.random(CONFIG.STAR_PARTICLES.orbit_speed.min, CONFIG.STAR_PARTICLES.orbit_speed.max),
      floatSpeed = love.math.random(CONFIG.STAR_PARTICLES.float_speed.min, CONFIG.STAR_PARTICLES.float_speed.max),
      floatAmp   = love.math.random(CONFIG.STAR_PARTICLES.float_amp.min, CONFIG.STAR_PARTICLES.float_amp.max),
      size = love.math.random(CONFIG.STAR_PARTICLES.size.min, CONFIG.STAR_PARTICLES.size.max),
      alpha = love.math.random(CONFIG.STAR_PARTICLES.alpha.min, CONFIG.STAR_PARTICLES.alpha.max),
      pulseOffset = love.math.random() * math.pi * 2,
      color = {1,1,1},
      sparkleTimer = love.math.random() * 2.0
    }
  end
  star.particles = particles
end

function M.updateGalaxyParticles(star, dt, CONFIG, StarClasses)
  if not star.particles then return end
  local class = StarClasses[star.starClass] or StarClasses.power
  local time = love.timer.getTime()
  for _, p in ipairs(star.particles) do
    p.baseAngle = p.baseAngle + p.orbitSpeed * dt
    local float = math.sin(time * p.floatSpeed + p.pulseOffset) * p.floatAmp
    p.distance = p.baseDistance + float
    p.x = star.x + math.cos(p.baseAngle) * p.distance
    p.y = star.y + math.sin(p.baseAngle) * p.distance
    local basePulse = math.sin(time * class.pulseSpeed + p.pulseOffset) * 0.3 + 0.7
    p.alpha = math.min(1, math.max(0.25, p.alpha * 0.98 + basePulse * 0.02))
    p.sparkleTimer = p.sparkleTimer - dt
  end
end

function M.drawSparkles(pool)
  for i=#pool,1,-1 do
    local s=pool[i]
    s.x=s.x+s.vx*love.timer.getDelta()
    s.y=s.y+s.vy*love.timer.getDelta()
    s.vx,s.vy=s.vx*0.95,s.vy*0.95
    s.life=s.life-love.timer.getDelta()
    local lr=math.max(0, s.life/s.maxLife)
    love.graphics.setColor(s.color[1],s.color[2],s.color[3],lr)
    love.graphics.circle("fill",s.x,s.y,s.size*lr)
    local cs=s.size*3*lr
    love.graphics.setLineWidth(0.5)
    love.graphics.line(s.x-cs,s.y,s.x+cs,s.y)
    love.graphics.line(s.x,s.y-cs,s.x,s.y+cs)
    if s.life<=0 then table.remove(pool,i) end
  end
end

function M.drawBursts(bursts, COLORS)
  for i=#bursts,1,-1 do
    local b=bursts[i]; b.time=b.time-love.timer.getDelta()
    if b.time<=0 then table.remove(bursts,i)
    else
      local pct=b.time/b.duration
      for j=1,2 do
        local r=(1-pct)*b.maxRadius*(1-(j-1)*0.25)
        local a=pct*(1-(j-1)*0.35)
        love.graphics.setColor(COLORS.gold[1],COLORS.gold[2],COLORS.gold[3],a*0.45)
        love.graphics.setLineWidth(1.5-(j-1)*0.3)
        love.graphics.circle("line",b.x,b.y,r)
      end
    end
  end
end

return M
