local CONFIG = require("core.config")
local M = {}

-- moonshine (soft)
local moonshine do
  local ok, m = pcall(require, "moonshine")
  if not ok then ok, m = pcall(require, "libs.moonshine") end
  moonshine = ok and m or nil
end

local effect              -- callable wrapper
local useMoonshineNebula = false
local nebulaFxCtor = nil
local nebulaScroll = {x=0,y=0}

-- fallback canvas shader (low-cost path)
local fallback = {
  enabled=false, canvas=nil, w=0, h=0, scroll={x=0,y=0}, shader=nil,
  accum=0, update_interval=1/30,  -- throttle: default 30 FPS
}

-- Performance tracking
local performanceMode = false
local lastFPS = 60
local fpsCheckTimer = 0

-- ---------- helpers ----------
local function identity_effect()
  -- no extra pass; just call fn()
  return setmetatable({}, { __call=function(_, fn) fn() end })
end

local function anyMoonshineEnabled(cfg)
  return (cfg.GLOW_STRENGTH or 0) > 0
      or (cfg.ENABLE_CHROMASEP == true)
      or (cfg.ENABLE_FILMGRAIN == true)
      or (cfg.ENABLE_SCANLINES == true)
      or (cfg.VIGNETTE_OPACITY or 0) > 0
      or (cfg.HAZE_STRENGTH or 0) > 0        -- NEW: Haze support
      or (cfg.USE_MOONSHINE_NEBULA == true)
end

local function ensureFallbackCanvas(cfg)
  local W, H = love.graphics.getDimensions()
  -- Adaptive downscaling based on performance
  local baseScale = cfg.FALLBACK_DOWNSCALE or 2
  local scale = performanceMode and math.max(baseScale, 3) or baseScale
  scale = math.max(1, scale)
  
  local w, h = math.floor(W/scale), math.floor(H/scale)
  if not fallback.canvas or fallback.w ~= w or fallback.h ~= h then
    fallback.canvas = love.graphics.newCanvas(w, h)
    fallback.w, fallback.h = w, h
  end
end

-- Optimized fallback shader (faster hash function)
local function buildFallbackShader()
  if fallback.shader then return end
  fallback.shader = love.graphics.newShader([[
extern number time; extern vec2 resolution; extern vec2 scroll;
extern number intensity; extern vec3 color1; extern vec3 color2; extern vec3 color3;
extern number layers; extern number warp; extern number cloudLow; extern number cloudHigh;
extern number depthFalloff; extern number quality;

// Faster hash function (no sin/cos)
float hash(vec2 p){ 
  p = fract(p * 0.3183099 + 0.1);
  p *= 17.0;
  return fract(p.x * p.y * (p.x + p.y));
}

float noise(vec2 p){ 
  vec2 i=floor(p), f=fract(p); 
  // Faster smoothstep
  f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  float a=hash(i); float b=hash(i+vec2(1.0,0.0)); 
  float c=hash(i+vec2(0.0,1.0)); float d=hash(i+vec2(1.0,1.0));
  return mix(mix(a,b,f.x), mix(c,d,f.x), f.y);
}

// Adaptive FBM based on quality
float fbm_layers(vec2 p, float layersF, float q){ 
  float v=0.0, a=0.5, f=1.0;
  int maxLayers = int(min(6.0, layersF * q + 1.0));
  for(int i=0; i < 6; i++){ 
    if (i >= maxLayers) break;
    float m = step(float(i), layersF-1.0); 
    v += m * a * noise(p * f); 
    f *= 2.02; 
    a *= 0.5; 
  } 
  return v; 
}

vec2 domainWarp(vec2 p, float amt, float layersF, float q){
  float w1 = fbm_layers(p + vec2(3.4, 1.7), min(layersF, 3.0), q);
  float w2 = fbm_layers(p + vec2(5.1,-2.3), min(layersF, 3.0), q);
  return p + amt * vec2(w1, w2);
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  // Early exit for very low intensity
  if (intensity < 0.005) return vec4(0.0, 0.0, 0.0, 0.0);
  
  vec2 res = resolution;
  vec2 p = (sc + scroll) / res.y;
  
  // Quality-based LOD
  vec2 center = res * 0.5;
  float distFromCenter = length(sc - center) / res.y;
  float lodQuality = quality * (1.0 - smoothstep(0.0, 0.7, distFromCenter) * 0.4);
  
  vec2 pw = domainWarp(p * vec2(1.0), warp, layers, lodQuality);
  float t1 = fbm_layers(pw + vec2(time*0.010, time*0.008), layers, lodQuality);
  float t2 = fbm_layers(pw*1.5 + vec2(time*0.008,-time*0.010), layers, lodQuality * 0.8);
  float t3 = fbm_layers(pw*0.8 + vec2(-time*0.012, time*0.012), layers, lodQuality * 0.6);
  
  float d1 = smoothstep(cloudLow, cloudHigh, t1);
  float d2 = smoothstep(cloudLow+0.05, cloudHigh+0.05, t2);
  float d3 = smoothstep(cloudLow-0.08, cloudHigh-0.08, t3);
  
  vec3 neb = vec3(0.0);
  neb += color1 * d1 * 0.85;
  neb += color2 * d2 * 0.65;
  neb += color3 * d3 * 0.45;
  
  float cshift = fbm_layers(pw*2.0 + time*0.005, 2.0, lodQuality);
  neb *= (0.8 + 0.4 * cshift);
  
  float centerDist = length((sc - res*0.5) / res.y);
  float falloff = 1.0 - smoothstep(0.2, 0.8, centerDist);
  neb *= mix(1.0, falloff, clamp(depthFalloff, 0.0, 1.0));
  
  return vec4(neb * max(0.0,intensity), 1.0) * color;
}]])
end

