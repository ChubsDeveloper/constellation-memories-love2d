--====================================================================--
--  startup.lua – Constellation Memories splash / title animation
--====================================================================--
--  ▸ Star arcs across on a cubic Bezier at constant speed (no easing
--    slowdown), paints the Title then the Subtitle. Each glyph spawns
--    EXACTLY at the star's current position using font baseline metrics.
--  ▸ Title sheen (masked to glyphs), impact rings, sparkles, trail.
--  ▸ Pure LÖVE; no external deps. Camera shake removed.
--  ▸ Robust to frame hiccups: catches up reveals across large dt.
--====================================================================--

local Startup = {}

-----------------------------------------------------------------------
--  CONFIG
-----------------------------------------------------------------------
local CONFIG = {
  -- Motion ----------------------------------------------------------
  STAR_SPEED_T            = 2.0,       -- seconds to traverse the curve
  STAR_SIZE               = 1.7,
  STAR_SPIN_SPEED         = math.pi,   -- rad/s
  STAR_BOB_AMPLITUDE      = 1.0,       -- visual micro-bob around the path

  -- Where rows live (pick your poison) ------------------------------
  -- If value <= 1, treated as a fraction of screen height.
  -- If value >  1, treated as absolute pixels from top.
  TITLE_ROW_Y             = 0.40,
  SUB_ROW_Y               = 0.55,

  -- Bezier path shaping (screen-relative) ---------------------------
  PATH_CTRL_OFFSET_X      = 0.20,      -- % from ends toward center
  PATH_CTRL_OFFSET_Y      = -0.08,     -- % of H (negative = arc up)
  PATH_SAMPLES            = 250,       -- arc-length LUT resolution

  -- Let the star path ride higher/lower than the text baseline (px) -
  STAR_PATH_Y_OFFSET      = { title = 60, subtitle = 80 },

  -- Impact rings (no shake) ----------------------------------------
  IMPACT_XNORM            = 0.50,
  IMPACT_RING_COUNT       = 3,
  IMPACT_RING_MAX_R       = 140,
  IMPACT_RING_TIME        = 0.7,
  IMPACT_BURST_SPARKLES   = 28,

  -- Timing ----------------------------------------------------------
  TITLE_DELAY             = 0.6,
  COMPLETION_DELAY        = 1.4,
  FADE_OUT_TIME           = 1.0,

  -- Fonts -----------------------------------------------------------
  FONT_PATH               = "assets/font.ttf",
  FONT_SIZE_TITLE         = 54,
  FONT_SIZE_SUB           = 24,

  -- Trail & path sparkles ------------------------------------------
  TRAIL_LENGTH            = 26,
  TRAIL_FADE              = 0.94,
  PATH_SPARKLE_RATE       = 32,    -- per second
  PATH_SPARKLES_PER       = 3,

  -- Letter reveal & motion -----------------------------------------
  LETTER_FADE_SPEED       = 8.0,
  LETTER_SLIDE_SPEED      = 18.0,  -- slide spawn -> target
  SPRING = { k=32, d=10, start=1.25 }, -- scale spring after reveal

  -- Title sheen (masked by glyphs via stencil) ----------------------
  SHEEN_ENABLED           = false,
  SHEEN_DELAY_AFTER_TITLE = 0.25,
  SHEEN_SWEEPS            = 2,
  SHEEN_TIME_PER_SWEEP    = 0.9,
  SHEEN_ANGLE             = -20,
  SHEEN_WIDTH             = 140,
  SHEEN_ALPHA             = 0.18,

  -- Text twinkles ---------------------------------------------------
  TEXT_TWINKLES_MAX       = 8,
  TEXT_TWINKLE_RATE       = 0.35,

  -- Colors ----------------------------------------------------------
  STAR_COLOR              = {0.95, 0.74, 0.25},
  STAR_HIGHLIGHT          = {1.00, 0.96, 0.70},
  TRAIL_COLOR             = {1.00, 0.92, 0.76},
  TEXT_COLOR              = {0.96, 0.90, 0.78},
  RING_COLOR              = {1.00, 0.95, 0.80},
  SPARKLE_COLORS          = {
    {1.00, 1.00, 0.92},
    {1.00, 0.95, 0.76},
    {0.96, 0.86, 0.66},
  },

  BG_ALPHA                = 0.25,

  -- Fine alignment: nudge glyph spawn Y (px) if your font looks off --
  STAR_Y_SPAWN_OFFSET     = 0,
}

