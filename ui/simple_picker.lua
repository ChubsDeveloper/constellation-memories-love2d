-- ui/simple_picker.lua
-- Explorer-like picker: Grid (thumbnails) ⇄ List, directories first, multi-select.
-- Requires: libs/nativefs.lua  (require("libs.nativefs") must work)

local M = {}

local ok_nfs, nativefs = pcall(require, "libs.nativefs")
assert(ok_nfs and nativefs, "[simple_picker] nativefs.lua is required")

local lf = love.filesystem

local DEBUG = true
local function dprint(...) if DEBUG then print("[picker]", ...) end end

-- --------------- state ---------------
local open    = false
local cwd     = nil
local entries = {}   -- { {name, path, isDir, isImg} ... }
local sel     = {}   -- set[path] = true
local scroll  = 0
local layout  = "grid"  -- "grid" | "list"

-- import handshake
local importClicked = false

-- layout rects
local rectPanel, rectSidebar, rectPath, rectUp, rectList, rectImport, rectCancel, rectToggle = nil,nil,nil,nil,nil,nil,nil,nil

-- caches
local thumbCache = {}  -- key = path .. "@" .. size  -> { img=?, w=?, h=?, scale=?, iw=?, ih=? }
local itemRects  = {}  -- for grid/list hit-testing (array of {x,y,w,h,idx})
local sideRects  = {}  -- clickable rows in the sidebar

-- sidebar data
local defaultLinks = {} -- fixed (Quick Access + Drives)
local favLinks     = {} -- user favorites (persisted)
local SIDEBAR_SAVE = "picker_sidebar.txt"

-- context menu
local ctx = { open=false, x=0, y=0, items=nil, target=nil } -- items: { {label,fn}, ... }

-- --------------- utils ---------------
local function clamp(x,a,b) if x<a then return a elseif x>b then return b else return x end end
local function inside(mx,my,r) return r and mx>=r.x and mx<=r.x+r.w and my>=r.y and my<=r.y+r.h end
local SEP = package.config:sub(1,1)

local function isWin() return SEP == "\\" end

-- Keep it simple now: PNG/JPG/JPEG
local SUPPORTED_IMG_EXT = { png=true, jpg=true, jpeg=true }
local function isSupportedImage(name)
  local ext = name:match("%.([A-Za-z0-9]+)$")
  return ext and SUPPORTED_IMG_EXT[string.lower(ext)] or false
end
local function extOf(path) return (path:match("%.([A-Za-z0-9]+)$") or ""):lower() end

local function join(a,b)
  if not a or a=="" then return b end
  if a:sub(-1) == SEP then return a .. b else return a .. SEP .. b end
end

local function existsDir(p)
  local info = nativefs.getInfo(p)
  return info and info.type == "directory"
end

local function parentOf(path)
  local p = (path or ""):gsub("[/\\]+", SEP)
  local i = p:match(".*()" .. SEP)
  if not i or i <= 1 then
    if isWin() then
      local drive = p:match("^([A-Za-z]:\\)")
      return drive or p
    else
      return "/"
    end
  end
  return p:sub(1, i-1)
end

local function homeDir()
  local w = isWin()
  local h = (w and (os.getenv("USERPROFILE") or (os.getenv("HOMEDRIVE") and os.getenv("HOMEDRIVE")..(os.getenv("HOMEPATH") or ""))))
          or os.getenv("HOME")
  return h or nativefs.getWorkingDirectory()
end