-- Performance monitoring
local function updatePerformanceMode(dt)
  fpsCheckTimer = fpsCheckTimer + dt
  if fpsCheckTimer > 2.0 then -- Check every 2 seconds
    fpsCheckTimer = 0
    local currentFPS = love.timer.getFPS()
    
    -- Enable performance mode if FPS drops below 45
    if currentFPS < 45 and not performanceMode then
      performanceMode = true
      print("Performance mode enabled (FPS: " .. currentFPS .. ")")
    -- Disable if FPS is stable above 55 for a while
    elseif currentFPS > 55 and performanceMode then
      performanceMode = false
      print("Performance mode disabled (FPS: " .. currentFPS .. ")")
    end
    
    lastFPS = currentFPS
  end
end

-- ---------- build effect chain ----------
local function buildEffect(cfg)
  -- Adaptive throttle based on performance
  local baseUpdateRate = cfg.FALLBACK_UPDATE_FPS or 30
  local updateRate = performanceMode and math.max(20, baseUpdateRate * 0.7) or baseUpdateRate
  fallback.update_interval = 1 / updateRate

  -- optional Moonshine nebula ctor
  if moonshine then
    local ok, ctor = pcall(require, "effects.nebula")
    if not ok then ok, ctor = pcall(require, "nebula") end
    if ok and type(ctor)=="function" then nebulaFxCtor = ctor end
  end

  if moonshine and anyMoonshineEnabled(cfg) then
    -- Build only enabled passes
    local chain = nil
    local function add(pass, setup)
      if not pass then return end
      chain = chain and chain.chain(pass) or moonshine(pass)
      if setup then setup(chain) end
    end

    -- Adaptive glow strength based on performance
    local glowStrength = cfg.GLOW_STRENGTH or 0
    if performanceMode and glowStrength > 5 then
      glowStrength = glowStrength * 0.6  -- Reduce intensity in performance mode
    end
    
    if glowStrength > 0 and moonshine.glow then
      add(moonshine.glow, function(e) e.glow.strength = glowStrength end)
    end
    
    -- Skip expensive effects in performance mode
    if cfg.ENABLE_CHROMASEP and moonshine.chromasep and not (performanceMode and cfg.CHROMASEP_RADIUS > 0.001) then
      add(moonshine.chromasep, function(e)
        e.chromasep.radius = cfg.CHROMASEP_RADIUS
        e.chromasep.angle  = cfg.CHROMASEP_ANGLE
      end)
    end
    
    -- Reduce film grain in performance mode
    if cfg.ENABLE_FILMGRAIN and moonshine.filmgrain then
      local opacity = cfg.FILMGRAIN_OPACITY
      if performanceMode then opacity = opacity * 0.5 end
      add(moonshine.filmgrain, function(e)
        e.filmgrain.size    = cfg.FILMGRAIN_SIZE
        e.filmgrain.opacity = opacity
      end)
    end
    
    if cfg.ENABLE_SCANLINES and moonshine.scanlines and not performanceMode then
      add(moonshine.scanlines, function(e)
        e.scanlines.thickness = cfg.SCANLINES_THICKNESS
        e.scanlines.opacity   = cfg.SCANLINES_OPACITY
      end)
    end
    
    -- NEW: Haze support with quality control
    if (cfg.HAZE_STRENGTH or 0) > 0 and moonshine.haze then
      local quality = performanceMode and 0.4 or (cfg.HAZE_QUALITY or 0.8)
      add(moonshine.haze, function(e)
        e.haze.strength = cfg.HAZE_STRENGTH
        e.haze.scale = cfg.HAZE_SCALE or {4.0, 4.0}
        -- Only send quality uniform if the shader supports it
        if e.haze.shader and e.haze.shader.send then
          local ok = pcall(function()
            e.haze.shader:send("quality", quality)
          end)
          if not ok then
            -- Shader doesn't have quality uniform, use basic settings
            if performanceMode then
              e.haze.strength = e.haze.strength * 0.7 -- Reduce strength instead
            end
          end
        end
      end)
    end
    
    if (cfg.VIGNETTE_OPACITY or 0) > 0 and moonshine.vignette then
      add(moonshine.vignette, function(e)
        e.vignette.radius   = cfg.VIGNETTE_RADIUS
        e.vignette.softness = cfg.VIGNETTE_SOFTNESS
        e.vignette.opacity  = cfg.VIGNETTE_OPACITY
        e.vignette.color    = cfg.VIGNETTE_COLOR
      end)
    end
    
    if cfg.USE_MOONSHINE_NEBULA and nebulaFxCtor then
      add(nebulaFxCtor)
      useMoonshineNebula = true
    else
      useMoonshineNebula = false
    end

    effect = chain or identity_effect()
  else
    -- No passes at all → zero extra draws
    effect = identity_effect()
    useMoonshineNebula = false
  end

  -- Fallback shader prepared either way
  buildFallbackShader()
  fallback.enabled = cfg.NEBULA_ENABLED