-----------------------------------------------------------------------
--  STATE
-----------------------------------------------------------------------
local S = {
  phase        = "waiting",
  timer        = 0,

  -- Star path state
  starActive   = false,
  elapsed      = 0,        -- seconds on current pass
  starX        = -50,
  starY        = 0,        -- drawn Y (bobbed)
  starAngle    = 0,
  starTarget   = "title",
  starS        = 0,        -- <-- arc length position along path (for catch-up)

  -- Path control points + arc-length LUT
  P0 = {x=0,y=0}, P1 = {x=0,y=0}, P2 = {x=0,y=0}, P3 = {x=0,y=0},
  path = { lut=nil, length=0 },

  -- Impact (rings only)
  impacted     = false,
  impactX      = 0, impactY = 0,
  rings        = {},

  -- Fade + trail + particles
  fade         = 0,
  trail        = {},
  sparkles     = {},
  sparkleTimer = 0,

  -- Text + metrics
  titleLetters = {}, subLetters = {},
  fTitle       = nil, fSub     = nil,
  mTitle       = nil, mSub     = nil,
  baseline     = { title=0, subtitle=0 },
  titleAllIn   = false,
  sheen        = {active=false, timer=0, pass=0},

  -- Strict one-by-one reveal index
  revealIdx    = { title = 1, subtitle = 1 },

  -- Twinkles
  twinkleCount = 0,

  onComplete   = nil,
}

-----------------------------------------------------------------------
--  UTILS
-----------------------------------------------------------------------
local unpack = unpack or table.unpack
local function rrange(a,b) return love.math.random()*(b-a)+a end
local function lerp(a,b,t) return a + (b-a)*t end
local function bezier3(p0,p1,p2,p3,t)
  local u=1-t; local tt=t*t; local uu=u*u; local uuu=uu*u; local ttt=tt*t
  return uuu*p0 + 3*uu*t*p1 + 3*u*tt*p2 + ttt*p3
end
local function bezier2d(P0,P1,P2,P3,t)
  return bezier3(P0.x,P1.x,P2.x,P3.x,t), bezier3(P0.y,P1.y,P2.y,P3.y,t)
end
local function resolveRowY(val, H)
  if val <= 1 then return H*val else return val end
