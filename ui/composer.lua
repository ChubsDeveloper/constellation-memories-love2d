-- ui/composer.lua — composer with preset Tags + Background picker (color/gradient), using ui/simple_picker
local Composer = {}

local Common       = require("ui.common")
local Media        = require("media_store")
local SimplePicker = require("ui.simple_picker")

-- prefer global utf8 if provided; else fall back to require
local utf8 = utf8 or require("utf8")

local cursorIBeam = love.mouse.getSystemCursor and love.mouse.getSystemCursor("ibeam") or nil
local cursorArrow = love.mouse.getSystemCursor and love.mouse.getSystemCursor("arrow") or nil
local caretBlinkOn = true
local caretBlinkTimer = 0

-- ===== Optional StarMap + moonshine =====
local StarMap
local function tryRequireStarMap()
  if StarMap ~= nil then return StarMap end
  local ok, mod = pcall(require, "star_map")
  StarMap = (ok and type(mod) == "table") and mod or false
  return StarMap or nil
end

local moonshine do
  local ok, mod = pcall(require, "moonshine")
  if ok then moonshine = mod end
end

-- ===== State =====
local open, alpha = false, 0
local posX, posY = 0, 0
local mode, editId = "create", nil
local onSave, onCancel = nil, nil

-- Text fields (Title, Subtitle, Memory)
local fields = {
  { name="Title",    value="", max=120,  multiline=false, rect=nil, hover=false, scroll=0, caret=1, selecting=false },
  { name="Subtitle", value="", max=240,  multiline=false, rect=nil, hover=false, scroll=0, caret=1, selecting=false },
  { name="Memory",   value="", max=8000, multiline=true,  rect=nil, hover=false, scroll=0, caret=1, selecting=false },
}
local focused = 1

-- Preset tags (chips under Memory)
local PRESET_TAGS = {
  "love","trip","family","friends","song","movie","food","place",
  "funny","sad","hope","milestone","habit","gift","photo","random"
}
local selectedTagsSet = {}   -- set[tag]=true
local tagChipRects = {}      -- for hit-testing

-- Background picker (swatches under tags)
local SOLID_SWATCHES = {
  {1.00,0.78,0.90,0.22}, {0.70,0.85,1.00,0.22}, {0.55,0.95,0.75,0.22},
  {1.00,0.90,0.40,0.22}, {1.00,0.65,0.50,0.22}, {0.60,0.55,1.00,0.22},
  {0.95,0.74,0.25,0.22}, {0.90,0.10,0.10,0.22}, {0.25,0.85,0.60,0.22},
  {0.50,0.40,0.80,0.22}, {1.00,0.70,0.45,0.22}, {0.10,0.12,0.18,0.28},
}
local GRADIENT_SWATCHES = {
  { from={0.95,0.70,0.30,0.18}, to={0.90,0.10,0.10,0.28} },
  { from={0.45,0.70,1.00,0.18}, to={0.25,0.40,0.90,0.28} },
  { from={0.55,0.95,0.75,0.18}, to={0.20,0.75,0.55,0.28} },
  { from={1.00,0.78,0.90,0.18}, to={0.60,0.55,1.00,0.28} },
  { from={1.00,0.90,0.40,0.18}, to={1.00,0.65,0.50,0.28} },
  { from={0.50,0.40,0.80,0.18}, to={0.10,0.12,0.18,0.30} },
}
-- selected background: "default" | {kind="color", color={...}} | {kind="gradient",from=...,to=...}
local selectedBackground = "default"
local swatchRects = {}  -- { kind="default"/"color"/"gradient", index=?, rect={...} }

-- Dynamic style controls (star look)
local style   = {}
local sliders = {}
local enums   = {}
local currentForm = nil -- NOTE: 'form' selection hidden/disabled; keep nil to use default star

-- Preserve *exact* incoming star style to avoid wiping unknown fields on save
local originalStyle = {}

-- Controls viewport (right column for style)
local viewport = { x=0, y=0, w=0, h=0, scroll=0, contentH=0 }

-- Buttons
local btnSave, btnCancel = nil, nil
local hoverSave, hoverCancel = false, false

-- Slider drag state
local dragging = { active=false, idx=nil }

-- Preview FX cache
local previewFX
local useFX = true

-- Images (staged vs existing)
local existingImages = {}
local stagedImages   = {}
local removedExistingSet = {}
local imagesStrip = { y=0, h=92, pad=10, thumbH=72, scroll=0, rect=nil, leftRect=nil, rightRect=nil }
local thumbRects, delRects = {}, {}
local btnPaste, btnBrowse = nil, nil

-- ===== Utils =====
local function clamp(x,a,b) if x<a then return a elseif x>b then return b else return x end end
local function inside(mx,my,r) return r and mx>=r.x and mx<=r.x+r.w and my>=r.y and my<=r.y+r.h end
local function shallowCopy(t) local o={}; for k,v in pairs(t or {}) do o[k]=v end; return o end

local function arraysEqual(a,b)
  if not a or not b then return false end
  if #a ~= #b then return false end
  for i=1,#a do if a[i] ~= b[i] then return false end end
  return true
end

local function normalizeColor(c)
  if type(c)~="table" then return 1,1,1,1 end
  local r = c.r or c[1] or 1
  local g = c.g or c[2] or 1
  local b = c.b or c[3] or 1
  local a = c[4] or 1
  if r>1 or g>1 or b>1 or a>1 then r,g,b,a = r/255, g/255, b/255, a/255 end
  return r,g,b,a
end

local function backgroundEquals(a,b)
  if a=="default" or b=="default" then return a==b end
  if type(a)~="table" or type(b)~="table" then return false end
  if a.kind ~= b.kind then return false end
  if a.kind=="color" then
    local ar,ag,ab,aa = normalizeColor(a.color or {})
    local br,bg,bb,ba = normalizeColor(b.color or {})
    return math.abs(ar-br)<1e-6 and math.abs(ag-bg)<1e-6 and math.abs(ab-bb)<1e-6 and math.abs(aa-ba)<1e-6
  elseif a.kind=="gradient" then
    return arraysEqual(a.from or {}, b.from or {}) and arraysEqual(a.to or {}, b.to or {})
  end
  return false
end

-- ===== UTF-8 + text editing helpers =========================================
local function u8len(s) return (utf8.len(s or "")) or 0 end
local function u8sub_bytes(s, i, j) return s:sub(i, j) end

