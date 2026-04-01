-- ui/textedit.lua
-- Reusable text field logic: caret, selection, insert/delete, copy/cut/paste, word nav.
-- Uses global utf8 (set in main.lua as: utf8 = require("utf8")), with safe fallback.

local utf8 = utf8 or require("utf8")
local M = {}

-- ========= UTF-8 helpers =========
local function ulen(s) return utf8.len(s or "") or 0 end

-- idx is 1-based caret position (1..len+1). Returns byte index (1..#s+1)
local function cpIndexToByteIndex(s, idx)
  if idx <= 1 then return 1 end
  local l = ulen(s)
  if idx > l + 1 then return #s + 1 end
  local b = utf8.offset(s, idx)
  return b or (#s + 1)
end

-- 1-based, inclusive i..j by codepoints; j may be < i => ""
local function usub(s, i, j)
  local l = ulen(s)
  i = math.max(1, math.min(i or 1, l))
  j = math.max(1, math.min(j or l, l))
  if j < i then return "" end
  local bi = cpIndexToByteIndex(s, i)
  local bj = cpIndexToByteIndex(s, j + 1) - 1
  return s:sub(bi, bj)
end

-- [a, b) half-open in caret space (1..len+1)
local function usub_between(s, a, b)
  local l = ulen(s)
  a = math.max(1, math.min(a or 1, l + 1))
  b = math.max(1, math.min(b or (l + 1), l + 1))
  if b <= a then return "" end
  return usub(s, a, b - 1)
end

-- ========= Field lifecycle =========
function M.init(field)
  field.value     = field.value or ""
  local l = ulen(field.value)
  field.caret     = field.caret or (l + 1)   -- 1..len+1
  field.anchor    = field.anchor or field.caret
  field.selStart  = field.selStart or field.caret
  field.selEnd    = field.selEnd   or field.caret
  field.scroll    = field.scroll or 0
  field.multiline = (field.multiline == true)
  field.max       = field.max or 1e9         -- max codepoints
  field.selecting = false                    -- mouse drag flag
  field._caretMoved = false                  -- for one-shot follow
end

-- ========= Selection helpers =========
function M.hasSelection(f)
  return (f.selStart ~= f.selEnd)
end

local function normalizeSel(f)
  if f.selStart > f.selEnd then
    f.selStart, f.selEnd = f.selEnd, f.selStart
  end
end

function M.clearSelection(f)
  f.selStart, f.selEnd = f.caret, f.caret
  f.anchor = f.caret
end

function M.selectAll(f)
  f.selStart = 1
  f.selEnd   = ulen(f.value) + 1
  f.anchor   = f.selStart
  f.caret    = f.selEnd
  f._caretMoved = true
end

local function normalizedRange(f)
  local a = math.min(f.selStart, f.selEnd)
  local b = math.max(f.selStart, f.selEnd)
  return a, b
end

function M.getSelectionText(f)
  if not M.hasSelection(f) then return "" end
  return usub_between(f.value or "", f.selStart, f.selEnd)
end

-- ========= Caret movement =========
function M.setCaret(f, pos, keepAnchor)
  local l = ulen(f.value or "")
  f.caret = math.max(1, math.min(pos or 1, l + 1))
  if not keepAnchor then f.anchor = f.caret end
  f.selStart, f.selEnd = f.caret, f.caret
  f._caretMoved = true
end

function M.extendSelectionTo(f, pos)
  local l = ulen(f.value or "")
  pos = math.max(1, math.min(pos or 1, l + 1))
  f.anchor = f.anchor or f.caret or pos
  f.selStart, f.selEnd = f.anchor, pos
  normalizeSel(f)
  f.caret = f.selEnd
  f._caretMoved = true
end

function M.moveChars(f, delta, withSelect)
  local l = ulen(f.value or "")
  local np = math.max(1, math.min((f.caret or 1) + delta, l + 1))
  if withSelect then M.extendSelectionTo(f, np) else M.setCaret(f, np) end
end

-- simple word boundaries: contiguous non-space == word
local function wordBoundaryLeft(s, caret)
  local left = usub_between(s, 1, caret - 1)
  if left == "" then return 1 end
  left = left:gsub("%s+$","")
  local cut = left:gsub("[^%s]+$","")
  return ulen(cut) + 1
end
local function wordBoundaryRight(s, caret)
  local l = ulen(s)
  local right = usub_between(s, caret, l + 1)
  if right == "" then return l + 1 end
  right = right:gsub("^%s+","")
  right = right:gsub("^[^%s]+","")
  return (l - ulen(right)) + 1
end

function M.moveWord(f, dir, withSelect)
  local s = f.value or ""
  local np = (dir < 0) and wordBoundaryLeft(s, f.caret or 1) or wordBoundaryRight(s, f.caret or 1)
  if withSelect then M.extendSelectionTo(f, np) else M.setCaret(f, np) end
end

function M.moveToStart(f, withSelect)
  if withSelect then
    f.anchor = f.anchor or f.caret
    f.selStart, f.selEnd = f.anchor, 1
    normalizeSel(f)
    f.caret = f.selEnd
    f._caretMoved = true
  else
    M.setCaret(f, 1)
  end
end

function M.moveToEnd(f, withSelect)
  local e = ulen(f.value)
  if withSelect then
    f.anchor = f.anchor or f.caret
    f.selStart, f.selEnd = f.anchor, e + 1
    normalizeSel(f)
    f.caret = f.selEnd
    f._caretMoved = true
  else
    M.setCaret(f, e + 1)
  end
end

-- ========= Editing =========
function M.deleteSelection(f)
  if not M.hasSelection(f) then return false end
  local s = f.value or ""
  local a, b = normalizedRange(f)
  local ba = cpIndexToByteIndex(s, a)
  local bb = cpIndexToByteIndex(s, b)
  f.value  = s:sub(1, ba - 1) .. s:sub(bb)
  f.caret  = a
  f.anchor = f.caret
  f.selStart, f.selEnd = f.caret, f.caret
  f._caretMoved = true
  return true
end

function M.insertText(f, text)
  text = text or ""
  if text == "" then return end

  -- single-line: normalize newlines to spaces
  if not f.multiline then
    text = text:gsub("[\r\n]+", " ")
  end

  -- enforce max (codepoints)
  local s = f.value or ""
  local cur = ulen(s)
  local add = ulen(text)
  local room = math.max(0, (f.max or 1e9) - cur)
  if room <= 0 then return end
  if add > room then text = usub(text, 1, room) end

  if M.deleteSelection(f) then s = f.value end

  local bCaret = cpIndexToByteIndex(s, f.caret)
  f.value = s:sub(1, bCaret - 1) .. text .. s:sub(bCaret)
  f.caret = f.caret + (utf8.len(text) or 0)
  f.anchor = f.caret
  f.selStart, f.selEnd = f.caret, f.caret
  f._caretMoved = true
end

function M.backspace(f)
  if M.deleteSelection(f) then return end
  if (f.caret or 1) <= 1 then return end
  local s = f.value or ""
  local b1 = cpIndexToByteIndex(s, f.caret - 1)
  local b2 = cpIndexToByteIndex(s, f.caret)
  f.value = s:sub(1, b1 - 1) .. s:sub(b2)
  f.caret = f.caret - 1
  f.anchor = f.caret
  f.selStart, f.selEnd = f.caret, f.caret
  f._caretMoved = true
end

function M.deleteForward(f)
  if M.deleteSelection(f) then return end
  local s = f.value or ""
  if (f.caret or 1) > ulen(s) then return end
  local b1 = cpIndexToByteIndex(s, f.caret)
  local b2 = cpIndexToByteIndex(s, f.caret + 1)
  f.value = s:sub(1, b1 - 1) .. s:sub(b2)
  f.anchor = f.caret
  f.selStart, f.selEnd = f.caret, f.caret
  f._caretMoved = true
end

function M.deleteWordLeft(f)
  if M.deleteSelection(f) then return end
  local s = f.value or ""
  local np = wordBoundaryLeft(s, f.caret or 1)
  if np >= (f.caret or 1) then return end
  f.value = usub_between(s, 1, np) .. usub_between(s, f.caret, ulen(s) + 1)
  f.caret = np
  f.anchor = f.caret
  f.selStart, f.selEnd = f.caret, f.caret
  f._caretMoved = true
end

function M.deleteWordRight(f)
  if M.deleteSelection(f) then return end
  local s = f.value or ""
  local np = wordBoundaryRight(s, f.caret or 1)
  if np <= (f.caret or 1) then return end
  f.value = usub_between(s, 1, f.caret) .. usub_between(s, np, ulen(s) + 1)
  f.anchor = f.caret
  f.selStart, f.selEnd = f.caret, f.caret
  f._caretMoved = true
end

-- ========= Clipboard =========
function M.copy(f)
  if not M.hasSelection(f) then return end
  local clip = M.getSelectionText(f)
  if love.system and love.system.setClipboardText then
    love.system.setClipboardText(clip)
  end
end

function M.cut(f)
  if not M.hasSelection(f) then return end
  M.copy(f)
  M.deleteSelection(f)
end

function M.paste(f)
  local clip = (love.system and love.system.getClipboardText and love.system.getClipboardText()) and love.system.getClipboardText() or ""
  if clip == "" then return end
  M.insertText(f, clip)
end

-- ========= Mouse selection helpers =========
-- font: a Love2D Font; cw: content width (without paddings)
function M.caretFromMouse(f, x, y, font, cw, padX, padY)
  local text = f.value or ""
  local _, lines = font:getWrap(text, cw)
  local lineH = font:getHeight()
  local localY = y - (f.rect.y + padY) + (f.scroll or 0)
  local line = math.floor(localY / lineH) + 1
  if line < 1 then line = 1 elseif line > #lines then line = #lines end
  local acc = 0
  for i = 1, line - 1 do acc = acc + ulen(lines[i]) end
  local lx = x - (f.rect.x + padX)
  if lx <= 0 then return acc + 1 end
  local s = lines[line] or ""
  local best, wPrev = 0, 0
  local chars = ulen(s)
  for c = 1, chars do
    local w = font:getWidth(usub(s, 1, c))
    if lx < (wPrev + w) * 0.5 then best = c - 1; break end
    wPrev = w
    best = c
  end
  return acc + best + 1
end

-- Call when mouse pressed in field bounds; pass shiftDown to extend selection
function M.mousePress(f, x, y, font, cw, padX, padY, shiftDown)
  local pos = M.caretFromMouse(f, x, y, font, cw, padX, padY)
  if shiftDown then
    f.anchor = f.anchor or f.caret or pos
    M.extendSelectionTo(f, pos)
  else
    M.setCaret(f, pos)
  end
  f.selecting = true
end

function M.mouseDrag(f, x, y, font, cw, padX, padY)
  if not f.selecting then return end
  local pos = M.caretFromMouse(f, x, y, font, cw, padX, padY)
  M.extendSelectionTo(f, pos)
end

function M.mouseRelease(f)
  f.selecting = false
end

-- ========= Caret follow (no per-frame snap) =========
-- Call this AFTER you layout/wrap lines and only when f._caretMoved is true.
function M.ensureCaretVisibleOnce(f, lines, viewH, padY, lineH)
  if not f._caretMoved then return end
  local idx = (f.caret or 1) - 1
  local acc, lineIndex = 0, 1
  for i = 1, #lines do
    local L = ulen(lines[i])
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
  f._caretMoved = false
end

-- ========= Keyboard handler =========
-- Returns true if handled. Options:
--   opts = { onCommit=function() end } -- for single-line Enter
function M.keypressed(f, key, scancode, opts)
  local onCommit = opts and opts.onCommit

  -- modifiers
  local ctrl = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
  local cmd  = love.keyboard.isDown("lgui")  or love.keyboard.isDown("rgui")   -- macOS Command
  local alt  = love.keyboard.isDown("lalt")  or love.keyboard.isDown("ralt")
  local shift= love.keyboard.isDown("lshift")or love.keyboard.isDown("rshift")
  local mod  = ctrl or cmd          -- copy/cut/paste/select-all
  local word = ctrl or alt          -- word nav/delete

  -- Select all / Copy / Cut / Paste
  if mod and ((key=="a") or (scancode=="a")) then M.selectAll(f); return true end
  if mod and ((key=="c") or (scancode=="c")) then M.copy(f); return true end
  if mod and ((key=="x") or (scancode=="x")) then M.cut(f);  return true end
  if mod and ((key=="v") or (scancode=="v")) then M.paste(f);return true end

  -- Navigation / editing
  if key=="backspace" then
    if word then M.deleteWordLeft(f) else M.backspace(f) end
    return true
  elseif key=="delete" then
    if word then M.deleteWordRight(f) else M.deleteForward(f) end
    return true
  elseif key=="left" then
    if word then M.moveWord(f, -1, shift) else M.moveChars(f, -1, shift) end
    return true
  elseif key=="right" then
    if word then M.moveWord(f,  1, shift) else M.moveChars(f,  1, shift) end
    return true
  elseif key=="home" then
    M.moveToStart(f, shift); return true
  elseif key=="end" then
    M.moveToEnd(f, shift); return true
  elseif key=="tab" then
    -- let parent handle focus cycling
    return false
  elseif key=="return" or key=="kpenter" then
    if f.multiline then
      M.insertText(f, "\n")
    else
      if onCommit then onCommit() end
    end
    return true
  end

  return false
end

-- Feed Love's textinput into this
function M.textinput(f, t)
  M.insertText(f, t)
end

return M
