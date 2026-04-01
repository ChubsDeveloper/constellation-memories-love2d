-- star_map.lua — orchestrator (optimized CPU paths, culling & hover)

local MemoryStore = require("memory_store")
local data        = require("data.memories")
local Schema      = require("data.memory_schema")
local memories    = Schema.normalizeAll(data.memories)
local links       = data.links

local CONFIG      = require("core.config")
local U           = require("core.utils")
local COLORS      = require("core.colors")

local PostFX      = require("fx.postfx")
local Presets     = require("fx.presets")

local StarClasses = require("stars.classes")
local Particles   = require("stars.particles")
local RenderStar  = require("stars.render")

local Background  = require("systems.background")
local Links       = require("systems.links")
local Falling     = require("systems.falling")

-- ──────────────────────────────────────────────────────────────────────────────
-- Locals for speed (LuaJIT: fewer table lookups in tight loops)
-- ──────────────────────────────────────────────────────────────────────────────
local lg, lm, lt, lmath = love.graphics, love.mouse, love.timer, love.math
local min, max, sqrt, floor = math.min, math.max, math.sqrt, math.floor

-- Current tooltip font (created once)
local tooltipFont = lg.newFont(CONFIG.TOOLTIP_FONT.path, CONFIG.TOOLTIP_FONT.size)

-- Time source for star pulse (kept identical: disabled when PULSE.enabled == false)
local function animTimeFromConfig()
  local P = (CONFIG and CONFIG.PULSE) or {}
  if P.enabled == false then return 0 end
  return lt.getTime()
end

-- Optional UI (lazy)
local UI
local function withUI(fn)
  if UI == nil then
    local cached = package.loaded["ui"] or package.loaded["ui.ui"]
    if type(cached) == "table" then
      UI = cached
    else
      local ok, m = pcall(require, "ui.ui")
      if not ok then ok, m = pcall(require, "ui") end
      UI = ok and type(m) == "table" and m or false
      if UI and not package.loaded["ui"] then package.loaded["ui"] = UI end
    end
  end
  if UI and type(fn) == "function" then fn(UI) end
end