-- 1-based char indices (inclusive); supports j < i => empty
local function u8sub(s, i, j)
  local l = u8len(s)
  i = math.max(1, math.min(i or 1, l + 1))
  j = (j == nil) and l or math.max(0, math.min(j, l))
  if j < i then return "" end
  local bi = utf8.offset(s, i) or (#s + 1)
  local bj = (utf8.offset(s, j + 1) or (#s + 1)) - 1
  return u8sub_bytes(s, bi, bj)
end

-- substring over [a, b) using 1-based caret positions (end-exclusive)
local function u8sub_between(s, a, b)
  local l = u8len(s)
  a = math.max(1, math.min(a or 1, l + 1))
  b = math.max(1, math.min(b or (l + 1), l + 1))
  if b <= a then return "" end
  return u8sub(s, a, b - 1)
end

local function fieldLen(f) return u8len(f.value or "") end
local function hasSelection(f) return f and f.selStart and f.selEnd and f.selEnd > f.selStart end
local function normalizeSel(f)
  if not f.selStart or not f.selEnd then
    f.selStart = f.caret or 1; f.selEnd = f.caret or 1
  end
  if f.selStart > f.selEnd then f.selStart, f.selEnd = f.selEnd, f.selStart end
end
local function clearSelection(f) f.anchor = f.caret; f.selStart = f.caret; f.selEnd = f.caret end
local function setCaret(f, pos, keepAnchor)
  local l = fieldLen(f)
  f.caret = math.max(1, math.min(pos or 1, l + 1))
  if not keepAnchor then f.anchor = f.caret end
  f.selStart, f.selEnd = f.caret, f.caret
  f._followCaret = true -- one-shot follow
end
local function extendSelectionTo(f, pos)
  local l = fieldLen(f)
  pos = math.max(1, math.min(pos or 1, l + 1))
  f.selStart = f.anchor or (f.caret or pos)
  f.selEnd = pos
  normalizeSel(f)
  f.caret = f.selEnd
  f._followCaret = true -- one-shot follow
end

local function deleteSelection(f)
  if not hasSelection(f) then return false end
  local s = f.value or ""
  local before = u8sub_between(s, 1, f.selStart)
  local after  = u8sub_between(s, f.selEnd, u8len(s) + 1)
  f.value = before .. after
  setCaret(f, u8len(before) + 1)
  return true
end

local function insertTextAtCaret(f, txt, isMultiline)
  if not isMultiline then txt = (txt or ""):gsub("[\r\n]+", " ") end
  deleteSelection(f)
  local s = f.value or ""
  local maxChars = f.max or 1e9
  local curLen = u8len(s)
  local addLen = u8len(txt or "")
  if addLen > (maxChars - curLen) then
    txt = u8sub(txt or "", 1, math.max(0, maxChars - curLen))
  end
  local before = u8sub_between(s, 1, f.caret)
  local after  = u8sub_between(s, f.caret, u8len(s) + 1)
  f.value = before .. (txt or "") .. after
  setCaret(f, u8len(before .. (txt or "")) + 1)
end

local function backspaceChar(f)
  if deleteSelection(f) then return true end
  if (f.caret or 1) <= 1 then return false end
  local s = f.value or ""
  local left  = u8sub_between(s, 1, f.caret - 1)
  local right = u8sub_between(s, f.caret, u8len(s) + 1)
  f.value = left .. right
  setCaret(f, u8len(left) + 1)
  return true
end

local function deleteChar(f)
  if deleteSelection(f) then return true end
  local s = f.value or ""
  if (f.caret or 1) > u8len(s) then return false end
  local left  = u8sub_between(s, 1, f.caret)
  local right = u8sub_between(s, f.caret + 1, u8len(s) + 1)
  f.value = left .. right
  setCaret(f, u8len(left) + 1)
  return true
end

-- word boundaries: "word" ~= contiguous non-space; simple and effective
local function wordBoundaryLeft(s, caret)
  local left = u8sub_between(s, 1, caret - 1)
  if left == "" then return 1 end
  left = left:gsub("%s+$", "")
  local cut = left:gsub("[^%s]+$", "")
  return u8len(cut) + 1
end
local function wordBoundaryRight(s, caret)
  local l = u8len(s)
  local right = u8sub_between(s, caret, l + 1)
  if right == "" then return l + 1 end
  right = right:gsub("^%s+", "")
  right = right:gsub("^[^%s]+", "")
  return (l - u8len(right)) + 1
end

local function ctrlBackspace(f)
  if deleteSelection(f) then return true end
  local s = f.value or ""
  local newPos = wordBoundaryLeft(s, f.caret or 1)
  if newPos >= (f.caret or 1) then return false end
  f.value = u8sub_between(s, 1, newPos) .. u8sub_between(s, f.caret, u8len(s) + 1)
  setCaret(f, newPos)
  return true
end
local function ctrlDelete(f)
  if deleteSelection(f) then return true end
  local s = f.value or ""
  local newPos = wordBoundaryRight(s, f.caret or 1)
  if newPos <= (f.caret or 1) then return false end
  f.value = u8sub_between(s, 1, f.caret) .. u8sub_between(s, newPos, u8len(s) + 1)
  setCaret(f, f.caret)
  return true
end

local function moveCaretChars(f, delta, withShift)
  local l = fieldLen(f)
  local np = math.max(1, math.min((f.caret or 1) + delta, l + 1))
  if withShift then extendSelectionTo(f, np) else setCaret(f, np) end
end
local function moveCaretWord(f, dir, withShift)
  local s  = f.value or ""
  local np = (dir < 0) and wordBoundaryLeft(s, f.caret or 1) or wordBoundaryRight(s, f.caret or 1)
  if withShift then extendSelectionTo(f, np) else setCaret(f, np) end
end

local function moveCaretHomeEnd(f, toEnd, withShift)
  local dest = toEnd and (fieldLen(f) + 1) or 1
  if withShift then extendSelectionTo(f, dest) else setCaret(f, dest) end
end

-- Map caret <-> (line,offset) and keep caret visible for multiline (one-shot)
local function ensureCaretVisible(f, lines, viewH, padY, lineH)
  local idx = (f.caret or 1) - 1
  local acc, lineIndex = 0, 1
  for i = 1, #lines do
    local L = u8len(lines[i])
    if idx <= acc + L then lineIndex = i; break end
    acc = acc + L
  end
  local yTop = (lineIndex - 1) * lineH
  local viewTop = f.scroll or 0
  local innerH = viewH - 2 * padY
  if yTop < viewTop then
    f.scroll = math.max(0, yTop)
  elseif yTop + lineH > viewTop + innerH then
    f.scroll = math.max(0, yTop + lineH - innerH)
  end
end

-- From a mouse position into char index within the wrapped field
local function caretFromMouse(f, x, y, font, cw, padX, padY)
  local text = f.value or ""
  local _, lines = font:getWrap(text, cw)
  local lineH = font:getHeight()
  local localY = y - (f.rect.y + padY) + (f.scroll or 0)
  local line = math.floor(localY / lineH) + 1
  if line < 1 then line = 1 elseif line > #lines then line = #lines end
  local acc = 0
  for i = 1, line - 1 do acc = acc + u8len(lines[i]) end
  local lx = x - (f.rect.x + padX)
  if lx <= 0 then return acc + 1 end
  local s = lines[line] or ""
  local best = 0
  local wPrev = 0
  local chars = u8len(s)
  for c = 1, chars do
    local w = font:getWidth(u8sub(s, 1, c))
    if lx < (wPrev + w) * 0.5 then best = c - 1; break end
    wPrev = w
    best = c
  end
  return acc + best + 1
end

-- ===== Schema helpers (form-aware star style) =====
local function getSchemaFromStarMap(form)
  local sm = tryRequireStarMap(); if not sm then return nil end
  if type(sm.getStyleSchema) == "function" then
    local ok,res = pcall(sm.getStyleSchema, form)
    if not ok then ok,res = pcall(sm.getStyleSchema) end
    if ok and res then return res end
  end
  return sm and (sm.STYLE_SCHEMA or sm.StyleSchema)
end

local function normalizeSchema(schema)
  if type(schema) ~= "table" then return nil end
  local out = {}
  if #schema > 0 then
    for _,e in ipairs(schema) do if type(e)=="table" and e.key then out[#out+1] = e end end
  else
    for k,e in pairs(schema) do
      if type(e)=="table" then local c={ key=k }; for kk,v in pairs(e) do c[kk]=v end; out[#out+1]=c end
    end
    table.sort(out, function(a,b) return tostring(a.key) < tostring(b.key) end)
  end
  return (#out>0) and out or nil
end

local function seedDefaults(entries)
  style = style or {}
  for _,e in ipairs(entries) do
    if e.key=="color" then
      local d = e.default or {0.95,0.74,0.25}
      if not style.color then style.color = { d[1] or 1, d[2] or 1, d[3] or 1 } end
    elseif e.type=="enum" then
      if style[e.key]==nil then style[e.key]=e.default or (e.choices and e.choices[1]) or "" end
    elseif e.type=="bool" or e.type=="boolean" then
      if style[e.key]==nil then style[e.key]=(e.default==true) end
    else
      if style[e.key]==nil and e.default~=nil then style[e.key]=e.default end
    end
  end
  if not style.color then style.color={0.95,0.74,0.25} end
end

local function buildControls(entries)
  sliders, enums = {}, {}
  local function push(label,key,min,max,step,value)
    sliders[#sliders+1]={ label=label, key=key, min=min or 0, max=max or 1, step=step or 0.01, value=value }
  end
  for _,e in ipairs(entries) do
    if e.key=="color" then
      local c=style.color or {1,1,1}
      push("Red","color_r",0,1,0.005,c[1]); push("Green","color_g",0,1,0.005,c[2]); push("Blue","color_b",0,1,0.005,c[3])
    elseif e.type=="enum" then
      if e.key ~= "form" then
        enums[#enums+1]={ key=e.key,label=e.label or e.key,choices=e.choices or {},kind="enum",value=tostring(style[e.key] or e.default or ""),_chipRects={} }
      end
    elseif e.type=="bool" or e.type=="boolean" then
      enums[#enums+1]={ key=e.key,label=e.label or e.key,choices={"off","on"},kind="bool",value=(style[e.key] and "on" or "off"),_chipRects={} }
    else
      local val=style[e.key]; if e.type=="int" then val=math.floor((val or e.min or 0)+0.5) end
      push(e.label or e.key, e.key, e.min or 0, e.max or 1, e.step or 0.01, val or e.min or 0)
    end
  end
end

local function rebuildControls(seed)
  if type(seed)=="table" then
    for k,v in pairs(seed) do
      if k=="color" and type(v)=="table" then
        style.color = { v[1] or (style.color and style.color[1]) or 1,
                        v[2] or (style.color and style.color[2]) or 1,
                        v[3] or (style.color and style.color[3]) or 1 }
      else
        style[k] = (v==nil) and style[k] or v
      end
    end
  end

  local schema = normalizeSchema(getSchemaFromStarMap(nil))
  if schema then
    seedDefaults(schema)
    buildControls(schema)
  else
    style.radius = style.radius or 12
    style.glow   = style.glow or 1.2
    style.ringScale = style.ringScale or 1.7
    style.ringOpacity=style.ringOpacity or 0.25
    style.highlight=style.highlight or 1.0
    style.specSize = style.specSize or 0.18
    style.coreAlpha= style.coreAlpha or 1.0
    style.depth    = style.depth or 0.55
    style.rim      = style.rim or 0.45
    style.color    = style.color or {0.95,0.74,0.25}
    sliders = {
      {label="Star Size", key="radius", min=6, max=32, step=0.1, value=style.radius},
      {label="Overall Glow", key="glow", min=0.6, max=3, step=0.02, value=style.glow},
      {label="Outline Size", key="ringScale", min=1, max=3, step=0.02, value=style.ringScale},
      {label="Outline Opacity", key="ringOpacity", min=0, max=1, step=0.02, value=style.ringOpacity},
      {label="Centre Glow", key="highlight", min=0, max=2, step=0.02, value=style.highlight},
      {label="Centre Sparkle", key="specSize", min=0.05, max=0.6, step=0.01, value=style.specSize},
      {label="Core Opacity", key="coreAlpha", min=0.3, max=1.2, step=0.01, value=style.coreAlpha},
      {label="Edge Darken", key="depth", min=0, max=1, step=0.02, value=style.depth},
      {label="Edge Glow", key="rim", min=0, max=2, step=0.02, value=style.rim},
      {label="Red", key="color_r", min=0, max=1, step=0.005, value=style.color[1]},
      {label="Green", key="color_g", min=0, max=1, step=0.005, value=style.color[2]},
      {label="Blue", key="color_b", min=0, max=1, step=0.005, value=style.color[3]},
    }
    enums = {}
  end
end

-- ===== Image caches for already-staged images (virtual FS) =====
local thumbCache = {}
local imgCache   = {}

local function loadImage(saveRelPath)
  if imgCache[saveRelPath] then return imgCache[saveRelPath] end
  local data = love.filesystem.read(saveRelPath)
  local img
  if data then img = love.graphics.newImage(love.filesystem.newFileData(data, "memimg"))
  else
    local ok, im = pcall(love.graphics.newImage, saveRelPath)
    if ok then img = im end
  end
  if not img then return nil end
  local slot = { img=img, w=img:getWidth(), h=img:getHeight() }
  imgCache[saveRelPath] = slot
  return slot
end

local function getThumb(saveRelPath, thumbH)
  if thumbCache[saveRelPath] then return thumbCache[saveRelPath] end
  local slot = loadImage(saveRelPath); if not slot then return nil end
  local w,h = slot.w, slot.h
  local s = (thumbH or imagesStrip.thumbH) / h
  local tw = math.max(1, math.floor(w*s))
  local ok, cv = pcall(love.graphics.newCanvas, tw, math.floor(h*s))
  if not ok or not cv then
    thumbCache[saveRelPath] = { img=slot.img, passthrough=true, w=w, h=h }
    return thumbCache[saveRelPath]
  end
  love.graphics.push("all"); love.graphics.setCanvas(cv); love.graphics.clear(0,0,0,0)
  love.graphics.setColor(1,1,1,1); love.graphics.draw(slot.img, 0,0,0,s,s)
  love.graphics.setCanvas(); love.graphics.pop()
  thumbCache[saveRelPath] = { img=cv, w=cv:getWidth(), h=cv:getHeight() }
  return thumbCache[saveRelPath]
end

local function allImageEntries()
  local out = {}
  for _,p in ipairs(existingImages) do
    if not removedExistingSet[p] then out[#out+1] = { path=p, staged=false } end
  end
  for _,p in ipairs(stagedImages) do out[#out+1] = { path=p, staged=true } end
  return out
end

-- ===== Background picker helpers =====
local function drawGradientRect(x, y, w, h, cTop, cBottom)
  local verts = {
    {x,   y,   0,0,  cTop[1], cTop[2], cTop[3], cTop[4] or 1},
    {x+w, y,   1,0,  cTop[1], cTop[2], cTop[3], cTop[4] or 1},
    {x+w, y+h, 1,1,  cBottom[1], cBottom[2], cBottom[3], cBottom[4] or 1},
    {x,   y+h, 0,1,  cBottom[1], cBottom[2], cBottom[3], cBottom[4] or 1},
  }
  local mesh = love.graphics.newMesh(verts, "fan", "static")
  love.graphics.draw(mesh)
end

local function backgroundFromSwatch(kind, index)
  if kind == "default" then return "default" end
  if kind == "color" then
    local c = SOLID_SWATCHES[index]; if not c then return "default" end
    return { kind="color", color={c[1],c[2],c[3],c[4] or 0.22} }
  elseif kind == "gradient" then
    local g = GRADIENT_SWATCHES[index]; if not g then return "default" end
    return { kind="gradient", from=g.from, to=g.to }
  end
  return "default"
end

-- ===== Public API =====
function Composer.load() end
function Composer.isOpen() return open end

function Composer.openAt(x, y, seedStyle, cb)
  open, alpha = true, 0
  posX, posY = x, y
  mode, editId = "create", nil
  onSave, onCancel = cb and cb.onSave or nil, cb and cb.onCancel or nil

  for _,f in ipairs(fields) do
    f.value, f.scroll, f.caret, f.selecting = "", 0, 1, false
    f.selStart, f.selEnd, f.anchor = 1, 1, 1
    f._followCaret = false
  end
  focused = 1
  viewport.scroll = 0
  dragging.active, dragging.idx = false, nil

  originalStyle = shallowCopy(seedStyle or {})
  style         = shallowCopy(seedStyle or {})

  currentForm   = nil

  selectedTagsSet = {}
  selectedBackground = "default"
  tagChipRects, swatchRects = {}, {}

  existingImages, stagedImages = {}, {}
  removedExistingSet = {}
  Media.beginSession()
  imagesStrip.scroll = 0

  rebuildControls(style)

  if useFX and not previewFX then
    local sm = tryRequireStarMap()
    if sm and type(sm.getPreviewEffect)=="function" then
      local ok, fx = pcall(sm.getPreviewEffect); if ok and fx then previewFX = fx end
    elseif moonshine then
      local ok, chain = pcall(function()
        local ch = moonshine(moonshine.glow).chain(moonshine.vignette)
        ch.glow.strength = 4.5; ch.vignette.radius = 0.92; ch.vignette.opacity = 0.35; return ch
      end)
      if ok and chain then previewFX = chain end
    end
  end

  if love.keyboard and love.keyboard.setKeyRepeat then love.keyboard.setKeyRepeat(true) end
  if love.keyboard and love.keyboard.setTextInput then love.keyboard.setTextInput(true) end
end

function Composer.openForEdit(mem, sx, sy, cb)
  local seed = mem.style or mem.star or {}
  Composer.openAt(sx, sy, seed, cb)
  mode, editId = "edit", mem.id

fields[1].value = mem.label or mem.title or ""
fields[2].value = mem.subtitle or ""   -- ← no fallback to mem.text anymore
fields[3].value = (mem.memory or mem.details or mem.text or "")

  selectedTagsSet = {}
  if mem.tags and type(mem.tags)=="table" then
    for _,t in ipairs(mem.tags) do selectedTagsSet[tostring(t)] = true end
  end

  if mem.background then
    selectedBackground = mem.background
  else
    selectedBackground = "default"
  end

  for _,f in ipairs(fields) do
    f.scroll = 0
    f.caret = u8len(f.value or "") + 1
    f.selStart, f.selEnd, f.anchor = f.caret, f.caret, f.caret
    f.selecting = false
    f._followCaret = false
  end

  existingImages = {}
  local src = mem.images or mem.media or mem.photos
  if type(src)=="table" then for _,p in ipairs(src) do existingImages[#existingImages+1]=p end end
  stagedImages, removedExistingSet = {}, {}
  imagesStrip.scroll = 0

  rebuildControls(style)
end

function Composer.cancel()
  open = false
  love.keyboard.setTextInput(false)
  Media.discardSession()
  if cursorArrow then love.mouse.setCursor(cursorArrow) end
end

-- Helper: is any text field currently being drag-selected?
local function anyFieldSelecting()
  for _, f in ipairs(fields) do
    if f.selecting then return true end
  end
  return false
end

-- ===== Update / Draw =====
function Composer.update(dt)
  alpha = open and math.min(1, alpha + dt*3) or math.max(0, alpha - dt*3)

  -- blink caret
  caretBlinkTimer = (caretBlinkTimer or 0) + dt
  if caretBlinkTimer >= 0.5 then
    caretBlinkTimer = caretBlinkTimer - 0.5
    caretBlinkOn = not caretBlinkOn
  end

  -- import from SimplePicker
  if SimplePicker.didImport and SimplePicker.takeSelection and SimplePicker.didImport() then
    local picked = SimplePicker.takeSelection() or {}
    local already = {}
    for _,p in ipairs(stagedImages) do already[p] = true end
    for _,abs in ipairs(picked) do
      local rel = Media.stageImportAbs(abs)
      if rel and not already[rel] then
        already[rel] = true
        stagedImages[#stagedImages+1] = rel
      end
    end
    print(("[composer] imported %d item(s)"):format(#picked))
  end

  local mx,my = love.mouse.getPosition()
  hoverSave   = (btnSave   and mx>=btnSave.x   and mx<=btnSave.x+btnSave.w   and my>=btnSave.y   and my<=btnSave.y+btnSave.h) or false
  hoverCancel = (btnCancel and mx>=btnCancel.x and mx<=btnCancel.x+btnCancel.w and my>=btnCancel.y and my<=btnCancel.y+btnCancel.h) or false

  -- set I-beam when hovering any text field (only while composer is open)
  local overAnyField = false
  for _,f in ipairs(fields) do
    if f.hover then overAnyField = true break end
  end
  if overAnyField and cursorIBeam then
    love.mouse.setCursor(cursorIBeam)
  elseif cursorArrow then
    love.mouse.setCursor(cursorArrow)
  end
end

function Composer.draw()
  if alpha <= 0.001 then return end
  local a = alpha
  local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()

  -- Panel
  local margin = 14
  local panelW = math.min(1320, sw - margin*2)
  local panelH = math.min(1180, sh - margin*2)
  local px = (sw - panelW)/2
  local py = (sh - panelH)/2

  love.graphics.setColor(0,0,0,0.85*a); love.graphics.rectangle("fill", 0,0, sw,sh)
  love.graphics.setColor(0.10,0.10,0.15,0.95*a); love.graphics.rectangle("fill", px,py,panelW,panelH,16,16)
  love.graphics.setColor(1,0.88,0.45,0.75*a); love.graphics.setLineWidth(1.5); love.graphics.rectangle("line", px,py,panelW,panelH,16,16)

  -- Title
  local fontTitle = Common.fontTitle or love.graphics.getFont()
  love.graphics.setFont(fontTitle); love.graphics.setColor(1,1,1,a)
  love.graphics.print(mode=="edit" and "Edit Memory" or "Create Memory", px+18, py+16)

  -- Columns
  local fontBody = Common.fontBody or love.graphics.getFont()
  love.graphics.setFont(fontBody)
  local gutter = 18
  local leftW = math.floor(panelW * 0.56)
  local rightW = panelW - leftW - gutter*3
  local leftX = px + gutter
  local rightX = leftX + leftW + gutter
  local topY = py + 72

  -- LEFT: fields (Title, Subtitle, Memory)
  local fx, fw, fy = leftX, leftW, topY
  local heights = { 48, 48, 220 }
  for i,f in ipairs(fields) do
    love.graphics.setColor(1,1,1,0.8*a)
    love.graphics.print(f.name, fx, fy)

    local iy = fy + 24
    local h  = heights[i]
    f.rect = { x=fx, y=iy, w=fw, h=h }

    -- background
    love.graphics.setColor(0.13,0.13,0.18,0.95*a)
    love.graphics.rectangle("fill", fx,iy,fw,h,10,10)

    -- hover/focus
    local mx,my = love.mouse.getPosition()
    f.hover = (mx>=fx and mx<=fx+fw and my>=iy and my<=iy+h)
    local isFocus = (focused == i)

    -- focus highlight ring
    love.graphics.setLineWidth(isFocus and 2 or 1)
    local borderAlpha = (isFocus and 0.95 or (f.hover and 0.85 or 0.6)) * a
    love.graphics.setColor(1, 0.96, 0.70, borderAlpha)
    love.graphics.rectangle("line", fx,iy,fw,h,10,10)

    -- subtle focus fill so you see active field
    if isFocus then
      love.graphics.setColor(1,1,1,0.05*a)
      love.graphics.rectangle("fill", fx,iy,fw,h,10,10)
    end

    -- text + selection + caret
    local padX,padY=12,10
    local cw = fw - 2*padX - 10
    local textToWrap = f.value or ""
    local _, lines = fontBody:getWrap(textToWrap, cw)
    local lineH = fontBody:getHeight()
    local contentH = #lines * lineH
    local maxScroll = math.max(0, contentH - (h - 2*padY))
    f.scroll = clamp(f.scroll or 0, 0, maxScroll)

    love.graphics.setScissor(fx+padX, iy+padY, cw, h-2*padY)
    love.graphics.push()
    love.graphics.translate(0, -(f.scroll or 0))
    local baseY = iy + padY

    -- selection highlight (if any)
    if hasSelection(f) then
      local acc = 0
      for li=1,#lines do
        local line = lines[li]
        local L = u8len(line)
        local lineStart = acc + 1           -- inclusive
        local lineEndEx = acc + L + 1       -- exclusive
        local aSel = math.max(f.selStart or 1, lineStart)
        local bSel = math.min(f.selEnd   or 1, lineEndEx)
        if aSel < bSel then
          local leftCount = aSel - lineStart
          local selCount  = bSel - aSel
          local leftW = fontBody:getWidth(u8sub(line, 1, leftCount))
          local selW  = fontBody:getWidth(u8sub(line, 1, leftCount + selCount)) - leftW
          love.graphics.setColor(0.55,0.75,1.0,0.35*a)
          love.graphics.rectangle("fill", fx+padX + leftW, baseY + (li-1)*lineH, selW, lineH, 2,2)
        end
        acc = acc + L
      end
    end

    -- draw text
    love.graphics.setColor(1,1,1,a)
    local ycur = baseY
    for _,line in ipairs(lines) do
      love.graphics.print(line, fx+padX, ycur)
      ycur = ycur + lineH
    end

    -- caret (blinks)
    if isFocus and caretBlinkOn then
      local idx = (f.caret or 1) - 1
      local acc, cx, cy = 0, fx+padX, baseY
      for li=1,#lines do
        local line = lines[li]
        local L = u8len(line)
        if idx <= acc + L then
          local within = idx - acc
          cx = fx+padX + fontBody:getWidth(u8sub(line, 1, within))
          cy = baseY + (li-1)*lineH
          break
        end
        acc = acc + L
      end
      love.graphics.setColor(1,1,1,0.95*a)
      love.graphics.rectangle("fill", cx, cy, 2, lineH)
    end

    love.graphics.pop()
    love.graphics.setScissor()

    -- scrollbar (if needed)
    if maxScroll>0.5 then
      local trackX, trackY, trackH = fx+fw-8, iy+6, h-12
      love.graphics.setColor(0.22,0.22,0.26,0.65*a)
      love.graphics.rectangle("fill", trackX, trackY, 4, trackH, 2,2)
      local ratio = (h-2*padY)/contentH
      local thumbH = math.max(20, trackH * ratio)
      local thumbY = trackY + (trackH - thumbH) * ((f.scroll or 0)/math.max(1,maxScroll))
      love.graphics.setColor(0.75,0.72,0.60,0.65*a)
      love.graphics.rectangle("fill", trackX, thumbY, 4, thumbH, 2,2)
    end

    if isFocus and f.multiline and f._followCaret then
      ensureCaretVisible(f, lines, h, padY, lineH)
      f._followCaret = false
    end

    fy = fy + h + 28
  end

  -- compute once: if the user is drag-selecting text, suppress chip hovers
  local textDragging = anyFieldSelecting()

  -- LEFT: Preset Tags (chips) under Memory
  love.graphics.setColor(1,1,1,0.85*a); love.graphics.print("Tags", fx, fy)
  fy = fy + 28
  tagChipRects = {}
  do
    local chipPadX, chipPadY = 10, 6
    local chipGapX, chipGapY = 8, 10
    local lineH = fontBody:getHeight()
    local chipH = chipPadY*2 + lineH
    local x = fx
    local maxX = fx + fw
    for _,tag in ipairs(PRESET_TAGS) do
      local tw = fontBody:getWidth(tag)
      local chipW = math.min(tw + chipPadX*2, maxX - fx)
      if x + chipW > maxX then
        x = fx; fy = fy + chipH + chipGapY
      end
      local cy = fy
      local rect = { x=x, y=cy, w=chipW, h=chipH, tag=tag }
      tagChipRects[#tagChipRects+1] = rect

      local selected = selectedTagsSet[tag] == true
      local mx,my = love.mouse.getPosition()
      local hot = (not textDragging) and inside(mx,my,rect)
      love.graphics.setColor((selected and 0.26 or (hot and 0.22 or 0.18)), (selected and 0.26 or (hot and 0.22 or 0.18)), (selected and 0.30 or (hot and 0.26 or 0.22)), 0.95*a)
      love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 8,8)
      love.graphics.setColor(0.95,0.74,0.25,0.90*a); love.graphics.setLineWidth(1); love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 8,8)
      love.graphics.setColor(1,1,1,a); love.graphics.print(tag, rect.x + chipPadX, rect.y + chipPadY)

      x = x + chipW + chipGapX
    end
    fy = fy + chipH + chipGapY + 8
  end

  -- LEFT: Background picker (swatches)
  love.graphics.setColor(1,1,1,0.85*a); love.graphics.print("Background", fx, fy)
  fy = fy + 28
  swatchRects = {}
  do
    local swW, swH = 64, 40
    local gapX, gapY = 10, 10
    local x = fx
    local maxX = fx + fw

    -- inset, pixel-aligned border (doesn't bleed onto neighbors)
    local function drawInsetBorder(x0,y0,w0,h0, selected, alpha)
      love.graphics.push("all")
      love.graphics.setLineWidth(1)
      -- snap to pixel grid; draw fully inside the tile
      local inset = 1
      local bx = math.floor(x0) + 0.5 + inset
      local by = math.floor(y0) + 0.5 + inset
      local bw = math.floor(w0) - inset*2 - 1
      local bh = math.floor(h0) - inset*2 - 1
      love.graphics.setColor(1,1,1, (selected and 0.35 or 0.18) * alpha)
      love.graphics.rectangle("line", bx, by, bw, bh, 8,8)
      love.graphics.pop()
    end

    -- Default chip
    do
      local rect = { x=x, y=fy, w=swW, h=swH, kind="default", index=1 }
      local selected = (selectedBackground == "default")
      love.graphics.push("all")
      love.graphics.setColor(0.13,0.13,0.18,0.95*a)
      love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 8,8)
      love.graphics.setColor(1,1,1,0.75*a)
      love.graphics.printf("Default", rect.x, rect.y + swH/2 - fontBody:getHeight()/2, rect.w, "center")
      love.graphics.pop()
      drawInsetBorder(rect.x, rect.y, rect.w, rect.h, selected, a)
      swatchRects[#swatchRects+1] = rect
      x = x + swW + gapX
    end

    -- Solid colors
    for i,c in ipairs(SOLID_SWATCHES) do
      if x + swW > maxX then x = fx; fy = fy + swH + gapY end
      local rect = { x=x, y=fy, w=swW, h=swH, kind="color", index=i }
      love.graphics.push("all")
      love.graphics.setColor(c)
      love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 8,8)
      love.graphics.pop()
      local selected = (type(selectedBackground)=="table" and selectedBackground.kind=="color"
                        and backgroundEquals(selectedBackground, backgroundFromSwatch("color", i)))
      drawInsetBorder(rect.x, rect.y, rect.w, rect.h, selected, a)
      swatchRects[#swatchRects+1] = rect
      x = x + swW + gapX
    end

    -- Next row spacing
    x = fx; fy = fy + swH + gapY

    -- Gradients
    for i,g in ipairs(GRADIENT_SWATCHES) do
      if x + swW > maxX then x = fx; fy = fy + swH + gapY end
      local rect = { x=x, y=fy, w=swW, h=swH, kind="gradient", index=i }
      -- draw gradient clipped to rounded rect, and keep state local
      love.graphics.push("all")
      love.graphics.stencil(function()
        love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 8,8)
      end, "replace", 1)
      love.graphics.setStencilTest("equal", 1)
      drawGradientRect(rect.x, rect.y, rect.w, rect.h, g.from, g.to)
      love.graphics.setStencilTest()
      love.graphics.pop()

      local selected = (type(selectedBackground)=="table" and selectedBackground.kind=="gradient"
                        and backgroundEquals(selectedBackground, backgroundFromSwatch("gradient", i)))
      drawInsetBorder(rect.x, rect.y, rect.w, rect.h, selected, a)
      swatchRects[#swatchRects+1] = rect
      x = x + swW + gapX
    end

    fy = fy + swH + gapY + 6
  end

  -- RIGHT: star preview
  local pvX, pvY = rightX, topY
  local pvW = rightW
  local pvH = math.floor(math.min(360, math.max(260, sh * 0.30)))
  love.graphics.setColor(0.11,0.11,0.16,0.95*a); love.graphics.rectangle("fill", pvX,pvY,pvW,pvH,12,12)
  love.graphics.setColor(1,0.88,0.45,0.55*a); love.graphics.setLineWidth(1.2); love.graphics.rectangle("line", pvX, pvY, pvW, pvH, 12, 12)

  do
    local sm = tryRequireStarMap()
    local drawCenterX = pvX + pvW/2
    local drawCenterY = pvY + pvH/2 + 6
    local stylePreview = {}; for k,v in pairs(style) do stylePreview[k]=v end
    local previewScale = 1.0
    if sm and type(sm.getPreviewScaleHint)=="function" then
      local ok, hint = pcall(sm.getPreviewScaleHint, currentForm)
      if ok and type(hint)=="number" and hint>0 then previewScale = hint end
    end
    local function drawStar()
      -- IMPORTANT: reset tint
      love.graphics.setColor(1,1,1,1)
      if sm and type(sm.drawStarPreview)=="function" then
        local ok = pcall(sm.drawStarPreview, drawCenterX, drawCenterY, stylePreview, {
          with_particles = true, time = love.timer.getTime(), scale = previewScale, form  = currentForm,
        })
        if not ok then
          love.graphics.setColor(1,1,1,0.7*a); love.graphics.printf("Preview error", pvX+8, pvY+pvH/2-12, pvW-16, "center")
        end
      else
        love.graphics.setColor(1,1,1,0.7*a); love.graphics.printf("Needs star_map.drawStarPreview", pvX+8, pvY+pvH/2-12, pvW-16, "center")
      end
    end
    if useFX and previewFX and not (SimplePicker.isOpen and SimplePicker.isOpen()) then
      local ok = pcall(function() previewFX(drawStar) end)
      if not ok then drawStar() end
    else
      drawStar()
    end
  end

  -- Images header + actions
  local imgHeadY = pvY + pvH + 8
  local totalShown = #allImageEntries()
  local stagedCount = #stagedImages
  love.graphics.setColor(1,1,1,0.85*a)
  love.graphics.print(("Images (%d)"):format(totalShown), rightX, imgHeadY)
  love.graphics.setColor(1,1,1,0.55*a)
  love.graphics.print(("  – staged: %d"):format(stagedCount), rightX + 110, imgHeadY)

  local addLabel = "Add (paste)"
  local browseLabel = "Add (browse…)"
  local addW = fontBody:getWidth(addLabel)
  local browseW = fontBody:getWidth(browseLabel)
  local addH = fontBody:getHeight()
  local addY = imgHeadY
  local pvW_for_actions = rightW
  local addX = rightX + pvW_for_actions - (browseW + 18 + addW) - 8
  local browseX = rightX + pvW_for_actions - (addW) - 8

  btnBrowse = { x=addX,    y=addY, w=browseW, h=addH }
  btnPaste  = { x=browseX, y=addY, w=addW,    h=addH }

  local mx,my = love.mouse.getPosition()
  local overBrowse = inside(mx,my,btnBrowse)
  love.graphics.setColor(1,1,1, overBrowse and 0.95*a or 0.55*a)
  love.graphics.print(browseLabel, btnBrowse.x, btnBrowse.y)
  if overBrowse then love.graphics.line(btnBrowse.x, btnBrowse.y+addH, btnBrowse.x+browseW, btnBrowse.y+addH) end

  local overPaste = inside(mx,my,btnPaste)
  love.graphics.setColor(1,1,1, overPaste and 0.95*a or 0.55*a)
  love.graphics.print(addLabel, btnPaste.x, btnPaste.y)
  if overPaste then love.graphics.line(btnPaste.x, btnPaste.y+addH, btnPaste.x+addW, btnPaste.y+addH) end

  -- Images strip
  imagesStrip.y = imgHeadY + addH + 8
  local stripX, stripY, stripW, stripH = rightX, imagesStrip.y, rightW, imagesStrip.h
  love.graphics.setColor(0.11,0.11,0.16,0.95*a); love.graphics.rectangle("fill", stripX, stripY, stripW, stripH, 10,10)
  love.graphics.setColor(1,0.88,0.45,0.45*a); love.graphics.rectangle("line", stripX, stripY, stripW, stripH, 10,10)
  imagesStrip.rect = { x=stripX, y=stripY, w=stripW, h=stripH }

  local navW = 28
  imagesStrip.leftRect  = { x=stripX, y=stripY, w=navW, h=stripH }
  imagesStrip.rightRect = { x=stripX+stripW-navW, y=stripY, w=navW, h=stripH }
  local overLeft  = inside(mx,my,imagesStrip.leftRect)
  local overRight = inside(mx,my,imagesStrip.rightRect)
  love.graphics.setColor(1,1,1, overLeft and 0.8*a or 0.35*a)
  love.graphics.printf("‹", imagesStrip.leftRect.x, imagesStrip.leftRect.y + stripH/2 - 12, imagesStrip.leftRect.w, "center")
  love.graphics.setColor(1,1,1, overRight and 0.8*a or 0.35*a)
  love.graphics.printf("›", imagesStrip.rightRect.x, imagesStrip.rightRect.y + stripH/2 - 12, imagesStrip.rightRect.w, "center")

  -- Safe scissor
  local scX = stripX + navW + imagesStrip.pad
  local scY = stripY
  local scW = math.max(1, stripW - navW*2 - imagesStrip.pad*2)
  local scH = math.max(1, stripH)

  if scW > 1 and scH > 1 then
    love.graphics.setScissor(scX, scY, scW, scH)
    love.graphics.push(); love.graphics.translate(-imagesStrip.scroll, 0)
    thumbRects, delRects = {}, {}
    local cursor = stripX + navW + imagesStrip.pad
    local gap = 10
    for _,entry in ipairs(allImageEntries()) do
      local p = entry.path
      local th = getThumb(p, imagesStrip.thumbH)
      local tw = (th and th.w) or math.floor(imagesStrip.thumbH * 1.3)
      local thX = cursor
      local thY = stripY + (stripH - imagesStrip.thumbH)/2
      love.graphics.setColor(1,1,1,0.15*a); love.graphics.rectangle("fill", thX-2, thY-2, tw+4, imagesStrip.thumbH+4, 6,6)
      love.graphics.setColor(1,1,1,0.28*a); love.graphics.rectangle("line", thX-2, thY-2, tw+4, imagesStrip.thumbH+4, 6,6)
      if th and th.img then
        love.graphics.setColor(1,1,1,1)
        if th.passthrough then
          local slot = loadImage(p)
          local ih = (slot and slot.h) or imagesStrip.thumbH
          local iw = (slot and slot.w) or imagesStrip.thumbH
          local s  = imagesStrip.thumbH / ih
          local drawW = iw * s
          love.graphics.draw(th.img, thX + (tw - drawW)/2, thY, 0, s, s)
        else
          love.graphics.draw(th.img, thX, thY)
        end
      else
        love.graphics.setColor(1,1,1,0.1); love.graphics.rectangle("fill", thX, thY, tw, imagesStrip.thumbH, 6,6)
      end
      local dx, dy, dw, dh = thX + tw - 14, thY - 6, 16, 16
      love.graphics.setColor(1,0.7,0.7,0.9*a); love.graphics.rectangle("fill", dx, dy, dw, dh, 4,4)
      love.graphics.setColor(0.2,0.05,0.05,0.8*a); love.graphics.printf("×", dx, dy-2, dw, "center")

      delRects[#delRects+1] = { x=dx - imagesStrip.scroll, y=dy, w=dw, h=dh, path=p, staged=entry.staged }
      thumbRects[#thumbRects+1] = { x=thX - imagesStrip.scroll, y=thY, w=tw, h=imagesStrip.thumbH, path=p, staged=entry.staged }

      cursor = cursor + tw + gap
    end
    love.graphics.pop(); love.graphics.setScissor()
  end

  -- RIGHT: controls viewport (style sliders/enums)
  local pvBottom = imagesStrip.y + imagesStrip.h
  viewport.x = rightX
  viewport.y = pvBottom + 16
  viewport.w = rightW
  local reservedForButtons = 64
  viewport.h = math.max(260, (py + panelH - 60) - viewport.y - reservedForButtons)

  local sbW, padIn = 12, 8
  local contentW2 = viewport.w - sbW - padIn
  local sxL = viewport.x + padIn
  local colGap = 16
  local colW  = math.floor((contentW2 - colGap)/2)
  local sxR   = sxL + colW + colGap
  local syBase= viewport.y + 14
  local rowH  = 44

  local sliderRows    = math.ceil(#sliders / 2)
  local slidersHeight = sliderRows * rowH
  local chipsTopY     = syBase + slidersHeight + 8

  local chipPadX, chipPadY = 10, 6
  local chipGapX, chipGapY = 8, 12

  local function measureEnums()
    local fb = Common.fontBody or love.graphics.getFont()
    local x = sxL; local y = chipsTopY
    local lineH = fb:getHeight(); local chipH = chipPadY*2 + lineH
    local maxX = sxL + colW*2 + colGap
    for _,e in ipairs(enums) do
      y = y + 18; x = sxL
      local function acc(text)
        local tw = fb:getWidth(text)
        local w = math.min(tw + chipPadX*2, maxX - sxL)
        if x + w > maxX then x = sxL; y = y + chipH + chipGapY end
        x = x + w + chipGapX
      end
      if e.kind=="bool" then acc("off"); acc("on") else for _,c in ipairs(e.choices or {}) do acc(tostring(c)) end end
      y = y + chipH + chipGapY
    end
    return (y - (viewport.y + 8))
  end

  viewport.contentH = measureEnums()
  local maxScrollNow = math.max(0, viewport.contentH - viewport.h)
  viewport.scroll = clamp(viewport.scroll or 0, 0, maxScrollNow)

  love.graphics.setScissor(viewport.x, viewport.y, viewport.w, viewport.h)
  love.graphics.push(); love.graphics.translate(0, -(viewport.scroll or 0))

  for idx,s in ipairs(sliders) do
    local col = (idx % 2 == 1) and 1 or 2
    local row = math.floor((idx - 1) / 2)
    local sx  = (col == 1) and sxL or sxR
    local sy  = syBase + row * rowH
    local t = (s.value - s.min) / (s.max - s.min)
    local thumbX = sx + t * colW
    local screenY = sy - (viewport.scroll or 0)
    s._rectScreen  = { x=sx,        y=screenY, w=colW,   h=16 }
    s._thumbScreen = { x=thumbX-8,  y=screenY, w=16,     h=16 }
    local mx3,my3 = love.mouse.getPosition()
    local over = (mx3>=s._rectScreen.x and mx3<=s._rectScreen.x+s._rectScreen.w
               and my3>=s._rectScreen.y and my3<=s._rectScreen.y+s._rectScreen.h
               and mx3>=viewport.x and mx3<=viewport.x+viewport.w
               and my3>=viewport.y and my3<=viewport.y+viewport.h)
    love.graphics.setColor(over and 0.35 or 0.25, over and 0.35 or 0.25, over and 0.45 or 0.32, 1)
    love.graphics.rectangle("fill", sx, sy+10, colW, 4, 2,2)
    love.graphics.setColor(1,0.96,0.70,0.95*a); love.graphics.rectangle("fill", thumbX-6, sy+6, 12,12, 3,3)
    love.graphics.setColor(1,1,1,0.85*a); love.graphics.print(s.label, sx, sy-14)
    local fmt = (s.step or 0.01) >= 1 and "%.0f" or "%.2f"; if s.key=="radius" then fmt="%.1f" end
    love.graphics.printf(string.format(fmt, s.value), sx, sy-14, colW, "right")
  end

  local chipY = chipsTopY
  local mx2,my2 = love.mouse.getPosition()
  for _,e in ipairs(enums) do
    love.graphics.setColor(1,1,1,0.85*a); love.graphics.print(e.label, sxL, chipY); chipY = chipY + 18
    e._chipRects = {}
    local x = sxL
    local maxX = sxL + colW*2 + colGap
    local lineH = fontBody:getHeight()
    local chipH = chipPadY*2 + lineH
    local function placeChip(text)
      local tw = fontBody:getWidth(text); local chipW = math.min(tw + chipPadX*2, maxX - sxL)
      if x + chipW > maxX then x = sxL; chipY = chipY + chipH + chipGapY end
      local cy = chipY; local screenY = cy - (viewport.scroll or 0)
      local rect = { x=x, y=screenY, w=chipW, h=chipH, value=text }; e._chipRects[#e._chipRects+1]=rect
      local isSelected = (tostring(e.value)==text)
      local hot = (not textDragging)
        and (mx2>=rect.x and mx2<=rect.x+rect.w and my2>=rect.y and my2<=rect.y+rect.h)
        and (mx2>=viewport.x and mx2<=viewport.x+viewport.w and my2>=viewport.y and my2<=viewport.y+viewport.h)
      love.graphics.setColor((isSelected and 0.26 or (hot and 0.22 or 0.18)), (isSelected and 0.26 or (hot and 0.22 or 0.18)), (isSelected and 0.30 or (hot and 0.26 or 0.22)), 0.95*a)
      love.graphics.rectangle("fill", x, cy, chipW, chipH, 8,8)
      love.graphics.setColor(0.95,0.74,0.25,0.90*a); love.graphics.setLineWidth(1); love.graphics.rectangle("line", x, cy, chipW, chipH, 8,8)
      love.graphics.setColor(1,1,1,a); love.graphics.print(text, x + chipPadX, cy + chipPadY)
      x = x + chipW + chipGapX
    end
    if e.kind=="bool" then placeChip("off"); placeChip("on") else for _,choice in ipairs(e.choices or {}) do placeChip(tostring(choice)) end end
    chipY = chipY + chipH + chipGapY
  end

  love.graphics.pop(); love.graphics.setScissor()

  -- Buttons
  local buttonsTop = py + panelH - 64
  local btnW, btnH, gapB = 140, 40, 18
  local bx = px + panelW - btnW*2 - gapB - 18
  local by = buttonsTop + (64 - btnH)*0.5

  btnSave = { x=bx, y=by, w=btnW, h=btnH }
  love.graphics.setColor(hoverSave and 0.22 or 0.18, hoverSave and 0.22 or 0.18, hoverSave and 0.26 or 0.22, 0.95*a)
  love.graphics.rectangle("fill", bx,by, btnW,btnH, 8,8)
  love.graphics.setColor(0.95,0.74,0.25,0.90*a); love.graphics.setLineWidth(1); love.graphics.rectangle("line", bx,by, btnW,btnH, 8,8)
  love.graphics.setColor(1,1,1,a); love.graphics.printf("Save", bx, by+10, btnW, "center")

  local bx2 = bx + btnW + gapB
  btnCancel = { x=bx2, y=by, w=btnW, h=btnH }
  love.graphics.setColor(hoverCancel and 0.22 or 0.18, hoverCancel and 0.22 or 0.18, hoverCancel and 0.26 or 0.22, 0.95*a)
  love.graphics.rectangle("fill", bx2,by, btnW,btnH, 8,8)
  love.graphics.setColor(0.95,0.74,0.25,0.90*a); love.graphics.setLineWidth(1); love.graphics.rectangle("line", bx2,by, btnW,btnH, 8,8)
  love.graphics.setColor(1,1,1,a); love.graphics.printf("Cancel", bx2, by+10, btnW, "center")

  love.graphics.setColor(1,1,1,0.35*a)
  love.graphics.printf("Tip: images are staged until you save. Canceling discards them.", rightX, by - 24, rightW - 10, "right")

  -- === SimplePicker overlay ===
  if SimplePicker.isOpen and SimplePicker.isOpen() then
    love.graphics.setColor(0,0,0,0.65); love.graphics.rectangle("fill", 0,0, sw,sh)
    SimplePicker.draw(px+40, py+60, panelW-80, panelH-120)
  end
end

-- ===== Save / import helpers =====
local function ensureId(mem)
  if mem.id then return tostring(mem.id) end
  return tostring(math.floor(love.timer.getTime() * 100000))
end

local function getSelectedTags()
  local out = {}
  for _,t in ipairs(PRESET_TAGS) do if selectedTagsSet[t] then out[#out+1]=t end end
  return out
end

-- Build the style to persist:
-- Start with what we opened (originalStyle), then overlay the current UI-edited fields.
local function buildStyleForSaving()
  local out = shallowCopy(originalStyle or {})
  for k, v in pairs(style or {}) do
    if k == "color" and type(v) == "table" then
      out.color = { v[1] or 1, v[2] or 1, v[3] or 1 }
    else
      out[k] = v
    end
  end
  out.radius = out.radius or style.radius or originalStyle.radius or 12
  return out
end

local function commitSave()
  local title    = (fields[1].value or ""):gsub("^%s+",""):gsub("%s+$","")
  local subtitle = fields[2].value or ""
  local memoryTx = fields[3].value or ""
  if title == "" then return end

  local mem = {
  id = editId, x = posX, y = posY,

  -- legacy compatibility
  label   = title,
  subtitle= subtitle,
  memory  = memoryTx,
  text    = memoryTx,     -- ← was subtitle before; correct to body
  details = memoryTx,

  -- richer
  title   = title,
  blocks  = { { type="text", text = memoryTx } },
  tags    = getSelectedTags(),
  background = (selectedBackground == "default") and nil or selectedBackground,
  style   = buildStyleForSaving(),
  images  = {},
}


  local sm = tryRequireStarMap()

  if mode=="edit" then
    local finalList = Media.commit(mem.id, existingImages, stagedImages, removedExistingSet)
    mem.images = finalList
    if sm and sm.updateMemory then sm.updateMemory(mem) end
    if onSave then onSave(mem) end
    Composer.cancel()
    return
  end

  local addedId = nil
  if sm and sm.addMemory then
    local ok, ret = pcall(sm.addMemory, mem)
    if ok then addedId = ret end
  end
  mem.id = tostring(addedId or ensureId(mem))
  if (not addedId) and sm and sm.addMemory then pcall(sm.addMemory, mem) end

  local finalList = Media.commit(mem.id, {}, stagedImages, {})
  mem.images = finalList
  if sm and sm.updateMemory then pcall(sm.updateMemory, mem) end
  if onSave then onSave(mem) end
  Composer.cancel()
end

-- --- Click-off blur helpers -----------------------------------------------
local function anyFieldHit(x, y)
  for _, f in ipairs(fields) do
    if f.rect and x >= f.rect.x and x <= f.rect.x + f.rect.w
             and y >= f.rect.y and y <= f.rect.y + f.rect.h then
      return true
    end
  end
  return false
end

local function blurAllFields()
  focused = nil
  for _, f in ipairs(fields) do
    f.selecting = false
    f.anchor = f.caret
    f.selStart = f.caret
    f.selEnd = f.caret
    f._followCaret = false
  end
end

-- ===== Input =====
function Composer.mousepressed(x, y, button)
  if not open then return false end

  if SimplePicker.isOpen and SimplePicker.isOpen() then
    if SimplePicker.mousepressed and SimplePicker.mousepressed(x, y, button) then
      return true
    end
    return true
  end

  if button == 2 then
    return true
  end

  local lmb = (button == 1 or button == nil)

  -- Save / Cancel
  if btnSave   and inside(x,y,btnSave)   then commitSave(); return true end
  if btnCancel and inside(x,y,btnCancel) then if onCancel then onCancel() end; Composer.cancel(); return true end

  -- Open picker
  if btnBrowse and inside(x,y,btnBrowse) then
    if SimplePicker.open then SimplePicker.open() end
    return true
  end

  -- Paste-from-clipboard import
  if btnPaste and inside(x,y,btnPaste) then
    local clip = (love.system and love.system.getClipboardText and love.system.getClipboardText()) and love.system.getClipboardText() or ""
    if clip and clip ~= "" then
      if clip:match("^%a:[/\\]") or clip:match("^/") then
        local p = Media.stageImportAbs(clip); if p then stagedImages[#stagedImages+1]=p end
      elseif love.filesystem.getInfo(clip) then
        stagedImages[#stagedImages+1]=clip
      end
    end
    return true
  end

  -- Thumbnails strip
  if imagesStrip.rect and inside(x,y,imagesStrip.rect) then
    if imagesStrip.leftRect  and inside(x,y,imagesStrip.leftRect)  then
      imagesStrip.scroll = math.max(0, imagesStrip.scroll - 240); return true
    end
    if imagesStrip.rightRect and inside(x,y,imagesStrip.rightRect) then
      imagesStrip.scroll = imagesStrip.scroll + 240; return true
    end
    for _,r in ipairs(delRects or {}) do
      if inside(x,y,r) then
        if r.staged then
          for i,p in ipairs(stagedImages) do if p==r.path then table.remove(stagedImages, i); break end end
          Media.removeStaged(r.path)
        else
          removedExistingSet[r.path] = true
        end
        return true
      end
    end
    return true
  end

  -- ===== Fields focus / selection begin (handle BEFORE tags/background/enums/sliders) =====
  local fb = Common.fontBody or love.graphics.getFont()
  for i,f in ipairs(fields) do
    if f.rect and inside(x,y,f.rect) then
      focused = i
      local padX,padY=12,10
      local cw = f.rect.w - 2*padX - 10
      local pos = caretFromMouse(f, x, y, fb, cw, padX, padY)
      if love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") then
        f.anchor = f.anchor or f.caret or pos
        extendSelectionTo(f, pos)
      else
        setCaret(f, pos)
      end
      f.selecting = lmb
      return true
    end
  end

  -- If the click was NOT in a field, blur fields BEFORE interacting with other controls.
  if lmb and not anyFieldHit(x, y) then
    blurAllFields()
  end

  -- Tag chips
  for _,r in ipairs(tagChipRects or {}) do
    if inside(x,y,r) then
      blurAllFields()
      local t = r.tag
      selectedTagsSet[t] = not selectedTagsSet[t]
      return true
    end
  end

  -- Background swatches
  for _,s in ipairs(swatchRects or {}) do
    if inside(x,y,s) then
      blurAllFields()
      selectedBackground = backgroundFromSwatch(s.kind, s.index)
      return true
    end
  end

  -- Enum chips (right column style)
  for _,e in ipairs(enums) do
    if e._chipRects then
      for _,r in ipairs(e._chipRects) do
        if inside(x,y,r) then
          blurAllFields()
          e.value = r.value
          if e.kind=="bool" then
            style[e.key] = (r.value=="on")
          else
            style[e.key] = r.value
          end
          return true
        end
      end
    end
  end

  -- Sliders
  for i,s in ipairs(sliders) do
    local hit = (s._thumbScreen and inside(x,y,s._thumbScreen)) or (s._rectScreen and inside(x,y,s._rectScreen))
    if hit then
      blurAllFields()
      dragging.active, dragging.idx = true, i
      local t = clamp((x - s._rectScreen.x)/s._rectScreen.w, 0,1)
      local val = s.min + t * (s.max - s.min)
      if s.step and s.step>0 then val = math.floor((val/s.step)+0.5)*s.step end
      s.value = clamp(val, s.min, s.max)
      if s.key=="color_r" then
        style.color[1]=s.value
      elseif s.key=="color_g" then
        style.color[2]=s.value
      elseif s.key=="color_b" then
        style.color[3]=s.value
      else
        style[s.key]=s.value
      end
      return true
    end
  end

  return true
end

function Composer.mousereleased()
  dragging.active, dragging.idx = false, nil
  for _,f in ipairs(fields) do f.selecting=false end
end

function Composer.mousemoved(x, y, dx, dy)
  if SimplePicker.isOpen and SimplePicker.isOpen() then return end
  -- drag slider
  if dragging.active then
    local s = sliders[dragging.idx]; if not s or not s._rectScreen then return end
    local t = clamp((x - s._rectScreen.x)/s._rectScreen.w, 0,1)
    local val = s.min + t * (s.max - s.min)
    if s.step and s.step>0 then val = math.floor((val/s.step)+0.5)*s.step end
    s.value = clamp(val, s.min, s.max)
    if s.key=="color_r" then style.color[1]=s.value
    elseif s.key=="color_g" then style.color[2]=s.value
    elseif s.key=="color_b" then style.color[3]=s.value
    else style[s.key]=s.value end
    return
  end

  -- drag-select text
  local fb = Common.fontBody or love.graphics.getFont()
  for _,f in ipairs(fields) do
    if f.selecting and f.rect then
      local padX,padY=12,10
      local cw = f.rect.w - 2*padX - 10
      local pos = caretFromMouse(f, x, y, fb, cw, padX, padY)
      extendSelectionTo(f, pos)
      return
    end
  end
end

function Composer.wheelmoved(dx, dy)
  if not open then return end
  if SimplePicker.isOpen and SimplePicker.isOpen() then SimplePicker.wheelmoved(dx,dy); return end

  local mx,my = love.mouse.getPosition()

  if imagesStrip.rect and inside(mx,my,imagesStrip.rect) then
    imagesStrip.scroll = math.max(0, imagesStrip.scroll + (dy<0 and 160 or -160))
    return
  end

  for _,f in ipairs(fields) do
    if f.hover and f.rect then
      f.scroll = math.max(0, (f.scroll or 0) - dy * 32)
      return
    end
  end

  if mx>=viewport.x and mx<=viewport.x+viewport.w and my>=viewport.y and my<=viewport.y+viewport.h then
    local maxScroll = math.max(0, (viewport.contentH or 0) - viewport.h)
    viewport.scroll = math.max(0, math.min(maxScroll, (viewport.scroll or 0) + (dy<0 and 80 or -80)))
  end
end

function Composer.keypressed(key, scancode, isrepeat)
  if key=="escape" then
    if SimplePicker.isOpen and SimplePicker.isOpen() then SimplePicker.close(); return end
    Composer.cancel(); return
  end
  if SimplePicker.isOpen and SimplePicker.isOpen() then
    if SimplePicker.keypressed then SimplePicker.keypressed(key) end
    return
  end

  local f = fields[focused]
  local ctrl = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
  local cmd  = love.keyboard.isDown("lgui")  or love.keyboard.isDown("rgui")
  local alt  = love.keyboard.isDown("lalt")  or love.keyboard.isDown("ralt")
  local shift= love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
  local mod  = ctrl or cmd
  local word = ctrl or alt

  if f then
    if mod and ((key=="a") or (scancode=="a")) then
      f.selStart = 1
      f.selEnd   = fieldLen(f) + 1
      f.caret    = f.selEnd
      f.anchor   = 1
      return
    end
    if mod and ((key=="c") or (scancode=="c")) then
      if hasSelection(f) and love.system and love.system.setClipboardText then
        love.system.setClipboardText(u8sub_between(f.value or "", f.selStart, f.selEnd))
      end
      return
    end
    if mod and ((key=="x") or (scancode=="x")) then
      if hasSelection(f) and love.system and love.system.setClipboardText then
        love.system.setClipboardText(u8sub_between(f.value or "", f.selStart, f.selEnd))
        deleteSelection(f)
      end
      return
    end
    if mod and ((key=="v") or (scancode=="v")) then
      if love.system and love.system.getClipboardText then
        local clip = love.system.getClipboardText() or ""
        if clip ~= "" then insertTextAtCaret(f, clip, f.multiline) end
      end
      return
    end

    if key=="backspace" then
      if word then ctrlBackspace(f) else backspaceChar(f) end
      return
    elseif key=="delete" then
      if word then ctrlDelete(f) else deleteChar(f) end
      return
    elseif key=="left" then
      if word then moveCaretWord(f, -1, shift) else moveCaretChars(f, -1, shift) end
      return
    elseif key=="right" then
      if word then moveCaretWord(f,  1, shift) else moveCaretChars(f,  1, shift) end
      return
    elseif key=="home" then
      moveCaretHomeEnd(f, false, shift); return
    elseif key=="end" then
      moveCaretHomeEnd(f, true,  shift); return
    elseif (key=="return" or key=="kpenter") then
      if f.multiline then
        insertTextAtCaret(f, "\n", true)
      else
        commitSave()
      end
      return
    elseif key=="tab" then
      focused = (focused % #fields) + 1
      return
    end
  end

  -- Allow image path paste when no field focused
  if mod and (key=="v" or scancode=="v") and (not f) then
    local clip = (love.system and love.system.getClipboardText and love.system.getClipboardText()) and love.system.getClipboardText() or ""
    if clip and clip~="" then
      if clip:match("^%a:[/\\]") or clip:match("^/") then
        local p = Media.stageImportAbs(clip); if p then stagedImages[#stagedImages+1]=p end
      elseif love.filesystem.getInfo(clip) then
        stagedImages[#stagedImages+1]=clip
      end
    end
    return
  end
end

function Composer.textinput(t)
  if not open then return end
  if SimplePicker.isOpen and SimplePicker.isOpen() then return end
  local f = fields[focused]; if not f then return end
  insertTextAtCaret(f, t, f.multiline)
end

-- Hook from main.lua:
-- function love.filedropped(file) require("ui.composer").filedropped(file) end
function Composer.filedropped(file)
  if not open or not file or type(file)~="userdata" then return false end
  local p = Media.stageImportDropped(file)
  if p then stagedImages[#stagedImages+1] = p; return true end
  return false
end

function Composer.deleteMediaFor(memId)
  local ok, ms = pcall(require, "media_store")
  if ok and ms and ms.deleteFor then ms.deleteFor(memId) end
end

return Composer
