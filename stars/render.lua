-- stars/render.lua
local GalaxyShader = require("shaders.galaxy")
local Particles    = require("stars.particles")

local R = {}

-- Lua 5.1/5.2 compat
local _unpack = table.unpack or unpack

local function shallow_copy(tbl)
  local r = {}
  if type(tbl) == "table" then
    for k, v in pairs(tbl) do r[k] = v end
  end
  return r
end

local function mix(a,b,t) return a + (b-a)*t end
local function mix3(c1,c2,t) return { mix(c1[1],c2[1],t), mix(c1[2],c2[2],t), mix(c1[3],c2[3],t) } end

-- ------------------------------------------------------------------
-- Shared tiny white texture + spritebatch for ORBIT PARTICLES
-- (one draw per star for all its orbit particles instead of many)
-- ------------------------------------------------------------------
local unitImgParticles
local orbitSB

local function ensureOrbitBatch(minCapacity)
  if not unitImgParticles then
    local d = love.image.newImageData(2, 2)
    d:mapPixel(function() return 1, 1, 1, 1 end)
    unitImgParticles = love.graphics.newImage(d)
    unitImgParticles:setFilter("linear", "linear")
    orbitSB = love.graphics.newSpriteBatch(unitImgParticles, minCapacity or 256, "dynamic")
  else
    -- grow if needed (recreate with larger capacity)
    if minCapacity and minCapacity > orbitSB:getBufferSize() then
      orbitSB = love.graphics.newSpriteBatch(unitImgParticles, minCapacity, "dynamic")
    end
  end
end

-- ------------------------------------------------------------------
-- Style schema (kept as-is, plus halo/rings overrides)
-- ------------------------------------------------------------------
function R.getStyleSchema(CONFIG)
  return {
    { key="radius",  label="Star Size", min=2, max=48, step=0.5, default=CONFIG.MEM_RADIUS_BASE, type="number" },
    { key="glow",    label="Overall Glow", min=0.0, max=3.0, step=0.02, default=1.0, type="number" },

    { key="form",    label="Form", choices={"galaxy","spiky","disc"}, default="galaxy", type="enum" },

    { key="coreRel",   label="Core Size (rel.)", min=0.0, max=1.0, step=0.01, default=0.55, type="number" },
    { key="highlight", label="Centre Glow",      min=0.0, max=2.0, step=0.02, default=1.0,  type="number" },
    { key="specSize",  label="Centre Sparkle",   min=0.00,max=0.60, step=0.01, default=0.18,type="number" },
    { key="coreAlpha", label="Core Opacity",     min=0.0, max=1.5,  step=0.01, default=1.0, type="number" },
    { key="depth",     label="Edge Darken",      min=0.0, max=1.0,  step=0.02, default=0.55,type="number" },
    { key="rim",       label="Edge Glow",        min=0.0, max=2.0,  step=0.02, default=0.45,type="number" },

    { key="ringScale",   label="Outline Size",    min=0.5, max=3.0, step=0.02, default=1.7,  type="number" },
    { key="ringOpacity", label="Outline Opacity", min=0.0, max=1.0, step=0.02, default=0.25, type="number" },

    { key="haloOuterScale", label="Halo Outer Scale", min=0.3, max=2.5, step=0.01, default=1.0, type="number" },
    { key="haloMidScale",   label="Halo Mid Scale",   min=0.3, max=2.5, step=0.01, default=1.0, type="number" },
    { key="haloInnerScale", label="Halo Inner Scale", min=0.3, max=2.5, step=0.01, default=1.0, type="number" },

    { key="haloOuterAlpha", label="Halo Outer Alpha", min=0.0, max=3.0, step=0.02, default=1.0, type="number" },
    { key="haloMidAlpha",   label="Halo Mid Alpha",   min=0.0, max=3.0, step=0.02, default=1.0, type="number" },
    { key="haloInnerAlpha", label="Halo Inner Alpha", min=0.0, max=3.0, step=0.02, default=1.0, type="number" },

    { key="ringsCount",        label="Rings Count",        min=0,   max=8,   step=1,    default=0,   type="int"   },
    { key="ringsSpeed",        label="Rings Speed",        min=0.0, max=3.0, step=0.01, default=1.0, type="number"},
    { key="ringsAlphaBase",    label="Rings Alpha Base",   min=0.0, max=2.0, step=0.01, default=1.0, type="number"},
    { key="ringsAlphaFalloff", label="Rings Alpha Fall.",  min=0.0, max=1.0, step=0.01, default=0.12,type="number"},
    { key="ringsWidthBase",    label="Rings Width Base",   min=0.1, max=6.0, step=0.05, default=2.0, type="number"},
    { key="ringsWidthFalloff", label="Rings Width Fall.",  min=0.0, max=2.0, step=0.02, default=0.4, type="number"},
    { key="ringsWobble1Amp",   label="Rings Wobble1 Amp",  min=0.0, max=0.8, step=0.01, default=0.18,type="number"},
    { key="ringsWobble2Amp",   label="Rings Wobble2 Amp",  min=0.0, max=0.8, step=0.01, default=0.10,type="number"},

    { key="pulseScale", label="Pulse Amount", min=0.0, max=1.0, step=0.01, default=0.60, type="number" },

    { key="color", label="Color", default={0.95,0.74,0.25}, type="color" },
  }