-- Tween: flux (soft) with shim
local flux do
  local ok, f = pcall(require, "flux"); if not ok then ok, f = pcall(require, "libs.flux") end
  if ok and f then
    flux = f
  else
    local Tweens, EASE = {}, U.EASE
    local function tweenTo(obj, dur, target)
      local ease = EASE.linear
      local start = {}
      for k,_ in pairs(target) do start[k] = obj[k] end
      local tw = {obj=obj, dur=max(0.0001,dur), t=0, start=start, target=target,
                  ease=ease, afters={}, dead=false}
      function tw:after(o, ndur, ntarget) self.afters[#self.afters+1]={o=o,dur=ndur,target=ntarget}; return self end
      function tw:ease(name) self.ease = EASE[name] or self.ease; return self end
      Tweens[#Tweens+1] = tw; return tw
    end
    local function upd(dt)
      for i=#Tweens,1,-1 do
        local tw = Tweens[i]
        if not tw.dead then
          tw.t = tw.t + dt
          local k = min(1, tw.t / tw.dur)
          local e = tw.ease(k)
          for k2,v in pairs(tw.target) do
            local a, b = tw.start[k2], tw.target[k2]
            if type(a)=="number" and type(b)=="number" then
              tw.obj[k2] = a + (b-a)*e
            end
          end
          if tw.t >= tw.dur then
            if #tw.afters > 0 then
              local nxt = table.remove(tw.afters,1)
              tw.start = {}
              for k2,_ in pairs(nxt.target) do tw.start[k2] = tw.obj[k2] end
              tw.target = nxt.target
              tw.dur = max(0.0001, nxt.dur or 0.2)
              tw.t = 0
            else tw.dead = true end
          end
        else table.remove(Tweens,i) end
      end
    end
    flux = { to=function(obj,dur,target) return tweenTo(obj,dur,target) end, update=upd }
  end
end

COMPOSER_PREVIEW_SCALE = 0.54

-- Internal state
local StarMap = {}
local stars, idToStar           = {}, {}
local starBursts, sparkles      = {}, {}
local runtimeMemories           = nil

local linkMode, linkFirst       = false, nil

local leftDown, pressedStar     = false, nil
local pressX, pressY            = 0, 0
local holdTimer                 = 0
local draggingStar              = nil
local dragOffsetX, dragOffsetY  = 0, 0
local dragMoved                 = false
local DRAG_THRESHOLD            = 6

-- Nebula state
local currentNeb, lastNebulaPresetName

-- Helpers from modules
local spawnSparkle           = Particles.spawnSparkle
local createGalaxyParticles  = Particles.createGalaxyParticles
local updateGalaxyParticles  = Particles.updateGalaxyParticles

-- Normalize color (kept identical)
local function normColor(c)
  if type(c) ~= "table" then return 0.95, 0.74, 0.25 end
  local r = c.r or c[1] or 1
  local g = c.g or c[2] or 1
  local b = c.b or c[3] or 1
  if r > 1 or g > 1 or b > 1 then r, g, b = r/255, g/255, b/255 end
  return max(0, min(1, r)), max(0, min(1, g)), max(0, min(1, b))
end

-- STYLE / CLASSES / SCHEMA
StarMap.STYLE_SCHEMA = RenderStar.getStyleSchema(CONFIG)
function StarMap.getStyleSchema() return StarMap.STYLE_SCHEMA end
function StarMap.getStarClasses()
  local classes = {}
  for name,_ in pairs(StarClasses) do classes[#classes+1] = name end
  table.sort(classes); return classes
end

local function applyStyleDefaults(sty) return RenderStar.applyStyleDefaults(sty, CONFIG) end
local function assignStarClass(memory) return RenderStar.assignStarClass(memory, StarClasses) end

-- PUBLIC: preview
function StarMap.drawStarPreview(x, y, style, opts)
  return RenderStar.drawStarPreview(
    x, y, style, opts, CONFIG,
    createGalaxyParticles,
    function(star, t)
      RenderStar.drawMemoryStar(star, t, CONFIG, StarClasses, sparkles, spawnSparkle)
    end
  )
end

-- ──────────────────────────────────────────────────────────────────────────────
-- SAVE/LOAD HELPERS
-- ──────────────────────────────────────────────────────────────────────────────
local function nextId(list) local m=0; for _,v in ipairs(list) do if v.id and v.id>m then m=v.id end end; return m+1 end
local function findStarById(id) for i,s in ipairs(stars) do if s.memory and s.memory.id==id then return i,s end end end

-- ──────────────────────────────────────────────────────────────────────────────
-- PUBLIC API: memories
-- ──────────────────────────────────────────────────────────────────────────────
function StarMap.addMemory(mem)
  mem._scaled = true
  runtimeMemories = runtimeMemories or {}
  if not mem.id then mem.id = nextId(runtimeMemories) end
  if MemoryStore.add then MemoryStore.add(runtimeMemories, mem)
  else
    table.insert(runtimeMemories, mem)
    if MemoryStore.save then MemoryStore.save(runtimeMemories) end
  end

  local styl = applyStyleDefaults(mem.style)
  local star = {
    x=mem.x, y=mem.y,
    radius = styl.radius, style = styl, memory = mem,
    hovered=false, scale=0.6, targetScale=1.0,
    alpha=0.0, glow=0.0,
    targetGlow = CONFIG.MEM_GLOW_IDLE * (styl.glow or 1),
    pulseOffset = lmath.random() * math.pi * 2,
    moving=false,
    starClass = assignStarClass(mem),
    lastX=mem.x, lastY=mem.y,
    particles=nil
  }

  table.insert(stars, star)
  idToStar[mem.id] = star
  createGalaxyParticles(star, CONFIG, StarClasses)

  flux.to(star, 0.25, { alpha = 1.0, scale = 1.15 }):ease("quadout")
      :after(star, 0.20, { scale = 1.0 }):ease("quadinout")

  table.insert(starBursts, { x = star.x, y = star.y, maxRadius =  90, time = 0.8, duration = 0.8 })
  table.insert(starBursts, { x = star.x, y = star.y, maxRadius = 125, time = 0.9, duration = 0.9 })

  local sr, sg, sb = normColor(styl.color)
  spawnSparkle(sparkles, CONFIG, star.x, star.y, 10, {sr, sg, sb})
end

function StarMap.updateMemory(u)
  if not u or not u.id then return end
  local found=false
  for i,m in ipairs(runtimeMemories or {}) do
    if m.id==u.id then runtimeMemories[i]=u; found=true; break end
  end
  if not found then table.insert(runtimeMemories,u) end
  if MemoryStore.update then MemoryStore.update(runtimeMemories,u)
  elseif MemoryStore.save then MemoryStore.save(runtimeMemories) end

  local _,s=findStarById(u.id)
  if s then
    s.x,s.y = u.x,u.y; s.memory=u; s.style=applyStyleDefaults(u.style)
    s.radius=s.style.radius; s.targetGlow=CONFIG.MEM_GLOW_IDLE*(s.style.glow or 1)
  end
end

function StarMap.deleteMemory(id)
  if not id then return end
  for i=#runtimeMemories,1,-1 do if runtimeMemories[i].id==id then table.remove(runtimeMemories,i) break end end
  if MemoryStore.remove then MemoryStore.remove(runtimeMemories,id) elseif MemoryStore.save then MemoryStore.save(runtimeMemories) end
  local idx=findStarById(id); if idx then table.remove(stars,idx) end; idToStar[id]=nil
  Links.removeAllFor(id)
end

function StarMap.isLinkMode()
  local phase=nil; if linkMode then phase=(linkFirst and "second") or "first" end
  return linkMode,phase
end
StarMap.getLinkMode = StarMap.isLinkMode

function StarMap.setCustomStarClass(memoryId, className, customProperties)
  if customProperties then StarClasses[className] = customProperties end
  local star = idToStar[memoryId]; if not star then return end
  star.starClass = className
  createGalaxyParticles(star, CONFIG, StarClasses)
end

-- ──────────────────────────────────────────────────────────────────────────────
-- LOAD
-- ──────────────────────────────────────────────────────────────────────────────
function StarMap.load()
  currentNeb = Presets.resolve(CONFIG)
  lastNebulaPresetName = (CONFIG.NEBULA_PRESET or "orion"):lower()
  PostFX.applyNebula(currentNeb, CONFIG)

  local loaded = (MemoryStore.load and MemoryStore.load(bundled)) or {}

  local loadedMem, loadedLinks
  if type(loaded) == "table" and #loaded > 0 and type(loaded[1]) == "table" and loaded[1].x ~= nil and loaded[1].y ~= nil then
    loadedMem   = loaded
    loadedLinks = (type(bundled) == "table" and bundled.links) or {}
  else
    loadedMem, loadedLinks = Presets.normalizeLoaded(loaded, bundled)
  end

  runtimeMemories = U.deepcopy(loadedMem or {})

  local savedLinks = MemoryStore.loadLinks and MemoryStore.loadLinks(bundled) or {}
  local linksToUse = (#savedLinks > 0) and savedLinks or U.deepcopy(loadedLinks or {})
  Links.load(linksToUse, MemoryStore)

  -- Normalize any out-of-bounds layouts once
  do
    local w, h = lg.getDimensions()
    local needNormalize = false
    for _, m in ipairs(runtimeMemories) do
      if type(m.x) ~= "number" or type(m.y) ~= "number" or m.x < 0 or m.y < 0 or m.x > w or m.y > h then
        needNormalize = true
        break
      end
    end
    if needNormalize then
      Presets.normalizeLayout(runtimeMemories, w, h, 60)
    end
  end

  Presets.ensureIds(runtimeMemories)

  if MemoryStore.save and type(loaded) == "table" and (#loaded > 0 or loaded.memories) then
    MemoryStore.save(runtimeMemories)
  end

  Background.load(CONFIG.BACKGROUND_STARS_COUNT, CONFIG)

  stars, idToStar = {}, {}
  for _, mem in ipairs(runtimeMemories) do
    local st = applyStyleDefaults(mem.style)
    local s  = {
      x=mem.x, y=mem.y, radius=st.radius,
      style=st, memory=mem,
      hovered=false, scale=1, targetScale=1,
      alpha=1, glow=0, targetGlow=CONFIG.MEM_GLOW_IDLE*(st.glow or 1),
      pulseOffset = lmath.random() * math.pi * 2,
      moving=false,
      starClass = assignStarClass(mem),
      lastX=mem.x, lastY=mem.y,
      particles=nil
    }
    table.insert(stars, s)
    if mem.id then idToStar[mem.id] = s end
    createGalaxyParticles(s, CONFIG, StarClasses)
  end

  local function sparkleAdapter(x, y, count, col)
    spawnSparkle(sparkles, CONFIG, x, y, count, col, 0)
  end
  Falling.init(CONFIG, COLORS, sparkleAdapter)

  PostFX.resetScroll()
end

-- ──────────────────────────────────────────────────────────────────────────────
-- UPDATE (optimized: hover-on-move, culling, tight blends)
-- ──────────────────────────────────────────────────────────────────────────────

-- cache viewport for update-side culling, separate from draw margin
local CULL_MARGIN_UPDATE = 180
local screenW, screenH = 0, 0
local function refreshViewport() screenW, screenH = lg.getWidth(), lg.getHeight() end
local function starVisibleForUpdate(s)
  local r = (s.radius or 12) * (s.scale or 1) + 40
  return  s.x + r >= -CULL_MARGIN_UPDATE and
          s.x - r <=  screenW + CULL_MARGIN_UPDATE and
          s.y + r >= -CULL_MARGIN_UPDATE and
          s.y - r <=  screenH + CULL_MARGIN_UPDATE
end

-- recompute hovered only when mouse moved; keep first hovered star for tooltip
local lastMouseX, lastMouseY = -1, -1
local hoveredStar = nil
local function mouseMovedThisFrame(mx, my)
  if mx ~= lastMouseX or my ~= lastMouseY then
    lastMouseX, lastMouseY = mx, my
    return true
  end
  return false
end

local function updateStarVisuals(star, dt)
  updateGalaxyParticles(star, dt, CONFIG, StarClasses)
  if star.moving and star.particles then
    local lx, ly = star.lastX or star.x, star.lastY or star.y
    local sx, sy = star.x, star.y
    for _, p in ipairs(star.particles) do
      local relX = p.x - lx
      local relY = p.y - ly
      p.x = sx + relX
      p.y = sy + relY
    end
  end
  star.lastX, star.lastY = star.x, star.y
end

function StarMap.update(dt)
  local mx,my = lm.getPosition()
  refreshViewport()

  if flux and flux.update then flux.update(dt) end

  -- live-apply nebula preset changes (kept identical)
  local wanted = (CONFIG.NEBULA_PRESET or "orion"):lower()
  if wanted ~= lastNebulaPresetName then
    currentNeb = Presets.resolve(CONFIG)
    lastNebulaPresetName = wanted
    PostFX.applyNebula(currentNeb, CONFIG)
  end

  PostFX.update(dt, currentNeb, CONFIG)
  Background.update(dt, CONFIG)

  -- Drag start (hold)
  if leftDown and pressedStar and not draggingStar then
    holdTimer = holdTimer + dt
    if holdTimer >= CONFIG.HOLD_TO_MOVE_SECONDS then
      draggingStar = pressedStar; pressedStar=nil; draggingStar.moving=true
      local dx, dy = mx-draggingStar.x, my-draggingStar.y
      dragOffsetX,dragOffsetY = dx,dy
      dragMoved=false
      draggingStar.targetScale=1.45
      draggingStar.targetGlow=CONFIG.MEM_GLOW_HOVER*(draggingStar.style.glow or 1)*1.10
    end
  end

  -- Only recompute hovered when mouse actually moved. Pick first match.
  local recomputeHover = mouseMovedThisFrame(mx, my)
  if recomputeHover then hoveredStar = nil end

  -- Stars (update-side cull; still update dragged ones even if offscreen)
  local scaleBlend = min(1, dt * CONFIG.MEM_SCALE_SPEED)
  local glowBlend  = min(1, dt * CONFIG.MEM_GLOW_SPEED)

  for i = 1, #stars do
    local s = stars[i]

    -- Hover test (squared distance) only when needed
    if recomputeHover then
      local dx, dy = mx - s.x, my - s.y
      local pickR  = (s.radius or 12) + 12
      s.hovered    = (dx*dx + dy*dy) < (pickR*pickR)
      if s.hovered and hoveredStar == nil then hoveredStar = s end
    end

    -- Adjust targets based on state
    if s.moving then
      s.targetScale = 1.45
      s.targetGlow  = CONFIG.MEM_GLOW_HOVER*(s.style.glow or 1)*1.10
    elseif s.hovered then
      s.targetScale = CONFIG.MEM_SCALE_HOVER
      s.targetGlow  = CONFIG.MEM_GLOW_HOVER*(s.style.glow or 1)
      if lmath.random() < dt*CONFIG.HOVER_SPAWN_SPARKLE_RATE then
        local hr, hg, hb = normColor(s.style.color)
        spawnSparkle(sparkles, CONFIG, s.x+lmath.random(-10,10), s.y+lmath.random(-10,10), 2, {hr, hg, hb})
      end
    else
      s.targetScale = 1.0
      s.targetGlow  = CONFIG.MEM_GLOW_IDLE*(s.style.glow or 1)
    end

    -- Tight blend
    s.scale = s.scale + (s.targetScale - s.scale) * scaleBlend
    s.glow  = s.glow  + (s.targetGlow  - s.glow ) * glowBlend

    -- Heavy per-particle update only if on-screen (or dragging)
    if s.moving or starVisibleForUpdate(s) then
      updateStarVisuals(s, dt)
    else
      -- still advance last pos to avoid big teleports for particles when re-entering
      s.lastX, s.lastY = s.x, s.y
    end
  end

  -- Falling stars + Links (kept identical)
  Falling.update(dt)
  Links.update(dt, idToStar, sparkles, CONFIG, flux, spawnSparkle)
end

-- ──────────────────────────────────────────────────────────────────────────────
-- DRAW (culled & single tooltip; state churn minimized)
-- ──────────────────────────────────────────────────────────────────────────────
function StarMap.draw()
  local t  = animTimeFromConfig()
  local sw, sh = lg.getDimensions()
  local mx, my = lm.getPosition()

  local CULL_MARGIN = 120
  local function starVisible(s)
    local r = (s.radius or 12) * (s.scale or 1) + 40
    return  s.x + r >= -CULL_MARGIN and
            s.x - r <=  sw + CULL_MARGIN and
            s.y + r >= -CULL_MARGIN and
            s.y - r <=  sh + CULL_MARGIN
  end

  lg.push("all")
  lg.setScissor()
  lg.setShader()
  lg.setBlendMode("alpha", "alphamultiply")
  lg.origin()

  local drawnStars = 0

  PostFX.effect(function()
    PostFX.drawFallbackNebula(lt.getDelta(), currentNeb, CONFIG)
    Background.draw(CONFIG)

    Links.draw(idToStar, CONFIG)
    if linkMode and linkFirst and idToStar[linkFirst] then
      Links.drawPlaceholder(idToStar[linkFirst], mx, my, CONFIG)
    end

    Falling.draw()

    -- Stars (culled)
    for i = 1, #stars do
      local s = stars[i]
      if starVisible(s) then
        RenderStar.drawMemoryStar(s, t, CONFIG, StarClasses, sparkles, spawnSparkle)
        drawnStars = drawnStars + 1
      end
    end

    -- Particles (kept identical)
    Particles.drawSparkles(sparkles)
    Particles.drawBursts(starBursts, COLORS)
  end)

  -- One tooltip max, using cached hoveredStar
  do
    local s = hoveredStar
    if s and s.memory and s.memory.label and s.memory.label ~= "" then
      if not tooltipFont then tooltipFont = lg.getFont() end
      lg.setFont(tooltipFont)

      local text = s.memory.label
      local tw   = tooltipFont:getWidth(text) + 20
      local th   = tooltipFont:getHeight()   + 12
      local tx   = s.x - tw * 0.5
      local ty   = s.y - 50

      lg.setColor(0.10, 0.05, 0.15, 0.90)
      lg.rectangle("fill", tx, ty, tw, th, 8, 8)

      local cr, cg, cb = normColor(s.style and s.style.color or {1,1,1})
      lg.setColor(cr, cg, cb, 0.65)
      lg.setLineWidth(1.2)
      lg.rectangle("line", tx, ty, tw, th, 8, 8)

      lg.setColor(1, 1, 1, 1)
      lg.printf(text, tx, ty + 5, tw, "center")

      lg.setColor(cr, cg, cb, 0.35)
      lg.setLineWidth(1)
      lg.line(s.x, s.y - 15, s.x, ty + th)
    end
  end

  lg.pop()

  if CONFIG and CONFIG.DEBUG_DRAWS then
    local font = lg.getFont()
    lg.setColor(0,0,0,0.6)
    local msg = ("stars drawn (culled): %d / %d"):format(drawnStars, #stars)
    local w = font:getWidth(msg) + 12
    local h = font:getHeight() + 8
    lg.rectangle("fill", 12, 52, w, h, 6, 6)
    lg.setColor(1,1,1,0.95)
    lg.print(msg, 18, 54)
  end
end

-- ──────────────────────────────────────────────────────────────────────────────
-- INPUT
-- ──────────────────────────────────────────────────────────────────────────────
local function starAt(x,y)
  for _,st in ipairs(stars) do
    local dx,dy=x-st.x,y-st.y
    local r = (st.radius or 12) + 14
    if dx*dx+dy*dy<(r*r) then return st end
  end
end

function StarMap.mousepressed(x,y,button)
  if button==2 then withUI(function(u) if u.startCreateAt then u.startCreateAt(x,y) end end); return end
  if button~=1 then return end
  leftDown=true; local s=starAt(x,y)
  if linkMode then
    if s and s.memory and s.memory.id then
      if not linkFirst then
        linkFirst=s.memory.id
      else
        local a,b=linkFirst,s.memory.id
        if a~=b then
          if Links.has(a,b) then Links.remove(a,b, MemoryStore) else Links.add(a,b, MemoryStore) end
          linkFirst=b
        end
      end
    end
    return
  end
  if s then pressedStar=s; pressX,pressY=x,y; holdTimer=0; dragMoved=false; dragOffsetX,dragOffsetY=x-s.x,y-s.y end
end

function StarMap.mousereleased(x,y,button)
  if button~=1 then return end; leftDown=false
  if draggingStar then
    local s=draggingStar; draggingStar=nil; s.moving=false; s.memory.x,s.memory.y=s.x,s.y; StarMap.updateMemory(s.memory); return
  end
  if pressedStar then
    local dx,dy=x-pressX,y-pressY
    local moved=(dx*dx+dy*dy) >= DRAG_THRESHOLD*DRAG_THRESHOLD
    local held=holdTimer>=CONFIG.HOLD_TO_MOVE_SECONDS
    local s=pressedStar; pressedStar=nil; holdTimer=0
    if not moved and not held then
      withUI(function(u) if u.showMemory then u.showMemory(s.memory, s.x, s.y) end end)
      flux.to(s,0.16,{scale=2.0})
          :after(s,0.38,{scale=1.0}):ease("elasticout")
      flux.to(s,0.20,{alpha=0.35})
          :after(s,0.42,{alpha=1.0}):ease("cubicout")
      s.targetScale=s.hovered and CONFIG.MEM_SCALE_HOVER or 1.0
      table.insert(starBursts,{x=s.x,y=s.y,maxRadius=90,time=0.8,duration=0.8})
      table.insert(starBursts,{x=s.x,y=s.y,maxRadius=125,time=0.9,duration=0.9})
      local br, bg, bb = normColor(s.style.color)
      spawnSparkle(sparkles, CONFIG, s.x, s.y, 10, {br, bg, bb})
    end
  end
end

function StarMap.mousemoved(x,y,dx,dy)
  if draggingStar then
    local s=draggingStar
    if not dragMoved then
      local ddx,ddy=x-(s.x+dragOffsetX),y-(s.y+dragOffsetY)
      if ddx*ddx+ddy*ddy>=DRAG_THRESHOLD*DRAG_THRESHOLD then dragMoved=true end
    end
    s.x=x-dragOffsetX; s.y=y-dragOffsetY; s.memory.x,s.memory.y=s.x,s.y; return
  end
  -- ambient sparkle near mouse (kept identical)
  for _,s in ipairs(stars) do
    local ddx,ddy=x-s.x,y-s.y
    if (ddx*ddx+ddy*ddy) < (50*50) and lmath.random()>0.9 then
      local sr, sg, sb = normColor(s.style.color)
      spawnSparkle(sparkles, CONFIG, x, y, 1, {sr, sg, sb})
    end
  end
end

function StarMap.keypressed(key)
  if key=="l" then
    linkMode=not linkMode; linkFirst=nil
  elseif key=="escape" and linkMode then
    linkMode=false; linkFirst=nil
  elseif key=="c" then
    local mx, my = lm.getPosition()
    for _, star in ipairs(stars) do
      local dx, dy = mx - star.x, my - star.y
      if dx*dx + dy*dy < (star.radius + 28)^2 then
        local classes = {"power", "launch", "comet", "green", "red"}
        local currentIndex = 1
        for i, class in ipairs(classes) do if class == star.starClass then currentIndex = i; break end end
        local nextIndex = (currentIndex % #classes) + 1
        star.starClass = classes[nextIndex]
        createGalaxyParticles(star, CONFIG, StarClasses)
        print("Star type: " .. classes[nextIndex])
        break
      end
    end
  elseif key == "n" or key == "N" then
    CONFIG.NEBULA_ENABLED = not CONFIG.NEBULA_ENABLED
    PostFX.toggleNebula(CONFIG, currentNeb)
  end
end

return StarMap
