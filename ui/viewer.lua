-- ui/viewer.lua — memory card with single background + top-right tag + image lightbox
local Viewer = {}

local Common = require("ui.common")

-- ========= State =========
local memory, isVisible, alpha = nil, false, 0
local starX, starY = 0, 0
local cardX, cardY = 0, 0
local cardW, cardH = 420, 160
local appearScale = 0.95
local orbiters = {}
local linkEdit, linkDelete, linkImages = nil, nil, nil
local hoverEdit, hoverDelete, hoverImages = false, false, false
local confirmDelete = false
local lastStarStyle = nil

-- Gallery state
local galleryOpen = false
local galleryIndex = 1
local imageCache, thumbCache = {}, {}
local galleryError = nil
local THUMB_H = 76

-- ========= Theme =========
local THEME = {
  cardBgOuter = {0.10, 0.10, 0.15, 0.92},  -- outer plate
  cardBorder  = {0.95, 0.85, 0.55, 0.75},
  cardBorderW = 1.4,
  cardRadius  = 14,
  pad         = 16,
  lineGap     = 8,
  maxWidthPct = 0.65,
  ringW       = 1.2,
  ringR1      = 58,
  ringR2      = 84,

  galleryDim   = {0,0,0,0.86},
  galleryCard  = {0.10,0.10,0.14,0.95},
  galleryBorder= {1,1,1,0.25},
  navHot       = {1,1,1,0.85},
  navCold      = {1,1,1,0.50},
  closeCold    = {1,0.7,0.7,0.70},
  closeHot     = {1,0.7,0.7,1.00},
  textSoft     = {0.9,0.92,1.0,0.9},

  subtitle     = {0.85,0.88,1.0,0.80},

  -- Tag chip (top-right)
  tagBg        = {1,1,1,0.10},
  tagText      = {1,1,1,0.85},
  tagPadX      = 8,
  tagH         = 22,
  tagGap       = 8,
}

-- Accent derived from star color
local accent = {0.95, 0.74, 0.25}
local accentHalo1, accentHalo2 = {1,1,1,0.28}, {1,1,1,0.12}
local accentBorder, accentConnector, accentOrb = {1,1,1,0.75}, {1,1,1,0.55}, {1,1,1,0.85}

-- ========= Cached text & canvas =========
local cachedWrapLines = nil
local cachedWrapW = 0
local cachedTitle = ""
local cachedSubtitle = ""
local cachedTag = ""
local cachedBody = ""
local cardCanvas, cardCanvasW, cardCanvasH = nil, 0, 0
local cardDirty = true  -- rebuild when true

-- ========= Utils =========
local function mix(a,b,t) return a + (b - a) * t end
local function clamp01(v) return (v < 0 and 0) or (v > 1 and 1) or v end

local function setAccentFromColor(c)
  accent = { c[1] or 1, c[2] or 1, c[3] or 1 }
  local light = { mix(accent[1],1,0.35), mix(accent[2],1,0.35), mix(accent[3],1,0.35) }
  accentHalo1 = { light[1], light[2], light[3], 0.28 }
  accentHalo2 = { light[1], light[2], light[3], 0.12 }
  accentBorder    = { mix(accent[1],1,0.15), mix(accent[2],1,0.15), mix(accent[3],1,0.15), 0.75 }
  accentConnector = { mix(accent[1],1,0.05), mix(accent[2],1,0.05), mix(accent[3],1,0.05), 0.55 }
  accentOrb       = { mix(accent[1],1,0.20), mix(accent[2],1,0.20), mix(accent[3],1,0.20), 0.85 }
end

local function normalizeColor(c)
  if type(c) ~= "table" then return 0.95,0.74,0.25 end
  local r = c.r or c[1] or 1
  local g = c.g or c[2] or 1
  local b = c.b or c[3] or 1
  if r > 1 or g > 1 or b > 1 then r, g, b = r/255, g/255, b/255 end
  return clamp01(r), clamp01(g), clamp01(b)
end

local function deepcopy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k,v in pairs(t) do out[k] = deepcopy(v) end
  return out
end

local function inside(mx,my,r) return r and mx>=r.x and mx<=r.x+r.w and my>=r.y and my<=r.y+r.h end

-- ========= Orbiters =========
local function initOrbiters()
  orbiters = {}
  local ORB_R_MIN, ORB_R_MAX = 40, 58
  local ORB_SZ_MIN, ORB_SZ_MAX = 1.2, 1.6
  for i = 1, 10 do
    orbiters[i] = {
      r = love.math.random() * (ORB_R_MAX - ORB_R_MIN) + ORB_R_MIN,
      a = love.math.random() * math.pi * 2,
      s = love.math.random() * (1.6 - 0.6) + 0.6,
      sz= love.math.random() * (ORB_SZ_MAX - ORB_SZ_MIN) + ORB_SZ_MIN,
    }
  end