end

-- nil-only defaulting (so 0.0 values stick)
local function default_if_nil(t, key, val)
  if t[key] == nil then t[key] = val end
end

function R.applyStyleDefaults(sty, CONFIG)
  sty = shallow_copy(sty or {})

  default_if_nil(sty, "radius",     CONFIG.MEM_RADIUS_BASE)
  default_if_nil(sty, "color",      {0.95,0.74,0.25})
  default_if_nil(sty, "glow",       1.0)
  sty.form = (sty.form or "galaxy"):lower()

  default_if_nil(sty, "coreRel",    0.55)
  default_if_nil(sty, "highlight",  1.0)
  default_if_nil(sty, "specSize",   0.18)
  default_if_nil(sty, "coreAlpha",  1.0)
  default_if_nil(sty, "depth",      0.55)
  default_if_nil(sty, "rim",        0.45)

  default_if_nil(sty, "ringScale",   1.7)
  default_if_nil(sty, "ringOpacity", 0.25)

  default_if_nil(sty, "haloOuterScale", 1.0)
  default_if_nil(sty, "haloMidScale",   1.0)
  default_if_nil(sty, "haloInnerScale", 1.0)
  default_if_nil(sty, "haloOuterAlpha", 1.0)
  default_if_nil(sty, "haloMidAlpha",   1.0)
  default_if_nil(sty, "haloInnerAlpha", 1.0)

  default_if_nil(sty, "ringsCount",        0)
  default_if_nil(sty, "ringsSpeed",        1.0)
  default_if_nil(sty, "ringsAlphaBase",    1.0)
  default_if_nil(sty, "ringsAlphaFalloff", 0.12)
  default_if_nil(sty, "ringsWidthBase",    2.0)
  default_if_nil(sty, "ringsWidthFalloff", 0.4)
  default_if_nil(sty, "ringsWobble1Amp",   0.18)
  default_if_nil(sty, "ringsWobble2Amp",   0.10)

  default_if_nil(sty, "pulseScale", 0.60)

  default_if_nil(sty, "spikeLenFactor",   2.0)
  default_if_nil(sty, "spikeWidthFactor", 0.22)
  default_if_nil(sty, "spikeAlpha",       0.22)
  default_if_nil(sty, "spikeCount",       8)

  return sty
end

function R.assignStarClass(memory, StarClasses)
  if memory.style and memory.style.starClass then return memory.style.starClass end
  local color = (memory.style and memory.style.color) or {0.95,0.74,0.25}
  if color[1] > color[2] and color[1] > color[3] then
    if color[2] > 0.7 then return "power" else return "red" end
  elseif color[2] > color[1] and color[2] > color[3] then
    return "green"
  elseif color[3] > color[1] and color[3] > color[2] then
    return "launch"
  else
    if color[1] > 0.8 and color[3] > 0.6 then return "comet" end
    return "power"
  end
end

