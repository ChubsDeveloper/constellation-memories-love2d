-- links.lua
local U = require("core.utils")

local L = {}
local links, linkSet = {}, {}

-- viewport cache
local screenW, screenH = 0, 0
local function refreshViewport()
  screenW, screenH = love.graphics.getWidth(), love.graphics.getHeight()
end

-- --- keying helpers -------------------------------------------------
local function key(a, b)
  local sa, sb = tostring(a), tostring(b)
  if sa > sb then sa, sb = sb, sa end
  return sa .. "|" .. sb
end

local function rebuild()
  linkSet = {}
  for _, Lk in ipairs(links) do
    linkSet[key(Lk.a, Lk.b)] = true
  end
end

local function normalizeLink(Lk)
  local a, b = Lk.a, Lk.b
  return {
    a = a, b = b,
    aKey = tostring(a), bKey = tostring(b),
    t = Lk.t or 1
  }
end

-- Try both string and numeric keys; tolerate whatever idToStar used.
local function findStar(idToStar, idStr, idRaw)
  return idToStar[idStr]
      or idToStar[idRaw]
      or idToStar[tonumber(idStr)]
      or idToStar[tostring(idRaw)]
end

-- ----------------- Load / mutate API -----------------
function L.load(initial, MemoryStore)
  links = {}
  for i = 1, #initial do
    links[i] = normalizeLink(initial[i])
  end
  rebuild()
  if MemoryStore and MemoryStore.saveLinks then
    MemoryStore.saveLinks(links)
  end
end

function L.has(a, b)
  return linkSet[key(a, b)]
end

function L.add(a, b, MemoryStore)
  if not a or not b or a == b then return end
  local k = key(a, b)
  if linkSet[k] then return end
  table.insert(links, normalizeLink({ a = a, b = b, t = 0 }))
  linkSet[k] = true
  if MemoryStore and MemoryStore.saveLinks then
    MemoryStore.saveLinks(links)
  end
end

function L.remove(a, b, MemoryStore)
  local k = key(a, b)
  for i = #links, 1, -1 do
    if key(links[i].a, links[i].b) == k then
      table.remove(links, i)
    end
  end
  linkSet[k] = nil
  if MemoryStore and MemoryStore.saveLinks then
    MemoryStore.saveLinks(links)
  end
end

function L.removeAllFor(id)
  local kstr = tostring(id)
  for i = #links, 1, -1 do
    local Lk = links[i]
    if Lk.aKey == kstr or Lk.bKey == kstr then
      table.remove(links, i)
    end
  end
  rebuild()
end

-- ----------------- Draw helpers -----------------
local function length(ax, ay, bx, by)
  local dx, dy = bx - ax, by - ay
  return math.sqrt(dx * dx + dy * dy)
end

local function segmentsFor(ax, ay, bx, by, CONFIG)
  local base = CONFIG.LINK_SEGMENTS or 24
  local len  = length(ax, ay, bx, by)
  local minSeg = math.max(6, math.floor(base * 0.4))
  local maxSeg = base
  local scaleLen = math.min(1, len / 420)
  return math.floor(minSeg + (maxSeg - minSeg) * scaleLen)
end

local function cullLink(ax, ay, bx, by)
  refreshViewport()
  local pad = 12
  local minx = math.min(ax, bx) - pad
  local maxx = math.max(ax, bx) + pad
  local miny = math.min(ay, by) - pad
  local maxy = math.max(ay, by) + pad
  return (maxx < 0) or (minx > screenW) or (maxy < 0) or (miny > screenH)
end