end

local function updateOrbiters(dt)
  for i = 1, #orbiters do
    local o = orbiters[i]
    o.a = o.a + dt * o.s * 1.1
    local wobble = math.sin(o.a * 0.9 + o.s * 2.7) * 0.25
    o.r = math.max(40, math.min(58, o.r + wobble * dt * 16))
  end
end

-- ========= Images / Gallery helpers =========
local function imageKey(item)
  if type(item) == "string" then return item end
  if type(item) == "table" then return item.path or tostring(item) end
  return tostring(item)
end

local function loadImage(item)
  local key = imageKey(item)
  if imageCache[key] then return imageCache[key] end

  local img
  if type(item) == "string" then
    local ok; ok, img = pcall(love.graphics.newImage, item); if not ok then return nil, ("Failed to load: %s"):format(item) end
  elseif type(item) == "table" then
    if item.image and item.image.typeOf and item.image:typeOf("Image") then
      img = item.image
    elseif item.path then
      local ok2; ok2, img = pcall(love.graphics.newImage, item.path)
      if not ok2 then return nil, ("Failed to load: %s"):format(item.path) end
    elseif item.data and type(item.data)=="string" then
      local fileData = love.filesystem.newFileData(item.data, "memimg")
      img = love.graphics.newImage(fileData)
    else
      return nil, "Unsupported image entry"
    end
  else
    return nil, "Unsupported image entry"
  end

  local w, h = img:getWidth(), img:getHeight()
  imageCache[key] = { img=img, w=w, h=h }
  return imageCache[key]
end

local function getThumb(item)
  local key = imageKey(item)
  if thumbCache[key] then return thumbCache[key] end
  local slot, err = loadImage(item)
  if not slot then return nil, err end

  local w, h = slot.w, slot.h
  local scale = THUMB_H / h
  local tw = math.max(1, math.floor(w * scale))
  local ok, canvas = pcall(love.graphics.newCanvas, tw, THUMB_H)
  if not ok or not canvas then
    thumbCache[key] = { img=slot.img, w=slot.w, h=slot.h, scale=scale }
    return thumbCache[key]
  end

  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0,0,0,0)
  love.graphics.setColor(1,1,1,1)
  love.graphics.draw(slot.img, 0, 0, 0, scale, scale)
  love.graphics.setCanvas()
  love.graphics.pop()

  thumbCache[key] = { img=canvas, w=tw, h=THUMB_H, fromCanvas=true }
  return thumbCache[key]
end

local function drawImageFit(img, iw, ih, x, y, w, h)
  local sx = w / iw
  local sy = h / ih
  local s = math.min(sx, sy)
  local dw, dh = iw * s, ih * s
  local dx = x + (w - dw)/2
  local dy = y + (h - dh)/2
  love.graphics.draw(img, dx, dy, 0, s, s)
end

-- ========= Background helpers (tone-safe) =========
local SOLID_ALPHA        = 0.28   -- default for solid backgrounds
local GRAD_ALPHA_TOP     = 0.32   -- default gradient start alpha
local GRAD_ALPHA_BOTTOM  = 0.42   -- default gradient end alpha

-- Perceptual luminance (sRGB)
local function luminance(r, g, b)
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
end

-- For very bright colors, reduce alpha so text stays readable
local function tone_safe_alpha(r, g, b, base_alpha)
  local Y = luminance(r, g, b)
  if Y <= 0.70 then return base_alpha end
  -- Fade more as it gets brighter; clamp at ~60% of base
  local factor = 1.0 - (Y - 0.70) * 0.9  -- Y: 0.70..1.00 => factor ~1..0.19
  factor = math.max(0.60, math.min(1.0, factor))
  return base_alpha * factor
end