-- ----- unified pulse factor (works for all forms) -----
local function pulseFactor(style, class, CONFIG, star, time)
  local P = CONFIG.PULSE or {}
  local amountMult = (P.amount_mult ~= nil) and P.amount_mult or 1.0
  local speedMult  = (P.speed_mult  ~= nil) and P.speed_mult  or 1.0
  local enabled    = (P.enabled ~= false)
  if not enabled then return 1.0 end

  local classAmp   = (class and class.pulseAmount) or 0.0
  local classSpeed = (class and class.pulseSpeed ) or 1.0
  local perStarAmp = (style and style.pulseScale  ) or 1.0

  local amp   = classAmp * perStarAmp * amountMult
  local speed = classSpeed * speedMult
  if amp == 0 then return 1.0 end

  local phase = time * speed + (star.pulseOffset or 0)
  return 1.0 + math.sin(phase) * amp
end

-- ------------------------------------------------------
-- Spiky form (unchanged)
-- ------------------------------------------------------
local function drawSpikyStar(star, time, galaxyColor, CONFIG, class)
  local s = star.style
  local p = pulseFactor(s, class, CONFIG, star, time)

  local baseR = s.radius
  local r = baseR * (star.scale * CONFIG.MEM_SIZE_MULT) * p
  local cx, cy = star.x, star.y
  local alpha = star.alpha

  local light = mix3(s.color, {1,1,1}, 0.30 + 0.35 * s.highlight)
  local dark  = mix3(s.color, {0,0,0}, 0.30 + 0.45 * s.depth)
  local rings = 12
  for i = rings, 1, -1 do
    local t = i / rings
    local col = mix3(light, dark, 1 - t)
    love.graphics.setColor(col[1], col[2], col[3], (0.10 + 0.06 * t) * alpha * s.coreAlpha)
    love.graphics.circle("fill", cx, cy, r * t)
  end

  love.graphics.setBlendMode("add", "premultiplied")
  love.graphics.setColor(s.color[1], s.color[2], s.color[3], s.spikeAlpha * alpha * (s.glow or 1))
  local innerR = r * 1.02
  local outerR = innerR + r * s.spikeLenFactor
  local spikeW = innerR * s.spikeWidthFactor
  local n = math.max(3, math.floor(s.spikeCount))
  local step = (math.pi * 2) / n
  for i = 0, n - 1 do
    local a = i * step
    local ca, sa = math.cos(a), math.sin(a)
    local ix, iy = cx + ca * innerR, cy + sa * innerR
    local ox, oy = cx + ca * outerR, cy + sa * outerR
    local px, py = -sa * (spikeW * 0.5),  ca * (spikeW * 0.5)
    love.graphics.polygon("fill", ox, oy, ix + px, iy + py, ix - px, iy - py)
  end
  love.graphics.setBlendMode("alpha", "alphamultiply")

  love.graphics.setColor(1, 1, 1, 0.25 * s.highlight * alpha)
  love.graphics.circle("fill", cx - r * 0.18, cy - r * 0.18, r * s.specSize)
  if s.rim > 0.01 then
    local rimCol = mix3(s.color, {1,1,1}, 0.5)
    love.graphics.setColor(rimCol[1], rimCol[2], rimCol[3], 0.22 * s.rim * alpha)
    love.graphics.setLineWidth(1.3)
    love.graphics.circle("line", cx, cy, r * 0.98)
  end

  if s.ringOpacity > 0 then
    love.graphics.setBlendMode("add", "premultiplied")
    love.graphics.setColor(s.color[1], s.color[2], s.color[3], s.ringOpacity * alpha * 0.9)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", cx, cy, r * s.ringScale)
    love.graphics.setBlendMode("alpha", "alphamultiply")
  end
end