end
local function randomColour() return CONFIG.SPARKLE_COLORS[love.math.random(#CONFIG.SPARKLE_COLORS)] end

-- Font metrics: ascent/descent/baseline
local function fontMetrics(font)
  local h = font:getHeight()
  local asc = font.getAscent and font:getAscent() or h*0.78
  local desc = font.getDescent and font:getDescent() or h*0.22
  return { asc=asc, desc=desc, base=asc, height=h }
end

-- Build per-letter data at a BASELINE y
local function lettersFor(text,font,cx,baselineY,metrics)
  local list, tw = {}, font:getWidth(text)
  local topY = baselineY - metrics.base      -- convert baseline -> top-left
  local x = cx - tw/2
  for i=1,#text do
    local ch=text:sub(i,i)
    local cw=font:getWidth(ch)
    if ch~=" " then
      list[#list+1] = {
        char=ch, width=cw,
        tx=x, ty=topY,     -- target top-left
        dx=x, dy=topY,     -- current draw pos (set on reveal)
        alpha=0, revealed=false, scale=0, vel=0
      }
    end
    x = x + cw
  end
  return list
end

local function allVisible(list)
  for _,g in ipairs(list) do if g.alpha<1 then return false end end
  return true
end

-----------------------------------------------------------------------
--  CONSTANT-SPEED BEZIER (arc-length LUT)
-----------------------------------------------------------------------
local function buildArcLUT(P0,P1,P2,P3, samples)
  local lut = {}
  local s = 0
  local prevx,prevy = bezier2d(P0,P1,P2,P3,0)
  lut[1] = { t=0, s=0, x=prevx, y=prevy }
  for i=1,samples do
    local t = i / samples
    local x,y = bezier2d(P0,P1,P2,P3,t)
    local dx,dy = x-prevx, y-prevy
    s = s + math.sqrt(dx*dx + dy*dy)
    lut[#lut+1] = { t=t, s=s, x=x, y=y }
    prevx,prevy = x,y
  end
  return lut, s
end

local function sampleAtS(lut, s)
  if s <= 0 then return lut[1].x, lut[1].y, 0 end
  local last = lut[#lut]
  if s >= last.s then return last.x, last.y, 1 end
  -- binary search in cumulative length
  local lo,hi = 1,#lut
  while lo+1 < hi do
    local mid = math.floor((lo+hi)/2)
    if lut[mid].s < s then lo = mid else hi = mid end
  end
  local a,b = lut[lo], lut[hi]
  local t = (s - a.s) / (b.s - a.s)
  local x = a.x + (b.x - a.x)*t
  local y = a.y + (b.y - a.y)*t
  local tt= a.t + (b.t - a.t)*t
  return x,y,tt
end

-- helper: index in LUT such that lut[i].s <= s < lut[i+1].s
local function lutIndexOfS(lut, s)
  if s <= 0 then return 1 end
  if s >= lut[#lut].s then return #lut-1 end
  local lo,hi = 1,#lut
  while lo+1 < hi do
    local mid = math.floor((lo+hi)/2)
    if lut[mid].s < s then lo = mid else hi = mid end
  end
  return lo
end

-----------------------------------------------------------------------
--  PARTICLES / RINGS
-----------------------------------------------------------------------
local function spawnPathSparkles(x,y)
  for _=1,CONFIG.PATH_SPARKLES_PER do
    local a  = love.math.random()*math.pi*2
    local sp = rrange(36,82)
    local c  = randomColour()
    S.sparkles[#S.sparkles+1] = {
      x=x+rrange(-4,4), y=y+rrange(-4,4),
      vx=math.cos(a)*sp, vy=math.sin(a)*sp,
      size=rrange(1,3), life=rrange(0.8,1.4), maxLife=1.4,
      color={c[1],c[2],c[3]},
    }
  end
end

-- 5 anchor points for twinkles
local ANCHORS = { {0,0}, {0.5,0}, {1,0}, {0,1}, {1,1} }
local function spawnGlyphTwinkle(glyph,fontHeight)
  if S.twinkleCount >= CONFIG.TEXT_TWINKLES_MAX then return end
  local ax,ay = unpack(ANCHORS[love.math.random(#ANCHORS)])
  local sx = glyph.tx + glyph.width*ax
  local sy = glyph.ty + fontHeight*ay
  local c  = randomColour()
  S.sparkles[#S.sparkles+1] = {
    x=sx, y=sy, vx=0, vy=0,
    size=rrange(1,2), life=0.5, maxLife=0.5,
    color={c[1],c[2],c[3]}, isTwinkle=true
  }
  S.twinkleCount = S.twinkleCount + 1
end

local function spawnImpactRings(x,y)
  S.rings = {}
  for i=1,CONFIG.IMPACT_RING_COUNT do
    S.rings[i] = {t=0, dur=CONFIG.IMPACT_RING_TIME*(1+0.06*(i-1)),
                  maxR=CONFIG.IMPACT_RING_MAX_R*(0.85+0.15*(i-1)) }
  end
end

local function spawnImpactBurst(x,y)
  for _=1,CONFIG.IMPACT_BURST_SPARKLES do
    local a = love.math.random()*math.pi*2
    local sp= rrange(120,260)
    local c = randomColour()
    S.sparkles[#S.sparkles+1] = {
      x=x, y=y, vx=math.cos(a)*sp, vy=math.sin(a)*sp,
      size=rrange(1.2,2.4), life=rrange(0.6,1.1), maxLife=1.1,
      color={c[1],c[2],c[3]},
    }
  end
end

-----------------------------------------------------------------------
--  TRAIL
-----------------------------------------------------------------------
local function updateTrail(x,y)
  S.trail[#S.trail+1] = {x=x,y=y,alpha=1}
  if #S.trail>CONFIG.TRAIL_LENGTH then table.remove(S.trail,1) end
  for _,p in ipairs(S.trail) do p.alpha=p.alpha*CONFIG.TRAIL_FADE end
end

-----------------------------------------------------------------------
--  STAR CONTROL / PATH SETUP
-----------------------------------------------------------------------
local function computePath(target)
  local w,h = love.graphics.getDimensions()

  -- Row centers from config (fraction or px), then convert to baselines
  local cyTitle = resolveRowY(CONFIG.TITLE_ROW_Y, h)
  local cySub   = resolveRowY(CONFIG.SUB_ROW_Y,   h)

  -- baselines: (center - halfHeight) + ascent
  S.baseline.title    = (cyTitle - S.mTitle.height*0.5) + S.mTitle.base
  S.baseline.subtitle = (cySub   - S.mSub.height  *0.5) + S.mSub.base

  local baseY = (target=="title") and
                (S.baseline.title    + (CONFIG.STAR_PATH_Y_OFFSET.title    or 0)) or
                (S.baseline.subtitle + (CONFIG.STAR_PATH_Y_OFFSET.subtitle or 0))

  local endY     = baseY + h*CONFIG.PATH_CTRL_OFFSET_Y
  local startX   = -50
  local endX     = w+50
  local cx       = w*CONFIG.IMPACT_XNORM

  S.P0.x, S.P0.y = startX, baseY
  S.P3.x, S.P3.y = endX,   baseY
  S.P1.x, S.P1.y = lerp(startX,cx,CONFIG.PATH_CTRL_OFFSET_X), endY
  S.P2.x, S.P2.y = lerp(endX,  cx,CONFIG.PATH_CTRL_OFFSET_X), endY

  S.path.lut, S.path.length = buildArcLUT(S.P0,S.P1,S.P2,S.P3, CONFIG.PATH_SAMPLES)
end

local function startStar(target)
  S.starActive = true
  S.starTarget = target
  S.elapsed    = 0
  S.starAngle  = 0
  S.starS      = 0
  S.trail      = {}

  computePath(target)

  -- Initialize the star at the new path's start so the first frame
  -- doesn't sweep across the whole screen and reveal letters early.
  local x0, yLine0 = sampleAtS(S.path.lut, 0)
  local bob0 = 0 -- math.sin(0) == 0, but kept for clarity
  S.starX = x0
  S.starY = yLine0 + bob0
end

-----------------------------------------------------------------------
--  LOAD
-----------------------------------------------------------------------
function Startup.load()
  local w,h = love.graphics.getDimensions()
  S.fTitle = love.graphics.newFont(CONFIG.FONT_PATH, CONFIG.FONT_SIZE_TITLE)
  S.fSub   = love.graphics.newFont(CONFIG.FONT_PATH, CONFIG.FONT_SIZE_SUB)

  S.mTitle = fontMetrics(S.fTitle)
  S.mSub   = fontMetrics(S.fSub)

  -- Use initial path setup to compute baselines, then build letters
  computePath("title")
  computePath("subtitle")

  S.titleLetters = lettersFor("CONSTELLATION MEMORIES", S.fTitle, w/2, S.baseline.title,    S.mTitle)
  S.subLetters   = lettersFor("The stars are coming out across the sky", S.fSub, w/2, S.baseline.subtitle, S.mSub)

  S.phase, S.timer = "waiting",0
  S.starActive = false
  S.fade = 0
  S.impactX = w*CONFIG.IMPACT_XNORM
  S.impactY = S.baseline.title
  S.impacted = false
  S.rings = {}
  S.sparkles, S.twinkleCount = {},0
  S.sheen = {active=false, timer=0, pass=0}
  S.revealIdx.title, S.revealIdx.subtitle = 1, 1
end

-----------------------------------------------------------------------
--  UPDATE
-----------------------------------------------------------------------
function Startup.update(dt)
  S.timer = S.timer + dt

  -- Phases
  if     S.phase=="waiting"   and S.timer>=CONFIG.TITLE_DELAY
  then S.phase="title";    startStar("title")

  elseif S.phase=="title"     and not S.starActive
  then S.phase="subtitle"; startStar("subtitle"); S.revealIdx.subtitle = 1

  elseif S.phase=="subtitle"  and not S.starActive
  then S.phase="linger";   S.timer=0

  elseif S.phase=="linger"    and S.timer>=CONFIG.COMPLETION_DELAY
  then S.phase="fade";     S.timer=0

  elseif S.phase=="fade" then
    S.fade = math.min(1, S.timer / CONFIG.FADE_OUT_TIME)
    if S.fade>=1 and S.onComplete then S.phase="finished"; S.onComplete() end
  end

  -- Star motion (constant-speed along LUT)
  if S.starActive then
    local prevx    = S.starX
    local prevS    = S.starS or 0

    S.elapsed = S.elapsed + dt
    local p = math.min(1, S.elapsed / CONFIG.STAR_SPEED_T)
    local s = p * S.path.length
    S.starS = s

    local x, yLine = sampleAtS(S.path.lut, s)
    -- micro-bob around the baseline path (use normalized progress p)
    local bob = math.sin(p * math.pi * 4) * CONFIG.STAR_BOB_AMPLITUDE
    local y   = yLine + bob

    S.starX, S.starY = x, y
    S.starAngle = S.starAngle + CONFIG.STAR_SPIN_SPEED*dt
    updateTrail(x,y)

    -- list/metrics for current pass
    local list, idxKey, metrics, fH
    if S.starTarget=="title" then
      list, idxKey, metrics, fH = S.titleLetters, "title", S.mTitle, S.fTitle:getHeight()
    else
      list, idxKey, metrics, fH = S.subLetters,   "subtitle", S.mSub,   S.fSub:getHeight()
    end

    -------------------------------------------------------------------
    -- CATCH-UP REVEAL: reveal ALL glyphs whose centers lie between
    -- prevx and x this frame. Compute exact spawn Y at the crossing by
    -- solving along the LUT segment and re-apply the bob at that s.
    -------------------------------------------------------------------
    local left  = math.min(prevx or -math.huge, x)
    local right = math.max(prevx or -math.huge, x)
    local eps   = 0.0001

    local function yAtCross(centerX, sA, sB)
      if sB < sA then sA, sB = sB, sA end
      local lut = S.path.lut
      local i0  = lutIndexOfS(lut, sA)
      local i1  = math.min(#lut-1, lutIndexOfS(lut, sB)+1)
      for i=i0, i1 do
        local a, b = lut[i], lut[i+1]
        -- clamp to [sA,sB] segment
        if b.s >= sA and a.s <= sB then
          if (a.x - centerX)*(b.x - centerX) <= 0 then
            local tseg = (centerX - a.x) / (b.x - a.x)
            tseg = math.max(0, math.min(1, tseg))
            local yline = a.y + (b.y - a.y) * tseg
            local scross= a.s + (b.s - a.s) * tseg
            local pnorm = scross / S.path.length
            local bobc  = math.sin(pnorm * math.pi * 4) * CONFIG.STAR_BOB_AMPLITUDE
            return yline + bobc
          end
        end
      end
      return nil
    end

    local i = S.revealIdx[idxKey]
    while i and list[i] do
      local g = list[i]
      local center = g.tx + g.width*0.5
      if center <= right + 0.5 and center >= left - 0.5 then
        -- compute exact Y at crossing (fallback to current starY)
        local yCross = yAtCross(center, prevS, s) or S.starY
        g.revealed = true
        g.scale, g.vel = CONFIG.SPRING.start, 0
        g.dx = center - g.width*0.5
        g.dy = (yCross - metrics.base) + (CONFIG.STAR_Y_SPAWN_OFFSET or 0)
        spawnPathSparkles(center, yCross)
        i = i + 1
        S.revealIdx[idxKey] = i
      else
        break
      end
    end

    -- impact center (title pass only) – rings only
    if (not S.impacted) and S.starTarget=="title" then
      local cx = S.impactX
      if (prevx < cx and x >= cx) or math.abs(x-cx) < 2.0 then
        S.impacted = true
        -- compute impactY via LUT at X=cx for visual accuracy on hiccups
        local yImpact = yAtCross(cx, prevS, s) or y
        S.impactY  = yImpact
        spawnImpactRings(cx,yImpact)
        spawnImpactBurst(cx,yImpact)
      end
    end

    -- path sparkles along flight
    S.sparkleTimer = S.sparkleTimer + dt
    if S.sparkleTimer >= 1/CONFIG.PATH_SPARKLE_RATE then
      spawnPathSparkles(x,y); S.sparkleTimer = 0
    end

    -- end of pass
    if p >= 1 then S.starActive=false end
  end

  -- Per-glyph fade + slide-to-target + spring scale + twinkles
  local function glyphUpdate(list,fontH)
    for _,g in ipairs(list) do
      if g.revealed then
        g.dx = g.dx + (g.tx - g.dx) * math.min(1, dt*CONFIG.LETTER_SLIDE_SPEED)
        g.dy = g.dy + (g.ty - g.dy) * math.min(1, dt*(CONFIG.LETTER_SLIDE_SPEED*0.6))
        if g.alpha < 1 then g.alpha = math.min(1, g.alpha + dt*CONFIG.LETTER_FADE_SPEED) end
        -- damped spring to 1
        local k,d = CONFIG.SPRING.k, CONFIG.SPRING.d
        local x = (g.scale - 1)
        local a = -k*x - d*g.vel
        g.vel = g.vel + a*dt
        g.scale = math.max(0.8, g.scale + g.vel*dt)
        -- twinkles once fully visible
        if g.alpha==1 and S.twinkleCount<CONFIG.TEXT_TWINKLES_MAX then
          if love.math.random() < CONFIG.TEXT_TWINKLE_RATE*dt then
            spawnGlyphTwinkle(g,fontH)
          end
        end
      end
    end
  end
  glyphUpdate(S.titleLetters,S.fTitle:getHeight())
  glyphUpdate(S.subLetters,S.fSub:getHeight())

  -- Title sheen activation
  if CONFIG.SHEEN_ENABLED and (not S.sheen.active) and (not S.starActive)
     and (S.phase=="subtitle" or S.phase=="linger") then
    if (not S.titleAllIn) and allVisible(S.titleLetters) then
      S.titleAllIn = true
      S.sheen.active = true
      S.sheen.timer = -CONFIG.SHEEN_DELAY_AFTER_TITLE
      S.sheen.pass = 0
    end
  end
  if S.sheen.active then
    S.sheen.timer = S.sheen.timer + dt
    if S.sheen.timer >= CONFIG.SHEEN_TIME_PER_SWEEP then
      S.sheen.timer = 0
      S.sheen.pass  = S.sheen.pass + 1
      if S.sheen.pass >= CONFIG.SHEEN_SWEEPS then
        S.sheen.active = false
      end
    end
  end

  -- Impact rings
  for i=#S.rings,1,-1 do
    local r=S.rings[i]; r.t = r.t + dt
    if r.t >= r.dur then table.remove(S.rings,i) end
  end

  -- Sparkles
  for i=#S.sparkles,1,-1 do
    local s=S.sparkles[i]
    s.x=s.x+s.vx*dt; s.y=s.y+s.vy*dt
    s.vx,s.vy=s.vx*0.95,s.vy*0.95
    s.life=s.life-dt
    if s.life<=0 then
      if s.isTwinkle then S.twinkleCount=S.twinkleCount-1 end
      table.remove(S.sparkles,i)
    end
  end
end

-----------------------------------------------------------------------
--  DRAW PRIMS
-----------------------------------------------------------------------
local function drawStar(x,y,r,angle)
  local body=CONFIG.STAR_COLOR; local hi=CONFIG.STAR_HIGHLIGHT
  love.graphics.push(); love.graphics.translate(x,y); love.graphics.rotate(angle)
  love.graphics.setColor(body); love.graphics.circle("fill",0,0,r)
  love.graphics.setColor(hi[1],hi[2],hi[3],0.5); love.graphics.circle("fill",0,0,r*0.52)
  love.graphics.setColor(1,1,1,0.30); love.graphics.circle("fill",0,0,r*0.20)
  love.graphics.setColor(1,0.88,0.45,0.16)
  local spikeL=r*1.55; local spikeW=math.max(0.8,r*0.18)
  for i=0,7 do
    local a=i*math.pi/4; local ca,sa=math.cos(a),math.sin(a)
    local tipX,tipY=ca*spikeL, sa*spikeL
    local b1x,b1y=-sa*spikeW*0.5, ca*spikeW*0.5
    local b2x,b2y= sa*spikeW*0.5,-ca*spikeW*0.5
    love.graphics.polygon("fill",tipX,tipY,b1x,b1y,b2x,b2y)
  end
  love.graphics.pop()
end

local function drawTrail()
  for i,p in ipairs(S.trail) do
    local r=CONFIG.STAR_SIZE*0.85*p.alpha*(i/#S.trail)
    love.graphics.setColor(CONFIG.TRAIL_COLOR[1],CONFIG.TRAIL_COLOR[2],CONFIG.TRAIL_COLOR[3],p.alpha*0.6)
    love.graphics.circle("fill",p.x,p.y,r)
  end
end

local function drawGlyphs(list,font)
  love.graphics.setFont(font)
  for _,g in ipairs(list) do
    if g.alpha>0 then
      love.graphics.push()
      local fh = font:getHeight()
      love.graphics.translate(g.dx + g.width*0.5, g.dy + fh*0.5)
      love.graphics.scale(g.scale,g.scale)
      love.graphics.translate(-(g.dx + g.width*0.5), -(g.dy + fh*0.5))
      love.graphics.setColor(CONFIG.TEXT_COLOR[1],CONFIG.TEXT_COLOR[2],CONFIG.TEXT_COLOR[3],g.alpha)
      love.graphics.print(g.char,g.dx,g.dy)
      love.graphics.pop()
    end
  end
end

-- draws a diagonal additive band, masked to current stencil
local function drawSheenBand(cx,cy,w,h,angleDeg,width,alpha)
  love.graphics.push("all")
  love.graphics.setBlendMode("add","premultiplied")
  love.graphics.translate(cx,cy)
  love.graphics.rotate(math.rad(angleDeg))
  love.graphics.setColor(1,1,1,alpha)
  love.graphics.rectangle("fill", -w, -width*0.5, w*2, width)
  love.graphics.pop()
end

-- Stencil from final glyph shapes so sheen only appears over title letters
local function titleStencil(list,font,fn)
  love.graphics.stencil(function()
    love.graphics.setColor(1,1,1,1)
    love.graphics.setFont(font)
    for _,g in ipairs(list) do
      if g.alpha>0.99 then
        love.graphics.print(g.char, g.tx, g.ty)
      end
    end
  end, "replace", 1, false)
  love.graphics.setStencilTest("equal", 1)
  fn()
  love.graphics.setStencilTest()
end

-----------------------------------------------------------------------
--  DRAW
-----------------------------------------------------------------------
function Startup.draw()
  local w,h=love.graphics.getDimensions()

  -- Background panel
  love.graphics.setColor(0,0,0,CONFIG.BG_ALPHA*(1-S.fade))
  love.graphics.rectangle("fill",0,0,w,h)

  -- TEXT first (so the star paints over / ahead of it)
  drawGlyphs(S.titleLetters,S.fTitle)
  drawGlyphs(S.subLetters,S.fSub)

  -- Title sheen (masked to final glyph positions), still under the star
  if CONFIG.SHEEN_ENABLED and S.sheen.active then
    local t = math.max(0, S.sheen.timer / CONFIG.SHEEN_TIME_PER_SWEEP)
    local bandX = lerp(-w*0.3, w*1.3, t)
    local bandCY = (S.baseline.title - S.mTitle.base) + S.mTitle.height*0.5
    titleStencil(S.titleLetters, S.fTitle, function()
      drawSheenBand(bandX, bandCY, w, h, CONFIG.SHEEN_ANGLE, CONFIG.SHEEN_WIDTH, CONFIG.SHEEN_ALPHA*(1-S.fade))
    end)
  end

  -- Trail + star
  if S.starActive then
    drawTrail()
    drawStar(S.starX,S.starY,CONFIG.STAR_SIZE,S.starAngle)
  end

  -- Impact rings
  for _,r in ipairs(S.rings) do
    local k = math.max(0, math.min(1, r.t / r.dur))
    local radius = r.maxR * k
    local a = (1-k) * 0.55
    love.graphics.setLineWidth(1.6)
    love.graphics.setColor(CONFIG.RING_COLOR[1],CONFIG.RING_COLOR[2],CONFIG.RING_COLOR[3], a*(1-S.fade))
    love.graphics.circle("line", S.impactX, S.impactY, radius)
  end

  -- Sparkles
  for _,s in ipairs(S.sparkles) do
    local a=(s.life/s.maxLife)*(1-S.fade)
    love.graphics.setColor(s.color[1],s.color[2],s.color[3],a)
    love.graphics.circle("fill",s.x,s.y,s.size*a)
    local cs=s.size*2*a; love.graphics.setLineWidth(1)
    love.graphics.line(s.x-cs,s.y,s.x+cs,s.y)
    love.graphics.line(s.x,s.y-cs,s.x,s.y+cs)
  end

  -- Fade to black
  love.graphics.setColor(0,0,0,S.fade)
  love.graphics.rectangle("fill",0,0,w,h)
end

-----------------------------------------------------------------------
--  PUBLIC API
-----------------------------------------------------------------------
function Startup.isFinished()          return S.phase=="finished" end
function Startup.setOnComplete(cb)     S.onComplete=cb end
function Startup.skip()                S.phase="fade"; S.timer=CONFIG.FADE_OUT_TIME end
function Startup.keypressed(k)         if k=="space" or k=="return" or k=="escape" then Startup.skip() end end

return Startup