local function drawSegmented(ax, ay, bx, by, c1, c2, lineAlpha, lineW, haloAlpha, haloW, CONFIG)
  if cullLink(ax, ay, bx, by) then return end

  -- halo (single line)
  love.graphics.setLineWidth(haloW)
  love.graphics.setColor(1, 0.96, 0.75, haloAlpha)
  love.graphics.line(ax, ay, bx, by)

  -- segmented gradient
  love.graphics.setLineWidth(lineW)
  local n = segmentsFor(ax, ay, bx, by, CONFIG)
  local invN = 1 / n
  local dx, dy = (bx - ax) * invN, (by - ay) * invN
  local r1, g1, b1 = c1[1], c1[2], c1[3]
  local r2, g2, b2 = c2[1], c2[2], c2[3]

  local sx, sy = ax, ay
  for i = 0, n - 1 do
    local ex, ey = sx + dx, sy + dy
    local midt = (i + 0.5) * invN
    local rc = r1 + (r2 - r1) * midt
    local gc = g1 + (g2 - g1) * midt
    local bc = b1 + (b2 - b1) * midt
    love.graphics.setColor(rc, gc, bc, lineAlpha)
    love.graphics.line(sx, sy, ex, ey)
    sx, sy = ex, ey
  end
end

local function drawGradientLink(A, B, p, CONFIG)
  p = p or 1
  local bx, by = U.lerp(A.x, B.x, p), U.lerp(A.y, B.y, p)
  local c1, c2 = A.style.color, B.style.color
  local hot = (A.hovered or B.hovered) and CONFIG.LINK_HOVER_BOOST or 0

  drawSegmented(
    A.x, A.y, bx, by,
    c1, c2,
    CONFIG.LINK_LINE_ALPHA + hot,
    CONFIG.LINK_WIDTH,
    CONFIG.LINK_BASE_ALPHA + hot * 0.4,
    CONFIG.LINK_HALO_WIDTH,
    CONFIG
  )

  -- endpoints
  love.graphics.setColor(c1[1], c1[2], c1[3], 0.6 + hot)
  love.graphics.circle("fill", A.x, A.y, 1.6)
  if p >= 1 then
    love.graphics.setColor(c2[1], c2[2], c2[3], 0.6 + hot)
    love.graphics.circle("fill", B.x, B.y, 1.6)
  end
end

-- ----------------- Runtime -----------------
function L.update(dt, idToStar, sparkles, CONFIG, flux, spawnSparkle)
  for _, Lk in ipairs(links) do
    if Lk.t < 1 then
      local prev = Lk.t
      Lk.t = math.min(1, Lk.t + dt * CONFIG.LINK_ANIM_SPEED)
      if prev < 1 and Lk.t >= 1 then
        local dst = findStar(idToStar, Lk.bKey, Lk.b)
        if dst then
          local surf = (dst.style.radius or dst.radius) * (dst.scale or 1)
          spawnSparkle(sparkles, CONFIG, dst.x, dst.y, CONFIG.LINK_SPARKLE_COUNT, dst.style.color, surf)
          local base = dst.targetScale or 1
          flux.to(dst, CONFIG.LINK_BOUNCE_IN_DUR, { scale = base + CONFIG.LINK_BOUNCE_SCALE }):ease("quartout")
              :after(dst, CONFIG.LINK_BOUNCE_OUT_DUR, { scale = base }):ease("backout")
        end
      end
    end
  end
end

function L.draw(idToStar, CONFIG)
  if #links == 0 then return end
  for _, Lk in ipairs(links) do
    local A = findStar(idToStar, Lk.aKey, Lk.a)
    local B = findStar(idToStar, Lk.bKey, Lk.b)
    if A and B then
      drawGradientLink(A, B, Lk.t or 1, CONFIG)
    end
  end
end

function L.drawPlaceholder(A, mx, my, CONFIG)
  drawSegmented(
    A.x, A.y, mx, my,
    A.style.color, { 1, 1, 1 },
    0.55, CONFIG.LINK_WIDTH,
    0.15, CONFIG.LINK_HALO_WIDTH,
    CONFIG
  )
  if not cullLink(A.x, A.y, mx, my) then
    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.circle("fill", mx, my, 2.0)
  end
end

return L