-- --------------- sidebar: persistence ---------------
local function saveFavorites()
  local lines = {}
  for _,e in ipairs(favLinks) do
    -- simple "Label|Path" format; escape '|' by doubling it
    local label = tostring(e.label or ""):gsub("|","||")
    local path  = tostring(e.path or ""):gsub("|","||")
    lines[#lines+1] = label .. "|" .. path
  end
  lf.write(SIDEBAR_SAVE, table.concat(lines, "\n"))
end

local function loadFavorites()
  favLinks = {}
  if not lf.getInfo(SIDEBAR_SAVE) then return end
  local s = lf.read(SIDEBAR_SAVE)
  if not s or s=="" then return end
  for line in s:gmatch("[^\r\n]+") do
    local a,b = line:match("^(.*)|(.*)$")
    if a and b then
      a = a:gsub("||","|"); b = b:gsub("||","|")
      if existsDir(b) then
        favLinks[#favLinks+1] = { label=a, path=b, _src="fav" }
      end
    end
  end
end

local function haveFavoritePath(path)
  for _,e in ipairs(favLinks) do if e.path == path then return true end end
  return false
end

local function addFavorite(label, path)
  if not path or not existsDir(path) then return end
  if haveFavoritePath(path) then return end
  favLinks[#favLinks+1] = { label = label or (path:match("([^/\\]+)$") or path), path = path, _src="fav" }
  saveFavorites()
end

local function removeFavoriteByPath(path)
  for i,e in ipairs(favLinks) do
    if e.path == path then table.remove(favLinks, i); saveFavorites(); return true end
  end
  return false
end

-- --------------- sidebar: build ---------------
local function addIfExists(dst, label, path, src)
  if path and existsDir(path) then dst[#dst+1] = { label=label, path=path, _src=src or "default" } end
end

local function buildDefaultLinks()
  defaultLinks = {}
  local HOME = homeDir()

  if isWin() then
    local UP = os.getenv("USERPROFILE")
    addIfExists(defaultLinks, "Home",        UP)
    addIfExists(defaultLinks, "Desktop",     UP and (UP .. "\\Desktop"))
    addIfExists(defaultLinks, "Documents",   UP and (UP .. "\\Documents"))
    addIfExists(defaultLinks, "Downloads",   UP and (UP .. "\\Downloads"))
    addIfExists(defaultLinks, "Pictures",    UP and (UP .. "\\Pictures"))
    -- Try common "Gallery" locations
    addIfExists(defaultLinks, "Gallery",     UP and (UP .. "\\Pictures\\Gallery"))
    addIfExists(defaultLinks, "Gallery",     UP and (UP .. "\\Gallery"))
    addIfExists(defaultLinks, "Saved Pictures", UP and (UP .. "\\Pictures\\Saved Pictures"))
    -- Drives
    for i=string.byte("A"), string.byte("Z") do
      local drive = string.char(i) .. ":\\"
      if existsDir(drive) then
        defaultLinks[#defaultLinks+1] = { label=drive, path=drive, _src="drive" }
      end
    end
  else
    addIfExists(defaultLinks, "Home",      HOME)
    addIfExists(defaultLinks, "Desktop",   HOME and (HOME .. "/Desktop"))
    addIfExists(defaultLinks, "Documents", HOME and (HOME .. "/Documents"))
    addIfExists(defaultLinks, "Downloads", HOME and (HOME .. "/Downloads"))
    addIfExists(defaultLinks, "Pictures",  HOME and (HOME .. "/Pictures"))
    addIfExists(defaultLinks, "Gallery",   HOME and (HOME .. "/Pictures/Gallery"))
    addIfExists(defaultLinks, "Root /",    "/")
  end
end

-- --------------- scanning ---------------
local function scan(dir)
  cwd = dir
  entries = {}
  local items = nativefs.getDirectoryItems(dir) or {}
  local imgCount, dirCount = 0, 0
  for _,name in ipairs(items) do
    if name ~= "." and name ~= ".." then
      local p = join(dir, name)
      local info = nativefs.getInfo(p)
      local isDir = info and info.type == "directory"
      local isImg = (not isDir) and isSupportedImage(name)
      if isDir then dirCount = dirCount + 1 elseif isImg then imgCount = imgCount + 1 end
      entries[#entries+1] = { name = name, path = p, isDir = isDir, isImg = isImg }
    end
  end
  table.sort(entries, function(a,b)
    if a.isDir ~= b.isDir then return a.isDir end
    return string.lower(a.name) < string.lower(b.name)
  end)
  scroll = 0
  itemRects = {}
  dprint("scan:", dir, "dirs=", dirCount, "png/jpg=", imgCount, "total=", #entries)
end

-- --------------- thumbnails ---------------
local function readBytesOS(absPath)
  local ok, data = pcall(nativefs.read, absPath)
  if ok and data and #data > 0 then return data end
  local f = io.open(absPath, "rb"); if not f then return nil end
  local b = f:read("*a"); f:close()
  return (b and #b > 0) and b or nil
end

local function loadThumb(absPath, maxW, maxH)
  maxW = maxW or 140
  maxH = maxH or 110

  local ext = extOf(absPath)
  if not SUPPORTED_IMG_EXT[ext] then
    return { unsupported = true, ext = ext }
  end

  local key = absPath .. "@img@" .. tostring(maxW) .. "x" .. tostring(maxH)
  if thumbCache[key] then return thumbCache[key] end

  local bytes = readBytesOS(absPath)
  if not bytes then dprint("IMG readBytes FAIL:", absPath); return nil end

  local hint = "pick."..ext
  local ok_fd, fd = pcall(lf.newFileData, bytes, hint)
  if not ok_fd or not fd then dprint("IMG FileData(contents,name) FAIL:", absPath); return nil end

  local ok_id, id = pcall(love.image.newImageData, fd)
  if not ok_id or not id then dprint("IMG ImageData(FileData) FAIL:", absPath); return nil end

  local ok_img, img = pcall(love.graphics.newImage, id)
  if not ok_img or not img then dprint("IMG newImage FAIL:", absPath); return nil end

  img:setFilter("linear", "linear")

  local w, h = img:getWidth(), img:getHeight()
  if w <= 0 or h <= 0 then return nil end

  local s = math.min(maxW / w, maxH / h)
  s = math.max(1e-6, math.min(s, 1e6))

  local tw = math.max(1, math.floor(w * s + 0.5))
  local th = math.max(1, math.floor(h * s + 0.5))

  local entry = { img = img, w = tw, h = th, scale = s, iw = w, ih = h }
  thumbCache[key] = entry
  return entry
end

-- --------------- selection / import ---------------
local function selectionCount()
  local n=0; for _,v in pairs(sel) do if v then n=n+1 end end; return n
end

function M.getSelection()
  local out = {}
  for p,v in pairs(sel) do if v then out[#out+1] = p end end
  table.sort(out)
  return out
end

function M.didImport()
  if importClicked then importClicked=false; return true end
  return false
end

function M.takeSelection()
  return M.getSelection() -- keep selection; composer may re-open
end

-- for composer that calls popSelection (same as takeSelection)
function M.popSelection()
  return M.takeSelection()
end

-- --------------- drawing ---------------
local function drawContextMenu()
  if not ctx.open or not ctx.items or #ctx.items==0 then return end
  local font = love.graphics.getFont()
  local padX, padY, itemH = 10, 6, 22
  local w = 0
  for _,it in ipairs(ctx.items) do w = math.max(w, font:getWidth(it.label) + padX*2) end
  local h = #ctx.items * itemH
  love.graphics.setColor(0.12,0.12,0.16,1); love.graphics.rectangle("fill", ctx.x, ctx.y, w, h, 6,6)
  love.graphics.setColor(1,1,1,0.25); love.graphics.rectangle("line", ctx.x, ctx.y, w, h, 6,6)
  local mx,my = love.mouse.getPosition()
  for i,it in ipairs(ctx.items) do
    local iy = ctx.y + (i-1)*itemH
    local hot = (mx>=ctx.x and mx<=ctx.x+w and my>=iy and my<=iy+itemH)
    love.graphics.setColor(1,1,1, hot and 0.08 or 0.04); love.graphics.rectangle("fill", ctx.x+1, iy, w-2, itemH)
    love.graphics.setColor(1,1,1,0.92); love.graphics.print(it.label, ctx.x+padX, iy+padY)
  end
  ctx._rect = { x=ctx.x, y=ctx.y, w=w, h=h }
end

local function ctxClick(x,y)
  if not ctx.open or not ctx._rect then return false end
  if not inside(x,y,ctx._rect) then ctx.open=false; return false end
  local itemH = 22
  local idx = math.floor((y - ctx._rect.y)/itemH) + 1
  local it = ctx.items[idx]
  ctx.open=false
  if it and it.fn then it.fn() end
  return true
end

function M.draw(x, y, w, h)
  if not open then return end

  -- panel
  rectPanel = { x=x, y=y, w=w, h=h }
  love.graphics.setColor(0.10,0.10,0.15,0.98)
  love.graphics.rectangle("fill", x, y, w, h, 12,12)
  love.graphics.setColor(1,0.9,0.6,0.8)
  love.graphics.rectangle("line", x, y, w, h, 12,12)

  local pad = 14
  local titleY = y + pad
  love.graphics.setColor(1,1,1,0.95)
  love.graphics.print("Select images", x+pad, titleY)

  -- sidebar
  local sidebarW = 220
  rectSidebar = { x=x+pad, y=titleY+28, w=sidebarW, h=h - (titleY+28) - 70 }
  love.graphics.setColor(0.12,0.12,0.18,1)
  love.graphics.rectangle("fill", rectSidebar.x, rectSidebar.y, rectSidebar.w, rectSidebar.h, 8,8)
  love.graphics.setColor(1,1,1,0.25)
  love.graphics.rectangle("line", rectSidebar.x, rectSidebar.y, rectSidebar.w, rectSidebar.h, 8,8)

  local sx = rectSidebar.x + 10
  local sy = rectSidebar.y + 8
  sideRects = {}

  local function drawLinkRow(lbl, path, src)
    local lh = 22
    local rx = sx; local ry = sy; local rw = rectSidebar.w - 20; local rh = lh
    local mx,my = love.mouse.getPosition()
    local hot = (mx>=rx and mx<=rx+rw and my>=ry and my<=ry+rh)
    love.graphics.setColor(1,1,1, hot and 0.10 or 0.05); love.graphics.rectangle("fill", rx, ry, rw, rh, 6,6)
    love.graphics.setColor(1,1,1,0.85); love.graphics.print(lbl, rx+8, ry+4)
    sy = sy + lh + 4
    sideRects[#sideRects+1] = { x=rx,y=ry,w=rw,h=rh,path=path,src=src,label=lbl }
  end

  love.graphics.setColor(1,1,1,0.85); love.graphics.print("Quick Access", sx, sy); sy = sy + 18
  for _,q in ipairs(defaultLinks) do
    if q._src ~= "drive" then drawLinkRow(q.label, q.path, q._src or "default") end
  end

  if #favLinks > 0 then
    sy = sy + 6
    love.graphics.setColor(1,1,1,0.85); love.graphics.print("Favorites", sx, sy); sy = sy + 18
    for _,q in ipairs(favLinks) do drawLinkRow(q.label, q.path, "fav") end
  end

  local hasDrives = false
  for _,q in ipairs(defaultLinks) do if q._src == "drive" then hasDrives = true; break end end
  if hasDrives then
    sy = sy + 6
    love.graphics.setColor(1,1,1,0.85); love.graphics.print("Drives", sx, sy); sy = sy + 18
    for _,q in ipairs(defaultLinks) do if q._src == "drive" then drawLinkRow(q.label, q.path, "drive") end end
  end

  -- path bar + Up + Toggle (to the right of sidebar)
  local contentX = rectSidebar.x + rectSidebar.w + 10
  local contentW = w - (contentX - x) - pad
  local barY, barH = titleY+18, 26
  rectPath = { x=contentX, y=barY, w=contentW - 220, h=barH }
  love.graphics.setColor(0.12,0.12,0.18,1)
  love.graphics.rectangle("fill", rectPath.x, rectPath.y, rectPath.w, rectPath.h, 6,6)
  love.graphics.setColor(1,1,1,0.25)
  love.graphics.rectangle("line", rectPath.x, rectPath.y, rectPath.w, rectPath.h, 6,6)
  love.graphics.setColor(1,1,1,0.85)
  love.graphics.print(cwd or "", rectPath.x+8, rectPath.y+5)

  local upW = 70
  rectUp = { x=rectPath.x + rectPath.w + 8, y=rectPath.y, w=upW, h=barH }
  love.graphics.setColor(0.16,0.16,0.22,1)
  love.graphics.rectangle("fill", rectUp.x, rectUp.y, rectUp.w, rectUp.h, 6,6)
  love.graphics.setColor(1,1,1,0.85)
  love.graphics.printf("↑ Up", rectUp.x, rectUp.y+5, rectUp.w, "center")

  local toggTxt = (layout == "grid") and "List" or "Grid"
  local font = love.graphics.getFont()
  local toggW = font:getWidth(toggTxt) + 20
  rectToggle = { x=rectUp.x + rectUp.w + 8, y=rectUp.y, w=toggW, h=barH }
  love.graphics.setColor(0.16,0.16,0.22,1)
  love.graphics.rectangle("fill", rectToggle.x, rectToggle.y, rectToggle.w, rectToggle.h, 6,6)
  love.graphics.setColor(1,1,1,0.85)
  love.graphics.printf(toggTxt, rectToggle.x, rectToggle.y+5, rectToggle.w, "center")

  -- list/grid area
  local listX, listY = contentX, rectPath.y + rectPath.h + 10
  local listW, listH = contentW, h - (rectPath.y + rectPath.h + 10) - 70
  rectList = { x=listX, y=listY, w=listW, h=listH }

  love.graphics.setColor(0.12,0.12,0.18,1)
  love.graphics.rectangle("fill", listX, listY, listW, listH, 8,8)
  love.graphics.setColor(1,1,1,0.25)
  love.graphics.rectangle("line", listX, listY, listW, listH, 8,8)

  itemRects = {}

  if layout == "list" then
    local itemH = 26
    local totalH = (#entries) * itemH
    local maxScroll = math.max(0, totalH - listH)
    scroll = clamp(scroll, 0, maxScroll)

    love.graphics.setScissor(listX, listY, listW, listH)
    love.graphics.push(); love.graphics.translate(0, -scroll)

    local mx,my = love.mouse.getPosition()
    for i,e in ipairs(entries) do
      local iy = listY + (i-1)*itemH
      local yOnScreen = iy - scroll
      local hot = (mx>=listX and mx<=listX+listW and my>=yOnScreen and my<=yOnScreen+itemH)
      if hot then
        love.graphics.setColor(1,1,1,0.06)
        love.graphics.rectangle("fill", listX+1, iy, listW-2, itemH)
      end
      local tag = e.isDir and "[DIR] " or (e.isImg and "[IMG] " or "[   ] ")
      love.graphics.setColor(1,1,1,0.88)
      love.graphics.print(tag .. e.name, listX+8, iy+6)
      if sel[e.path] then
        love.graphics.setColor(0.95,0.74,0.25,0.9)
        love.graphics.print("✓", listX + listW - 20, iy+6)
      end
      itemRects[#itemRects+1] = { x=listX, y=yOnScreen, w=listW, h=itemH, idx=i }
    end

    love.graphics.pop(); love.graphics.setScissor()

  else
    -- grid
    local gridPad = 10
    local cellW, cellH = 140, 150
    local thumbH = 110
    local cols = math.max(1, math.floor((listW - gridPad*2) / (cellW + gridPad)))
    local rows = math.ceil(#entries / cols)
    local totalH = gridPad + rows*(cellH + gridPad)
    local maxScroll = math.max(0, totalH - listH)
    scroll = clamp(scroll, 0, maxScroll)

    love.graphics.setScissor(listX, listY, listW, listH)
    love.graphics.push(); love.graphics.translate(0, -scroll)

    local startX = listX + gridPad
    local xcur = startX
    local ycur = listY + gridPad
    local mx,my = love.mouse.getPosition()

    for i,e in ipairs(entries) do
      local onScreenY = ycur - scroll
      local rect = { x = xcur, y = onScreenY, w = 140, h = 150, idx = i }
      itemRects[#itemRects+1] = rect

      local hot = (mx>=rect.x and mx<=rect.x+rect.w and my>=rect.y and my<=rect.y+rect.h)
      love.graphics.setColor(1,1,1, hot and 0.08 or 0.04)
      love.graphics.rectangle("fill", xcur, ycur, rect.w, rect.h, 10,10)
      love.graphics.setColor(1,1,1,0.15)
      love.graphics.rectangle("line", xcur, ycur, rect.w, rect.h, 10,10)

      if e.isDir then
        love.graphics.setColor(1,0.88,0.45, 0.22)
        love.graphics.rectangle("fill", xcur+16, ycur+16, rect.w-32, thumbH-12, 8,8)
        love.graphics.setColor(1,0.88,0.45, 0.65)
        love.graphics.rectangle("line", xcur+16, ycur+16, rect.w-32, thumbH-12, 8,8)
      elseif e.isImg then
        local padX, padY = 12, 8
        local maxThumbW, maxThumbH = rect.w - padX*2, thumbH
        local th = loadThumb(e.path, maxThumbW, maxThumbH)
        if th and th.img then
          love.graphics.setColor(1,1,1,1)
          local dx = xcur + (rect.w - th.w) / 2
          local dy = ycur + padY + (maxThumbH - th.h) / 2
          love.graphics.draw(th.img, dx, dy, 0, th.scale, th.scale)
        elseif th and th.unsupported then
          love.graphics.setColor(1,1,1,0.06)
          love.graphics.rectangle("fill", xcur+padX, ycur+padY, maxThumbW, maxThumbH, 6,6)
          love.graphics.setColor(1,0.75,0.6,0.95)
          love.graphics.printf("No preview: "..(th.ext or "?"):upper(), xcur+8, ycur+padY + maxThumbH/2 - 6, rect.w-16, "center")
        else
          love.graphics.setColor(1,1,1,0.06)
          love.graphics.rectangle("fill", xcur+padX, ycur+padY, maxThumbW, maxThumbH, 6,6)
          love.graphics.setColor(1,0.6,0.6,0.85)
          love.graphics.printf("Preview failed", xcur+8, ycur+padY + maxThumbH/2 - 6, rect.w-16, "center")
        end
      end

      local name = e.name or ""
      love.graphics.setColor(1,1,1,0.78)
      local maxTextW = rect.w - 12
      local shown = name
      local fnt = love.graphics.getFont()
      if fnt and fnt.getWidth then
        while fnt:getWidth(shown) > maxTextW and #shown > 4 do shown = shown:sub(1, -2) end
      end
      if shown ~= name then shown = shown .. "…" end
      love.graphics.printf(shown, xcur+6, ycur + rect.h - 24, maxTextW, "center")

      if sel[e.path] then
        love.graphics.setColor(0.95,0.74,0.25,0.95)
        love.graphics.printf("✓", xcur, ycur+6, rect.w-6, "right")
        love.graphics.setColor(0.95,0.74,0.25,0.55)
        love.graphics.rectangle("line", xcur, ycur, rect.w, rect.h, 10,10)
      end

      xcur = xcur + rect.w + 10
      if (i % math.max(1, math.floor((listW - 20) / (rect.w + 10)))) == 0 then
        xcur = startX
        ycur = ycur + rect.h + 10
      end
    end

    love.graphics.pop(); love.graphics.setScissor()
  end

  -- buttons
  local btnY = y + h - 48
  local count = selectionCount()
  local impTxt = ("Import (%d)"):format(count)
  local canTxt = "Cancel"
  local font = love.graphics.getFont()
  local impW  = font:getWidth(impTxt) + 24
  local canW  = font:getWidth(canTxt) + 24
  rectImport = { x=x + w - impW - canW - 20, y=btnY, w=impW, h=34 }
  rectCancel = { x=x + w - canW - 10,        y=btnY, w=canW, h=34 }

  local hasSel = count > 0
  love.graphics.setColor(0.2,0.28,0.22, hasSel and 0.95 or 0.40)
  love.graphics.rectangle("fill", rectImport.x, rectImport.y, rectImport.w, rectImport.h, 8,8)
  love.graphics.setColor(0.95,0.74,0.25,0.9)
  love.graphics.rectangle("line", rectImport.x, rectImport.y, rectImport.w, rectImport.h, 8,8)
  love.graphics.setColor(1,1,1, hasSel and 0.95 or 0.50)
  love.graphics.printf(impTxt, rectImport.x, rectImport.y+8, rectImport.w, "center")

  love.graphics.setColor(0.22,0.18,0.18,0.95)
  love.graphics.rectangle("fill", rectCancel.x, rectCancel.y, rectCancel.w, rectCancel.h, 8,8)
  love.graphics.setColor(0.95,0.74,0.25,0.9)
  love.graphics.rectangle("line", rectCancel.x, rectCancel.y, rectCancel.w, rectCancel.h, 8,8)
  love.graphics.setColor(1,1,1,0.95)
  love.graphics.printf(canTxt, rectCancel.x, rectCancel.y+8, rectCancel.w, "center")

  -- context menu (on top)
  drawContextMenu()
end

-- --------------- build links on module load ---------------
local function rebuildSidebar()
  buildDefaultLinks()
  loadFavorites()
end

-- --------------- input ---------------
function M.open(startPath)
  importClicked = false
  open = true
  sel = {}
  layout = "grid"
  rebuildSidebar()
  scan(startPath or homeDir())
end

function M.close() open = false; ctx.open=false end
function M.isOpen() return open end

function M.mousepressed(x, y, button)
  if not open then return false end

  -- Right-click: open context menu (and eat the click)
  if button == 2 then
    ctx.open = false

    -- RMB on sidebar row?
    for _, r in ipairs(sideRects or {}) do
      if inside(x, y, r) then
        if r.src == "fav" then
          ctx = {
            open = true, x = x, y = y, target = r,
            items = {
              { label = "Remove from sidebar", fn = function() removeFavoriteByPath(r.path) end },
              { label = "Open", fn = function() scan(r.path) end },
            }
          }
        else
          ctx = {
            open = true, x = x, y = y, target = r,
            items = { { label = "Open", fn = function() scan(r.path) end } }
          }
        end
        return true
      end
    end

    -- RMB on a directory entry in list/grid?
    if rectList and inside(x, y, rectList) then
      for _, r in ipairs(itemRects or {}) do
        if inside(x, y, r) then
          local e = entries[r.idx]
          if e and e.isDir then
            ctx = {
              open = true, x = x, y = y, target = { path = e.path, label = e.name },
              items = {
                { label = "Add to sidebar", fn = function() addFavorite(e.name, e.path) end },
                { label = "Open", fn = function() scan(e.path) end },
              }
            }
            return true
          end
        end
      end
    end

    -- RMB on empty area: just close any menu
    ctx.open = false
    return true
  end

  -- Left click on an open context menu?
  if ctx.open and ctxClick(x, y) then
    return true
  end

  -- Sidebar navigation (LMB)
  for _, r in ipairs(sideRects or {}) do
    if inside(x, y, r) then
      scan(r.path)
      return true
    end
  end

  -- We only handle LMB below
  if button ~= 1 then return false end

  if rectUp and inside(x, y, rectUp) then
    scan(parentOf(cwd))
    return true
  end

  if rectToggle and inside(x, y, rectToggle) then
    layout = (layout == "grid") and "list" or "grid"
    scroll = 0
    return true
  end

  if rectImport and inside(x, y, rectImport) then
    importClicked = true
    dprint("Import clicked. Selected:", #M.getSelection())
    M.close()
    return true
  end

  if rectCancel and inside(x, y, rectCancel) then
    sel = {}
    dprint("Cancel clicked. Selection cleared.")
    M.close()
    return true
  end

  if rectList and inside(x, y, rectList) and itemRects then
    for _, r in ipairs(itemRects) do
      if inside(x, y, r) then
        local e = entries[r.idx]
        if e then
          if e.isDir then
            scan(e.path)
          elseif e.isImg then
            sel[e.path] = not sel[e.path] or nil
          end
        end
        return true
      end
    end
  end

  return false
end

function M.wheelmoved(dx, dy)
  if not open or not rectList then return end
  local mx,my = love.mouse.getPosition()
  if inside(mx,my,rectList) then
    local step = (layout == "list") and 120 or 160
    scroll = clamp(scroll + (dy<0 and step or -step), 0, 10^9)
  end
end

return M