-- Gradient with per-vertex alpha (already tone-safe adjusted)
local function drawGradientRect(x, y, w, h, from, to)
  local fr = {from[1] or 1, from[2] or 1, from[3] or 1}
  local tr = {to[1]   or 1, to[2]   or 1, to[3]   or 1}

  local a1 = tone_safe_alpha(fr[0+1], fr[0+2], fr[0+3], GRAD_ALPHA_TOP)
  local a2 = tone_safe_alpha(tr[0+1], tr[0+2], tr[0+3], GRAD_ALPHA_BOTTOM)

  local verts = {
    {x,     y,     0,0, fr[1],fr[2],fr[3], a1},
    {x + w, y,     1,0, fr[1],fr[2],fr[3], a1},
    {x + w, y + h, 1,1, tr[1],tr[2],tr[3], a2},
    {x,     y + h, 0,1, tr[1],tr[2],tr[3], a2},
  }
  local ok, mesh = pcall(love.graphics.newMesh, verts, "fan", "static")
  if ok and mesh then
    love.graphics.draw(mesh)
  else
    local mixr = (fr[1] + tr[1]) * 0.5
    local mixg = (fr[2] + tr[2]) * 0.5
    local mixb = (fr[3] + tr[3]) * 0.5
    local a    = tone_safe_alpha(mixr, mixg, mixb, (GRAD_ALPHA_TOP + GRAD_ALPHA_BOTTOM) * 0.5)
    love.graphics.setColor(mixr, mixg, mixb, a)
    love.graphics.rectangle("fill", x, y, w, h)
  end
end

-- Single background fill for the card interior (fills the whole card)
local function drawCardBackgroundTint(bg, moodColor, w, h)
  local ix, iy = 0, 0
  local iw, ih = w, h

  if type(bg) == "table" and bg.kind == "color" and type(bg.color) == "table" then
    local r = bg.color[1] or 1
    local g = bg.color[2] or 1
    local b = bg.color[3] or 1
    local a = tone_safe_alpha(r, g, b, SOLID_ALPHA)
    love.graphics.setColor(r, g, b, a)
    love.graphics.rectangle("fill", ix, iy, iw, ih, THEME.cardRadius, THEME.cardRadius)
    return
  end

  if type(bg) == "table" and bg.kind == "gradient" and type(bg.from) == "table" and type(bg.to) == "table" then
    drawGradientRect(ix, iy, iw, ih, bg.from, bg.to)
    return
  end

  -- Fallback: mood tint
  local c = moodColor or {1,1,1}
  local a = tone_safe_alpha(c[1] or 1, c[2] or 1, c[3] or 1, SOLID_ALPHA)
  love.graphics.setColor(c[1] or 1, c[2] or 1, c[3] or 1, a)
  love.graphics.rectangle("fill", ix, iy, iw, ih, THEME.cardRadius, THEME.cardRadius)
end

-- Keep whichever bg was chosen; alpha is handled by the draw functions above
local function chooseBackground()
  local starC = (memory.style and memory.style.color) or {0.95,0.74,0.25}
  local sr,sg,sb = normalizeColor(starC)
  local default = { kind="color", color={sr,sg,sb, 1.0} }
  local bg = memory.background
  if not bg or bg == "default" then return default end
  return bg
end

local function drawCornerFiligree(x, y, w, h, r, c)
  love.graphics.setColor(c[1],c[2],c[3], (c[4] or 1))
  love.graphics.setLineWidth(1)
  local m=10
  -- TL
  love.graphics.line(x+m,y+r, x+m,y+m); love.graphics.line(x+r,y+m, x+m,y+m)
  -- TR
  love.graphics.line(x+w-m,y+r, x+w-m,y+m); love.graphics.line(x+w-r,y+m, x+w-m,y+m)
  -- BL
  love.graphics.line(x+m,y+h-r, x+m,y+h-m); love.graphics.line(x+r,y+h-m, x+m,y+h-m)
  -- BR
  love.graphics.line(x+w-m,y+h-r, x+w-m,y+h-m); love.graphics.line(x+w-r,y+h-m, x+w-m,y+h-m)
end