-- ------------------------------------------------------
-- Main renderer
-- ------------------------------------------------------
function R.drawMemoryStar(star, time, CONFIG, StarClasses, sparklePool, spawnSparkle)
  if not star.starClass then
    star.starClass = R.assignStarClass(star.memory, StarClasses)
    Particles.createGalaxyParticles(star, CONFIG, StarClasses)
  end

  local s      = star.style
  local class  = StarClasses[star.starClass] or StarClasses.power
  local memCol = s.color
  local galaxyColor = {
    memCol[1] * 0.7 + class.baseColor[1] * 0.3,
    memCol[2] * 0.7 + class.baseColor[2] * 0.3,
    memCol[3] * 0.7 + class.baseColor[3] * 0.3
  }

  local form = s.form or "galaxy"
  if form ~= "galaxy" then
    if form == "spiky" then
      drawSpikyStar(star, time, galaxyColor, CONFIG, class)
    else
      -- DISC: halos + solid core
      local p = pulseFactor(s, class, CONFIG, star, time)
      local r = s.radius * (star.scale * CONFIG.MEM_SIZE_MULT) * p

      love.graphics.setBlendMode("add", "premultiplied")
      local glowMul = (star.glow or (CONFIG.MEM_GLOW_IDLE*(s.glow or 1))) / math.max(1e-6,(CONFIG.MEM_GLOW_IDLE or 1))
      local h = CONFIG.STAR_GLOW
      local os = (h.outer_scale or 2.0) * (s.haloOuterScale or 1.0)
      local ms = (h.mid_scale   or 1.2) * (s.haloMidScale   or 1.0)
      local is = (h.inner_scale or 0.8) * (s.haloInnerScale or 1.0)
      local oa = (h.outer_alpha or 0.20) * (s.haloOuterAlpha or 1.0) * glowMul
      local ma = (h.mid_alpha   or 0.25) * (s.haloMidAlpha   or 1.0) * glowMul
      local ia = (h.inner_alpha or 0.35) * (s.haloInnerAlpha or 1.0) * glowMul
      love.graphics.setColor(galaxyColor[1],galaxyColor[2],galaxyColor[3], star.alpha * oa)
      love.graphics.circle("fill", star.x, star.y, r * os)
      love.graphics.setColor(galaxyColor[1],galaxyColor[2],galaxyColor[3], star.alpha * ma)
      love.graphics.circle("fill", star.x, star.y, r * ms)
      love.graphics.setColor(galaxyColor[1],galaxyColor[2],galaxyColor[3], star.alpha * ia)
      love.graphics.circle("fill", star.x, star.y, r * is)
      love.graphics.setBlendMode("alpha", "alphamultiply")

      love.graphics.setColor(1,1,1, star.alpha * math.min(1, s.coreAlpha or 1))
      love.graphics.circle("fill", star.x, star.y, r)
    end
    return
  end

  -- GALAXY
  local p = pulseFactor(s, class, CONFIG, star, time)
  local coreR = s.radius * (star.scale * CONFIG.MEM_SIZE_MULT) * p

  local glowAnimated = (star.glow or (CONFIG.MEM_GLOW_IDLE*(s.glow or 1)))
  local glowBase     = (CONFIG.MEM_GLOW_IDLE or 1)
  local glowFactor   = glowAnimated / math.max(1e-6, glowBase)

  -- Shader intensity
  local baseFloor = (CONFIG.STAR_GLOW.base_intensity or 0.35)
  local shaderIntensity =
      (baseFloor + (class.glowIntensity or 0)) *
      (s.glow or 1.0) *
      glowFactor *
      (CONFIG.STAR_GLOW.shader_intensity_mult or 1.0) *
      (star.hovered and 1.15 or 1.0)

  -- HALOS (additive)
  love.graphics.setBlendMode("add", "premultiplied")
  do
    local h = CONFIG.STAR_GLOW
    local os = (h.outer_scale or 2.0) * (s.haloOuterScale or 1.0)
    local ms = (h.mid_scale   or 1.2) * (s.haloMidScale   or 1.0)
    local is = (h.inner_scale or 0.8) * (s.haloInnerScale or 1.0)
    local oa = (h.outer_alpha or 0.20) * (s.haloOuterAlpha or 1.0) * glowFactor
    local ma = (h.mid_alpha   or 0.25) * (s.haloMidAlpha   or 1.0) * glowFactor
    local ia = (h.inner_alpha or 0.35) * (s.haloInnerAlpha or 1.0) * glowFactor

    love.graphics.setColor(galaxyColor[1],galaxyColor[2],galaxyColor[3], star.alpha * oa)
    love.graphics.circle("fill", star.x, star.y, coreR * os)
    love.graphics.setColor(galaxyColor[1],galaxyColor[2],galaxyColor[3], star.alpha * ma)
    love.graphics.circle("fill", star.x, star.y, coreR * ms)
    love.graphics.setColor(galaxyColor[1],galaxyColor[2],galaxyColor[3], star.alpha * ia)
    love.graphics.circle("fill", star.x, star.y, coreR * is)
  end
  love.graphics.setBlendMode("alpha", "alphamultiply")

  -- CORE shader
  local specMin, specMax = 0.00, 0.60
  local rawSpec = s.specSize or 0.18
  local spec01  = math.min(1, math.max(0, (rawSpec - specMin) / math.max(1e-6,(specMax - specMin))))

  local relMin  = CONFIG.CORE_REL_MIN or 0.10
  local relMax  = CONFIG.CORE_REL_MAX or 0.85
  local coreRel = (s.coreRel ~= nil) and math.min(1, math.max(0, s.coreRel))
                               or (relMin + (relMax - relMin) * spec01)

  love.graphics.setShader(GalaxyShader)
  GalaxyShader:send("time", time)
  GalaxyShader:send("starColor", galaxyColor)
  GalaxyShader:send("intensity", shaderIntensity)
  GalaxyShader:send("coreSize", coreRel)
  GalaxyShader:send("highlight", s.highlight or 0.0)
  GalaxyShader:send("specSize",  rawSpec)
  GalaxyShader:send("rim",       s.rim       or 0.0)
  GalaxyShader:send("depth",     s.depth     or 0.0)
  GalaxyShader:send("centerPx", {star.x, star.y})
  GalaxyShader:send("radiusPx", coreR)

  love.graphics.setColor(1,1,1, math.min(1, star.alpha * (s.coreAlpha or 1)))
  love.graphics.circle("fill", star.x, star.y, coreR)
  love.graphics.setShader()

  -- ORBIT PARTICLES (batched: one draw per star)
  if star.particles and #star.particles > 0 then
    ensureOrbitBatch(#star.particles)
    orbitSB:clear()
    love.graphics.setBlendMode("add", "premultiplied")

    for _, p in ipairs(star.particles) do
      local a = p.alpha * star.alpha * 0.7
      if p.sparkleTimer <= 0 then
        a = a * 2.0
        p.sparkleTimer = love.math.random(1.0, 3.0)
      end
      orbitSB:setColor(galaxyColor[1], galaxyColor[2], galaxyColor[3], a)
      -- draw a soft dot; center at 1,1 (2x2 img)
      orbitSB:add(p.x, p.y, 0, p.size, p.size, 1, 1)
    end

    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(orbitSB)
    love.graphics.setBlendMode("alpha", "alphamultiply")
  end

  -- WOBBLY RINGS (single polygon draw per ring)
  local rc = math.floor(s.ringsCount or 0)
  if rc > 0 then
    love.graphics.setBlendMode("add", "premultiplied")

    local segments   = CONFIG.STAR_RINGS.segments or 64
    local speed      = s.ringsSpeed or 1.0
    local aBase      = s.ringsAlphaBase or 1.0
    local aFall      = s.ringsAlphaFalloff or 0.12
    local wBase      = s.ringsWidthBase or 2.0
    local wFall      = s.ringsWidthFalloff or 0.4
    local wob1       = s.ringsWobble1Amp or 0.18
    local wob2       = s.ringsWobble2Amp or 0.10

    for ring = 1, rc do
      local ringTime   = time * speed + ring * 0.8
      local baseRadius = (s.radius * (star.scale * CONFIG.MEM_SIZE_MULT)) *
                         ((CONFIG.STAR_RINGS.base_radius or 1.4) + ring * (CONFIG.STAR_RINGS.per_ring_step or 0.26)) *
                         (s.ringScale or 1)

      local alphaMul = aBase - ring * aFall
      if alphaMul > 0.001 then
        love.graphics.setColor(s.color[1], s.color[2], s.color[3], star.alpha * alphaMul)
        love.graphics.setLineWidth(math.max(0.2, wBase - ring * wFall))

        local pts = {}
        for i = 0, segments - 1 do
          local a = (i / segments) * (math.pi * 2)
          local variation = 1.0
          local W1 = CONFIG.STAR_RINGS.wobble1 or { freq = 5.0, speed = 0.6 }
          local W2 = CONFIG.STAR_RINGS.wobble2 or { freq = 9.0, speed = 0.4 }
          variation = variation + math.sin(a * W1.freq + ringTime * W1.speed) * wob1
          variation = variation + math.sin(a * W2.freq - ringTime * W2.speed) * wob2
          local r = baseRadius * variation
          pts[#pts+1] = star.x + math.cos(a) * r
          pts[#pts+1] = star.y + math.sin(a) * r
        end
        love.graphics.polygon("line", pts) -- ONE draw per ring
      end
    end

    love.graphics.setBlendMode("alpha", "alphamultiply")
  elseif CONFIG.STAR_RINGS.enabled and (s.ringOpacity or 0) > 0 then
    -- Fallback/global rings (also single polygon per ring)
    love.graphics.setBlendMode("add", "premultiplied")
    local segments   = CONFIG.STAR_RINGS.segments
    local ringCount  = (StarClasses[star.starClass] or {}).ringCount or 3
    local ringSpeed  = (StarClasses[star.starClass] or {}).ringSpeed or 1.0

    for ring = 1, ringCount do
      local ringTime   = time * ringSpeed + ring * 0.8
      local baseRadius = (s.radius * (star.scale * CONFIG.MEM_SIZE_MULT)) *
                         (CONFIG.STAR_RINGS.base_radius + ring * CONFIG.STAR_RINGS.per_ring_step) *
                         (s.ringScale or 1)

      local aMul = (CONFIG.STAR_RINGS.alpha_base - ring * CONFIG.STAR_RINGS.alpha_falloff) * (s.ringOpacity or 0)
      if aMul > 0.001 then
        love.graphics.setColor(s.color[1], s.color[2], s.color[3], star.alpha * aMul)
        love.graphics.setLineWidth(math.max(0.2, (CONFIG.STAR_RINGS.width_base - ring * CONFIG.STAR_RINGS.width_falloff)))

        local pts = {}
        for i = 0, segments - 1 do
          local a = (i / segments) * (math.pi * 2)
          local variation = 1.0
          variation = variation + math.sin(a * CONFIG.STAR_RINGS.wobble1.freq + ringTime * CONFIG.STAR_RINGS.wobble1.speed) * CONFIG.STAR_RINGS.wobble1.amp
          variation = variation + math.sin(a * CONFIG.STAR_RINGS.wobble2.freq - ringTime * CONFIG.STAR_RINGS.wobble2.speed) * CONFIG.STAR_RINGS.wobble2.amp
          local r = baseRadius * variation
          pts[#pts+1] = star.x + math.cos(a) * r
          pts[#pts+1] = star.y + math.sin(a) * r
        end
        love.graphics.polygon("line", pts)
      end
    end

    love.graphics.setBlendMode("alpha", "alphamultiply")
  end

  -- AURA sparkles (unchanged logic; sparkles themselves are batched in particles.lua)
  local auraRate = (CONFIG.STAR_AURA_SPARKLES.rate or 0) * ((StarClasses[star.starClass] or {}).sparkleRate or 1)
  if love.math.random() < auraRate then
    local inner = s.radius * (star.scale * CONFIG.MEM_SIZE_MULT) * CONFIG.STAR_AURA_SPARKLES.radius_inner_mult
    local outer = s.radius * (star.scale * CONFIG.MEM_SIZE_MULT) * CONFIG.STAR_AURA_SPARKLES.radius_outer_mult
    local ang   = love.math.random() * math.pi * 2
    local r     = inner + (outer - inner) * love.math.random()
    spawnSparkle(
      sparklePool, CONFIG,
      star.x + math.cos(ang) * r, star.y + math.sin(ang) * r,
      CONFIG.STAR_AURA_SPARKLES.count,
      { galaxyColor[1], galaxyColor[2], galaxyColor[3] },
      0
    )
  end
end

-- Orchestrated preview (uses same renderer)
function R.drawStarPreview(x, y, style, opts, CONFIG, createParticles, drawStarFn)
  local s = R.applyStyleDefaults(style or {}, CONFIG)
  opts = opts or {}
  local tmp = {
    x = x, y = y,
    style = s,
    radius = s.radius,
    alpha = 1,
    hovered = opts.hovered or false,
    scale = opts.previewScale or (1 / CONFIG.MEM_SIZE_MULT),
    targetScale = 1,
    glow = CONFIG.MEM_GLOW_IDLE * (s.glow or 1), targetGlow = 0, pulseOffset = 0,
    memory = { style = s }, starClass = "power", particles = nil,
  }
  if opts.with_particles ~= false then createParticles(tmp, CONFIG, require("stars.classes")) end
  love.graphics.push("all")
  local t = (opts and opts.time) or love.timer.getTime()
  drawStarFn(tmp, t)
  love.graphics.pop()
  return true
end

return R