end

-- ---------- API ----------
function M.effect(fn) return effect(fn) end

function M.applyNebula(currentNeb, cfg)
  if not effect then buildEffect(cfg) end
  if useMoonshineNebula and currentNeb then
    effect.nebula.intensity    = cfg.NEBULA_ENABLED and currentNeb.intensity or 0.0
    effect.nebula.scale        = currentNeb.scale
    effect.nebula.layers       = currentNeb.layers
    effect.nebula.warp         = currentNeb.warp
    effect.nebula.color1       = currentNeb.colors[1]
    effect.nebula.color2       = currentNeb.colors[2]
    effect.nebula.color3       = currentNeb.colors[3]
    effect.nebula.cloudLow     = currentNeb.thresholds.low
    effect.nebula.cloudHigh    = currentNeb.thresholds.high
    effect.nebula.depthFalloff = currentNeb.depthFalloff
    effect.nebula.scroll       = {0,0}
  end
end

function M.resetScroll()
  nebulaScroll.x, nebulaScroll.y = 0, 0
  fallback.scroll.x, fallback.scroll.y = 0, 0
  fallback.accum = 0
end

function M.update(dt, currentNeb, cfg)
  if not effect then buildEffect(cfg) end
  
  -- Performance monitoring
  updatePerformanceMode(dt)

  -- scroll
  if cfg.NEBULA_ENABLED then
    nebulaScroll.x = nebulaScroll.x + (cfg.NEBULA_SCROLL_SPEED.x or 0) * dt * love.graphics.getWidth()
    nebulaScroll.y = nebulaScroll.y + (cfg.NEBULA_SCROLL_SPEED.y or 0) * dt * love.graphics.getHeight()
  end

  if useMoonshineNebula and currentNeb then
    effect.nebula.time      = love.timer.getTime()
    effect.nebula.intensity = cfg.NEBULA_ENABLED and currentNeb.intensity or 0.0
    effect.nebula.scroll    = { nebulaScroll.x, nebulaScroll.y }
  end

  -- throttle fallback updates
  fallback.accum = fallback.accum + dt