-- ========= Body/preview helpers =========
local function buildPreviewText(mem, maxChars)
  maxChars = maxChars or 480
  local chunks = {}

  if mem and mem.blocks and #mem.blocks > 0 then
    for _,b in ipairs(mem.blocks) do
      if b.type == "text" and b.text and b.text ~= "" then
        chunks[#chunks+1] = b.text
      elseif b.type == "quote" and b.text and b.text ~= "" then
        chunks[#chunks+1] = ("“%s”"):format(b.text)
      elseif b.type == "list" and b.items then
        for i=1,#b.items do chunks[#chunks+1] = "• " .. tostring(b.items[i]) end
      end
      if table.concat(chunks, "\n"):len() >= maxChars then break end
    end
  else
    if mem and mem.text and mem.text ~= "" then chunks[#chunks+1] = mem.text end
    if mem and mem.details and mem.details ~= "" then chunks[#chunks+1] = mem.details end
  end

  local s = table.concat(chunks, "\n")
  if #s > maxChars then s = s:sub(1, maxChars - 1) .. "…" end
  return s
end

local function firstTag(tags)
  if type(tags) == "string" and tags ~= "" then return tags end
  if type(tags) == "table" and #tags > 0 then return tostring(tags[1]) end
  return nil
end

-- Compact key for tag-list caching
local function tagsKey(tags)
  if type(tags) ~= "table" or #tags == 0 then return "" end
  local buf = {}
  for i = 1, #tags do buf[i] = tostring(tags[i]) end
  return table.concat(buf, "|")
end

-- Draw all tags as right-aligned chips on the title row.
-- Returns total width used by the chips (so title can avoid them).
local function drawTagsTopRight(tags, xRight, y, maxWidth)
  if type(tags) ~= "table" or #tags == 0 then return 0 end
  local font = love.graphics.getFont()
  local chipPadX, chipPadY = THEME.tagPadX, 4
  local gap = THEME.tagGap
  local h = THEME.tagH

  -- Measure from right to left until we run out of maxWidth
  local totalW = 0
  local widths = {}
  for i = #tags, 1, -1 do
    local t = tostring(tags[i])
    local w = math.min(font:getWidth(t) + chipPadX * 2, maxWidth) -- chip width
    local nextTotal = (totalW == 0) and w or (totalW + gap + w)
    if nextTotal > maxWidth then break end
    widths[#widths+1] = { idx = i, w = w, label = t }
    totalW = nextTotal
  end

  if totalW <= 0 then return 0 end

  -- Draw chips (still right->left)
  local cursorX = xRight - totalW
  for j = #widths, 1, -1 do
    local entry = widths[j]
    local x = cursorX
    local w = entry.w
    -- soft shadow
    love.graphics.setColor(0,0,0,0.20)
    love.graphics.rectangle("fill", x, y+1, w, h, 8, 8)
    -- body
    love.graphics.setColor(1,1,1,0.16)
    love.graphics.rectangle("fill", x, y, w, h, 8, 8)
    -- border
    love.graphics.setColor(1,1,1,0.28)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x, y, w, h, 8, 8)
    -- text
    love.graphics.setColor(1,1,1,0.92)
    love.graphics.print(entry.label, x + chipPadX, y + (h - font:getHeight())/2)

    cursorX = cursorX + w + gap
  end

  return totalW
end

-- Renders a single row of tag chips (used under the subtitle)
local function drawTagsLine(tags, x, y, maxW)
  if not tags or #tags == 0 then return 0 end
  local cx = x
  local lineH = THEME.tagH
  local font = love.graphics.getFont()
  for _, t in ipairs(tags) do
    local w = font:getWidth(t) + THEME.tagPadX * 2
    if cx + w > x + maxW then
      -- compact card: stop at one line
      break
    end
    love.graphics.setColor(THEME.tagBg)
    love.graphics.rectangle("fill", cx, y, w, lineH, 8, 8)
    love.graphics.setColor(THEME.tagText)
    love.graphics.print(t, cx + THEME.tagPadX, y + (lineH - font:getHeight())/2)
    cx = cx + w + THEME.tagGap
  end
  return lineH
end

-- ========= Card canvas rebuild =========
local function markCardDirty() cardDirty = true end

local function rebuildCardCanvasIfDirty()
  if not cardDirty or not memory then return end

  local xPad, yPad = THEME.pad, THEME.pad
  local wrapW = cardW - xPad*2

  -- Mood info (optional)
  local moodEmoji = ""
  local moodColor = nil
  if type(memory.moodData) == "table" then
    moodEmoji = memory.moodData.emoji or ""
    moodColor = memory.moodData.color
  end

  local title    = (memory.title or memory.label or "Memory")
  local subtitle = memory.subtitle or ""
  local preview  = buildPreviewText(memory)
  local tKey     = tagsKey(memory.tags)

  local shouldSkip =
    cachedPreviewLines and
    wrapW == cachedWrapW and
    cachedTitle == title and
    cachedSubtitle == subtitle and
    cachedMoodEmoji == moodEmoji and
    cachedTagsKey == tKey

  if not shouldSkip then
    cachedWrapW     = wrapW
    cachedTitle     = title
    cachedSubtitle  = subtitle
    cachedMoodEmoji = moodEmoji
    cachedTagsKey   = tKey
    local _, lines  = Common.fontBody:getWrap(preview, wrapW)
    cachedPreviewLines = lines
  end

  -- Height
  local h = yPad
  h = h + Common.fontTitle:getHeight() + THEME.lineGap * 0.75
  if subtitle ~= "" then
    h = h + Common.fontBody:getHeight() + THEME.lineGap * 0.75
  end
  h = h + (#cachedPreviewLines) * Common.fontBody:getHeight()
  h = h + yPad

  local minH = 160
  cardH = math.max(minH, h)

  if (not cardCanvas) or cardCanvasW ~= cardW or cardCanvasH ~= cardH then
    cardCanvas  = love.graphics.newCanvas(cardW, cardH)
    cardCanvasW, cardCanvasH = cardW, cardH
  end

  love.graphics.push("all")
  love.graphics.setCanvas({ cardCanvas, stencil = true })
  love.graphics.clear(0,0,0,0)

  -- Outer plate
  love.graphics.setColor(THEME.cardBgOuter[1],THEME.cardBgOuter[2],THEME.cardBgOuter[3],THEME.cardBgOuter[4] or 1)
  love.graphics.rectangle("fill", 0, 0, cardW, cardH, THEME.cardRadius, THEME.cardRadius)

  -- Inner background (now vivid)
  drawCardBackgroundTint(chooseBackground(), moodColor, cardW, cardH)

  -- Border + filigree
  love.graphics.setColor(accentBorder[1],accentBorder[2],accentBorder[3],(accentBorder[4] or 0.75))
  love.graphics.setLineWidth(THEME.cardBorderW)
  love.graphics.rectangle("line", 0, 0, cardW, cardH, THEME.cardRadius, THEME.cardRadius)
  drawCornerFiligree(0,0, cardW,cardH, THEME.cardRadius, accentBorder)

  -- Content
  local cursorY = yPad
  love.graphics.setFont(Common.fontTitle)
  love.graphics.setColor(1,1,1,1)

  -- Tags in top-right
  local tagWidth = 0
  if type(memory.tags) == "table" and #memory.tags > 0 then
    local tagsY = cursorY + math.max(0, (Common.fontTitle:getHeight() - THEME.tagH) * 0.5) - 2
    tagWidth = drawTagsTopRight(memory.tags, cardW - xPad, tagsY, math.floor(wrapW * 0.55))
  end

  -- Title (avoid overlapping tags)
  local titleText = (cachedMoodEmoji ~= "" and (cachedMoodEmoji .. "  ") or "") .. cachedTitle
  local titleW = wrapW - tagWidth - (tagWidth > 0 and 12 or 0)
  love.graphics.printf(titleText, xPad, cursorY, math.max(40, titleW), "left")
  cursorY = cursorY + Common.fontTitle:getHeight() + THEME.lineGap * 0.75

  -- Subtitle
  if cachedSubtitle ~= "" then
    love.graphics.setFont(Common.fontBody); love.graphics.setColor(THEME.subtitle)
    love.graphics.printf(cachedSubtitle, xPad, cursorY, wrapW, "left")
    cursorY = cursorY + Common.fontBody:getHeight() + THEME.lineGap * 0.75
  end

  -- Preview
  love.graphics.setFont(Common.fontBody); love.graphics.setColor(0.95,0.95,1,0.95)
  for i = 1, #cachedPreviewLines do
    love.graphics.print(cachedPreviewLines[i], xPad, cursorY)
    cursorY = cursorY + Common.fontBody:getHeight()
  end

  love.graphics.setCanvas()
  love.graphics.pop()

  cardDirty = false
end

-- ========= Public API =========
function Viewer.load() end
function Viewer.isVisible() return isVisible end
function Viewer.hide() isVisible=false; confirmDelete=false; galleryOpen=false end
function Viewer.getLastStyle() return lastStarStyle end

function Viewer.showMemory(data, sx, sy)
  memory = {
    id        = data.id,
    title     = data.title or data.label or "Memory",
    subtitle  = data.subtitle or "",
    text      = data.text or nil,          -- legacy support (unused if blocks present)
    details   = data.details or data.memory or nil,
    style     = data.style or data.star or {},
    tags      = data.tags or data.tag and {data.tag} or {},
    background= data.background,           -- nil/"default"/{kind="color"/"gradient",...}
    blocks    = data.blocks,
    images    = data.images or data.media or data.photos or nil,
  }

  starX, starY = sx or 0, sy or 0
  isVisible, alpha, appearScale = true, 0, 0.95
  galleryOpen, galleryIndex, galleryError = false, 1, nil

  -- Accent from star color
  local cr,cg,cb = normalizeColor((memory.style and memory.style.color) or {0.95,0.74,0.25})
  setAccentFromColor({cr,cg,cb})

  lastStarStyle = deepcopy(memory.style)

  local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
  local maxW = math.floor(sw * THEME.maxWidthPct)
  cardW = Common.clamp(cardW, 320, maxW)

  local prefX = starX + 140
  if prefX + cardW + 20 > sw then prefX = starX - 140 - cardW end
  local prefY = math.max(20, math.min(sy - 90, sh - 200))
  cardX, cardY = prefX, prefY

  initOrbiters()
  markCardDirty()
end

function Viewer.update(dt)
  if isVisible then
    alpha = math.min(1, alpha + dt * 10)
    appearScale = appearScale + (1 - appearScale) * math.min(1, dt * 10)
  else
    alpha = math.max(0, alpha - dt * 10)
  end

  updateOrbiters(dt)

  if not isVisible or alpha < 0.02 or galleryOpen then return end

  hoverEdit, hoverDelete, hoverImages = false, false, false
  if linkEdit and linkDelete then
    local mx,my = love.mouse.getPosition()
    hoverEdit   = (mx>=linkEdit.x   and mx<=linkEdit.x+linkEdit.w   and my>=linkEdit.y   and my<=linkEdit.y+linkEdit.h)
    hoverDelete = (mx>=linkDelete.x and mx<=linkDelete.x+linkDelete.w and my>=linkDelete.y and my<=linkDelete.y+linkDelete.h)
    if linkImages then
      hoverImages = (mx>=linkImages.x and mx<=linkImages.x+linkImages.w and my>=linkImages.y and my<=linkImages.y+linkImages.h)
    end
  end
end

-- ========= Gallery drawing =========
local function drawCornerFiligree(x, y, w, h, r, c, a)
  love.graphics.setColor(c[1], c[2], c[3], (c[4] or 1) * a)
  love.graphics.setLineWidth(1)
  local m = 10
  love.graphics.line(x + m, y + r,     x + m, y + m);     love.graphics.line(x + r,     y + m, x + m,     y + m)
  love.graphics.line(x + w - m, y + r, x + w - m, y + m); love.graphics.line(x + w - r, y + m, x + w - m, y + m)
  love.graphics.line(x + m, y + h - r, x + m, y + h - m); love.graphics.line(x + r,     y + h - m, x + m,     y + h - m)
  love.graphics.line(x + w - m, y + h - r, x + w - m, y + h - m); love.graphics.line(x + w - r, y + h - m, x + w - m, y + h - m)
end

local function drawGalleryOverlay()
  local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
  local a = alpha
  love.graphics.setColor(THEME.galleryDim[1],THEME.galleryDim[2],THEME.galleryDim[3],THEME.galleryDim[4]*a)
  love.graphics.rectangle("fill", 0,0, sw,sh)

  local margin = 32
  local panelX, panelY = margin, margin
  local panelW, panelH = sw - margin*2, sh - margin*2
  love.graphics.setColor(THEME.galleryCard[1],THEME.galleryCard[2],THEME.galleryCard[3],THEME.galleryCard[4]*a)
  love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 14,14)
  love.graphics.setColor(THEME.galleryBorder)
  love.graphics.setLineWidth(1.2)
  love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 14,14)

  if not (memory and memory.images and #memory.images>0) then
    love.graphics.setColor(THEME.textSoft)
    love.graphics.printf("No images.", panelX, panelY + panelH/2 - 10, panelW, "center")
    return
  end

  local current = memory.images[galleryIndex]
  local slot, err = loadImage(current)
  if not slot then galleryError = err or "Unable to load" else galleryError = nil end

  local thumbsH = THUMB_H + 24
  local mainX, mainY = panelX + 18, panelY + 18
  local mainW, mainH = panelW - 36, panelH - 36 - thumbsH

  if slot then
    love.graphics.setColor(1,1,1,1)
    drawImageFit(slot.img, slot.w, slot.h, mainX, mainY, mainW, mainH)
  else
    love.graphics.setColor(1,0.7,0.7,1)
    love.graphics.printf(galleryError or "Image error", mainX, mainY + mainH/2 - 10, mainW, "center")
  end

  local navW = 120
  local mx,my = love.mouse.getPosition()
  local leftRect  = { x=panelX,               y=panelY, w=navW,             h=panelH - thumbsH }
  local rightRect = { x=panelX+panelW-navW,   y=panelY, w=navW,             h=panelH - thumbsH }
  local overLeft  = inside(mx,my,leftRect)
  local overRight = inside(mx,my,rightRect)

  love.graphics.setColor( (overLeft and THEME.navHot or THEME.navCold) )
  love.graphics.printf("‹", leftRect.x, leftRect.y + leftRect.h/2 - 26, leftRect.w, "center")
  love.graphics.setColor( (overRight and THEME.navHot or THEME.navCold) )
  love.graphics.printf("›", rightRect.x, rightRect.y + rightRect.h/2 - 26, rightRect.w, "center")

  Viewer._navLeftRect  = leftRect
  Viewer._navRightRect = rightRect

  local closeW = 40
  local closeRect = { x=panelX+panelW-closeW-6, y=panelY+6, w=closeW, h=closeW }
  local overClose = inside(mx,my,closeRect)
  love.graphics.setColor(overClose and THEME.closeHot or THEME.closeCold)
  love.graphics.printf("×", closeRect.x, closeRect.y+6, closeRect.w, "center")
  Viewer._closeRect = closeRect

  local stripX, stripY = panelX + 18, panelY + panelH - thumbsH + 12
  local stripW, stripH = panelW - 36, THUMB_H
  love.graphics.setColor(1,1,1,0.08)
  love.graphics.rectangle("fill", stripX, stripY, stripW, stripH, 8,8)

  Viewer._thumbRects = {}
  local pad = 8
  local cursor = stripX + pad
  for i,entry in ipairs(memory.images) do
    local th, terr = getThumb(entry)
    local tw = th and th.w or (THUMB_H * 1.3)
    local rect = { x=cursor, y=stripY + (stripH - THUMB_H)/2, w=tw, h=THUMB_H, index=i }
    Viewer._thumbRects[#Viewer._thumbRects+1] = rect

    local selected = (i == galleryIndex)
    love.graphics.setColor(selected and accent[1] or 1, selected and accent[2] or 1, selected and accent[3] or 1, selected and 0.35 or 0.15)
    love.graphics.rectangle("fill", rect.x-2, rect.y-2, rect.w+4, rect.h+4, 6,6)
    love.graphics.setColor(1,1,1,0.8)

    if th and th.img then
      love.graphics.draw(th.img, rect.x, rect.y)
    else
      love.graphics.setColor(1,1,1,0.2)
      love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 6,6)
      love.graphics.setColor(1,0.8,0.8,0.8)
      love.graphics.printf(terr and "!" or "?", rect.x, rect.y + rect.h/2 - 8, rect.w, "center")
    end

    cursor = cursor + tw + pad
    if cursor > stripX + stripW - 40 then break end
  end

  drawCornerFiligree(panelX, panelY, panelW, panelH, 14, THEME.galleryBorder, 1)
end

-- ========= Drawing =========
function Viewer.draw()
  if not isVisible or alpha <= 0.02 or not memory then return end

  -- halos & orbiters
  love.graphics.setLineWidth(THEME.ringW)
  love.graphics.setColor(accentHalo1[1],accentHalo1[2],accentHalo1[3],accentHalo1[4]*alpha)
  love.graphics.circle("line", starX, starY, THEME.ringR1)
  love.graphics.setColor(accentHalo2[1],accentHalo2[2],accentHalo2[3],accentHalo2[4]*alpha)
  love.graphics.circle("line", starX, starY, THEME.ringR2)

  love.graphics.setColor(accentOrb[1],accentOrb[2],accentOrb[3], (accentOrb[4] or 1)*alpha)
  for i=1,#orbiters do
    local o=orbiters[i]
    love.graphics.circle("fill", starX + math.cos(o.a)*o.r, starY + math.sin(o.a)*(o.r*0.75), o.sz)
  end

  love.graphics.setLineWidth(2.0)
  love.graphics.setColor(accentConnector[1],accentConnector[2],accentConnector[3],(accentConnector[4] or 1)*alpha)
  love.graphics.line(starX, starY, cardX + 18, cardY + 18)

  -- rebuild cached card if needed
  rebuildCardCanvasIfDirty()

  -- draw cached card with transform/alpha modulation
  love.graphics.push()
  love.graphics.translate(cardX+cardW*0.5, cardY+cardH*0.5)
  love.graphics.scale(appearScale, appearScale)
  love.graphics.translate(-(cardX+cardW*0.5), -(cardY+cardH*0.5))
  love.graphics.setColor(1,1,1, alpha)
  love.graphics.draw(cardCanvas, cardX, cardY)
  love.graphics.pop()

  -- Links (dynamic)
  local linkAlphaBase, linkAlphaHot = 0.45*alpha, 0.95*alpha
  love.graphics.setFont(Common.fontBody)
  local hasImages = (memory.images and #memory.images > 0)

  local txtImages = hasImages and (("images (%d)"):format(#memory.images)) or nil
  local wImages = txtImages and Common.fontBody:getWidth(txtImages) or 0
  local txtEdit, txtDelete = "edit", "delete"
  local wEdit  = Common.fontBody:getWidth(txtEdit)
  local wDelete= Common.fontBody:getWidth(txtDelete)
  local gap = 14

  local totalW = wEdit + gap + wDelete
  if txtImages then totalW = totalW + gap + wImages end

  local lx  = cardX + cardW - totalW - 12
  local ly  = cardY + cardH + 8

  if txtImages then
    local over = hoverImages
    love.graphics.setColor(accentBorder[1],accentBorder[2],accentBorder[3], over and linkAlphaHot or linkAlphaBase)
    love.graphics.print(txtImages, lx, ly)
    if over then love.graphics.line(lx, ly+Common.fontBody:getHeight(), lx+wImages, ly+Common.fontBody:getHeight()) end
    linkImages = { x=lx, y=ly, w=wImages, h=Common.fontBody:getHeight() }
    lx = lx + wImages + gap
  else
    linkImages = nil
  end

  love.graphics.setColor(accentBorder[1],accentBorder[2],accentBorder[3], hoverEdit and linkAlphaHot or linkAlphaBase)
  love.graphics.print(txtEdit, lx, ly)
  if hoverEdit then love.graphics.line(lx, ly+Common.fontBody:getHeight(), lx+wEdit, ly+Common.fontBody:getHeight()) end
  linkEdit = { x=lx, y=ly, w=wEdit, h=Common.fontBody:getHeight() }

  local lxd = lx + wEdit + gap
  love.graphics.setColor(1,0.6,0.6, hoverDelete and linkAlphaHot or linkAlphaBase)
  love.graphics.print(txtDelete, lxd, ly)
  if hoverDelete then love.graphics.line(lxd, ly+Common.fontBody:getHeight(), lxd+wDelete, ly+Common.fontBody:getHeight()) end
  linkDelete = { x=lxd, y=ly, w=wDelete, h=Common.fontBody:getHeight() }

  if galleryOpen then
    drawGalleryOverlay()
  end
end

-- ========= Input =========
function Viewer.mousepressed(x, y, button)
  if not isVisible or not memory then return nil end

  if galleryOpen then
    if Viewer._closeRect and inside(x,y,Viewer._closeRect) then galleryOpen=false; return nil end
    if Viewer._navLeftRect and inside(x,y,Viewer._navLeftRect) then
      if memory.images and #memory.images>0 then
        galleryIndex = (galleryIndex - 2) % #memory.images + 1
      end
      return nil
    end
    if Viewer._navRightRect and inside(x,y,Viewer._navRightRect) then
      if memory.images and #memory.images>0 then
        galleryIndex = (galleryIndex) % #memory.images + 1
      end
      return nil
    end
    if Viewer._thumbRects then
      for _,r in ipairs(Viewer._thumbRects) do
        if inside(x,y,r) then galleryIndex = r.index; return nil end
      end
    end
    galleryOpen = false
    return nil
  end

  if linkImages and inside(x,y,linkImages) then
    if memory.images and #memory.images>0 then
      galleryIndex = 1; galleryOpen = true
    end
    return nil
  end

  if linkEdit and inside(x,y,linkEdit) then
    confirmDelete = false
    return { action="edit", memory=memory, sx=starX, sy=starY }
  end

  if linkDelete and inside(x,y,linkDelete) then
    if not confirmDelete then
      confirmDelete = true
    else
      isVisible = false; confirmDelete = false
      return { action="delete", id = memory.id }
    end
    return nil
  end

  isVisible = false; confirmDelete = false
  return nil
end

function Viewer.keypressed(key)
  if not isVisible then return end
  if key=="escape" then
    if galleryOpen then galleryOpen=false else Viewer.hide() end
    return
  end
  if galleryOpen and memory and memory.images and #memory.images>0 then
    if key=="left" then galleryIndex = (galleryIndex - 2) % #memory.images + 1 end
    if key=="right" then galleryIndex = (galleryIndex) % #memory.images + 1 end
  end
end

function Viewer.mousereleased() end
function Viewer.mousemoved() end
function Viewer.wheelmoved(dx, dy) if not galleryOpen then return end end
function Viewer.keyreleased() end
function Viewer.textinput() end

-- ========= External helpers =========
function Viewer.addImagesToCurrentMemory(list)
  if not memory then return end
  memory.images = memory.images or {}
  for _,v in ipairs(list or {}) do table.insert(memory.images, v) end
end

function Viewer.getLastStyle() return lastStarStyle end

-- If window resizes, card width clamp may change => recalc & rebuild
function Viewer.onResize()
  if not memory then return end
  local sw = love.graphics.getWidth()
  local maxW = math.floor(sw * THEME.maxWidthPct)
  local newW = Common.clamp(cardW, 320, maxW)
  if newW ~= cardW then cardW = newW; cardDirty = true end
end

return Viewer