end

function M.toggleNebula(cfg, currentNeb)
  cfg.NEBULA_ENABLED = not cfg.NEBULA_ENABLED
  if useMoonshineNebula and currentNeb then
    effect.nebula.intensity = cfg.NEBULA_ENABLED and currentNeb.intensity or 0.0
  else
    fallback.enabled = cfg.NEBULA_ENABLED
  end
end

-- Draw low-cost fallback nebula (downscaled canvas), throttled
function M.drawFallbackNebula(dt, currentNeb, cfg)
  if useMoonshineNebula or not fallback.enabled or not currentNeb then return end
  ensureFallbackCanvas(cfg)

  local needUpdate = fallback.accum >= fallback.update_interval
  if needUpdate then
    fallback.accum = 0
    fallback.scroll.x = fallback.scroll.x + (cfg.NEBULA_SCROLL_SPEED.x or 0) * (fallback.update_interval) * fallback.w
    fallback.scroll.y = fallback.scroll.y + (cfg.NEBULA_SCROLL_SPEED.y or 0) * (fallback.update_interval) * fallback.h

    love.graphics.push("all")
    love.graphics.setCanvas(fallback.canvas)
    love.graphics.clear(0,0,0,0)
    love.graphics.setShader(fallback.shader)
    fallback.shader:send("time", love.timer.getTime())
    fallback.shader:send("resolution", {fallback.w, fallback.h})
    fallback.shader:send("scroll", {fallback.scroll.x, fallback.scroll.y})
    fallback.shader:send("intensity", cfg.NEBULA_ENABLED and currentNeb.intensity or 0.0)
    fallback.shader:send("color1", currentNeb.colors[1])
    fallback.shader:send("color2", currentNeb.colors[2])
    fallback.shader:send("color3", currentNeb.colors[3])
    fallback.shader:send("layers", currentNeb.layers)
    fallback.shader:send("warp", currentNeb.warp)
    fallback.shader:send("cloudLow", currentNeb.thresholds.low)
    fallback.shader:send("cloudHigh", currentNeb.thresholds.high)
    fallback.shader:send("depthFalloff", currentNeb.depthFalloff)
    -- NEW: Quality setting for adaptive performance
    fallback.shader:send("quality", performanceMode and 0.4 or 0.8)
    love.graphics.setColor(1,1,1,1)
    love.graphics.rectangle("fill", 0, 0, fallback.w, fallback.h) -- 1 draw
    love.graphics.setShader()
    love.graphics.setCanvas()
    love.graphics.pop()
  end

  -- Blit cached canvas (always 1 draw)
  love.graphics.push("all")
  love.graphics.setColor(1,1,1, 1.0)
  love.graphics.draw(
    fallback.canvas, 0, 0, 0,
    (love.graphics.getWidth()/fallback.w),
    (love.graphics.getHeight()/fallback.h)
  )
  love.graphics.pop()
end

-- Performance info
function M.getPerformanceInfo()
  return {
    performanceMode = performanceMode,
    lastFPS = lastFPS,
    fallbackScale = fallback.w and (love.graphics.getWidth() / fallback.w) or 1
  }
end

return M