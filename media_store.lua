-- media_store.lua — stage images until memory is saved; then commit or discard
-- Saves ONLY inside love.filesystem (e.g. %AppData%/LOVE/<game>/)
-- API: beginSession(), discardSession(), stageImportAbs(absPath),
--      stageImportDropped(file), removeStaged(rel), commit(memId, existing, staged, removedExistingSet),
--      deleteFor(memId)

local M = {}
local lf = love.filesystem

-- ------- small utils -------
local function join(a,b) return (tostring(a or "") .. "/" .. tostring(b or "")):gsub("//+","/") end
local function ensureDir(path) if lf.getInfo(path,"directory") then return true end return lf.createDirectory(path) end
local function baseName(p) p=tostring(p or ""):gsub("\\","/"); local i=p:match(".*()/"); return i and p:sub(i+1) or p end

--
local ok_ffi, ffi = pcall(require, "ffi")
local SEP = package.config:sub(1,1)
local isWindows = (SEP == '\\')

if isWindows and ok_ffi then
  local need = not pcall(ffi.typeof, "HANDLE")
  if need then
    ffi.cdef[[
      typedef void* HANDLE;
      typedef int BOOL;
      typedef unsigned long DWORD;
      typedef const uint16_t* LPCWSTR;
      HANDLE __stdcall CreateFileW(LPCWSTR, DWORD, DWORD, void*, DWORD, DWORD, HANDLE);
      BOOL   __stdcall ReadFile(HANDLE, void*, DWORD, DWORD*, void*);
      BOOL   __stdcall CloseHandle(HANDLE);
    ]]
  end
end

local bitlib = bit or require("bit")
local band, bor, rshift, lshift = bitlib.band, bitlib.bor, bitlib.rshift, bitlib.lshift

local function utf8_to_utf16le_buf(s)
  if not ok_ffi then return nil end
  local u16 = ffi.new("uint16_t[?]", (#s * 2) + 1)
  local i, out = 1, 0
  while i <= #s do
    local b = s:byte(i); i = i + 1
    local cp
    if b < 0x80 then
      cp = b
    elseif band(b,0xE0) == 0xC0 then
      local b2 = s:byte(i) or 0; i = i + 1
      cp = bor(lshift(band(b,0x1F),6), band(b2,0x3F))
    elseif band(b,0xF0) == 0xE0 then
      local b2 = s:byte(i) or 0; local b3 = s:byte(i+1) or 0; i = i + 2
      cp = bor(lshift(band(b,0x0F),12), lshift(band(b2,0x3F),6), band(b3,0x3F))
    else
      local b2 = s:byte(i) or 0; local b3 = s:byte(i+1) or 0; local b4 = s:byte(i+2) or 0; i = i + 3
      cp = bor(lshift(band(b,0x07),18), lshift(band(b2,0x3F),12), lshift(band(b3,0x3F),6), band(b4,0x3F))
    end
    if cp < 0x10000 then
      u16[out] = cp; out = out + 1
    else
      cp = cp - 0x10000
      u16[out] = 0xD800 + rshift(cp,10); out = out + 1
      u16[out] = 0xDC00 + band(cp,0x3FF); out = out + 1
    end
  end
  u16[out] = 0
  return u16
end

-- read bytes from absolute OS path (Unicode-safe on Windows)
local function readAbsFile(absPath)
  if not (absPath and absPath ~= "") then return nil, "no path" end

  if not isWindows or not ok_ffi then
    local f = io.open(absPath, "rb"); if not f then return nil, "open fail" end
    local bytes = f:read("*a"); f:close()
    if not bytes or #bytes == 0 then return nil, "io-empty" end
    return bytes
  end

  local GENERIC_READ   = 0x80000000
  local FILE_SHARE_R_W = 0x00000001 + 0x00000002
  local OPEN_EXISTING  = 3
  local FILE_ATTR_NORM = 0x00000080

  local wbuf = utf8_to_utf16le_buf((absPath or ""):gsub("/", "\\"))
  local h = ffi.C.CreateFileW(wbuf, GENERIC_READ, FILE_SHARE_R_W, nil, OPEN_EXISTING, FILE_ATTR_NORM, nil)
  if h == nil or h == ffi.cast("HANDLE", -1) then
    return nil, "CreateFileW-fail"
  end

  local parts = {}
  local CHUNK = 65536
  while true do
    local tmp = ffi.new("uint8_t[?]", CHUNK)
    local read = ffi.new("DWORD[1]", 0)
    local ok = ffi.C.ReadFile(h, tmp, CHUNK, read, nil)
    if ok == 0 then break end
    local n = tonumber(read[0])
    if n == 0 then break end
    parts[#parts+1] = ffi.string(tmp, n)
  end
  ffi.C.CloseHandle(h)

  local s = table.concat(parts)
  if #s == 0 then return nil, "io-empty" end
  return s
end

local function readDroppedFile(file)  -- love File object from love.filedropped
  local ok, data = pcall(file.read, file)
  if ok and data then return data end
  return nil, "read fail"
end

-- tiny FNV-1a-ish hash for filenames
local bxor, band2, tobit = bitlib.bxor, bitlib.band, bitlib.tobit
local function tinyHash(s)
  local h = 2166136261
  for i=1,#s do h = tobit(bxor(h, s:byte(i)) * 16777619) end
  return string.format("%08x", band2(h, 0xffffffff))
end

-- ------- layout in save dir -------
local ROOT        = "media"
local STAGED_ROOT = ROOT .. "/staged"
local PERM_ROOT   = ROOT .. "/mem"

local function initRoots()
  ensureDir(ROOT); ensureDir(STAGED_ROOT); ensureDir(PERM_ROOT)
end

-- pick an extension we support, default .png
local function pickExt(name)
  local lower = (name or ""):lower()
  return lower:match("(%.png)$")
      or lower:match("(%.jpe?g)$")
      or lower:match("(%.bmp)$")
      or lower:match("(%.webp)$")
      or ".png"
end

local function writeBytes(relPath, bytes)
  local ok, err = lf.write(relPath, bytes)
  if not ok then return false, err end
  return true
end

-- ------- session -------
local sessionActive = false

function M.beginSession()
  initRoots()
  sessionActive = true
  return true
end

function M.discardSession()
  if lf.getInfo(STAGED_ROOT, "directory") then
    for _,leaf in ipairs(lf.getDirectoryItems(STAGED_ROOT)) do
      lf.remove(join(STAGED_ROOT, leaf))
    end
  end
  sessionActive = false
end

-- ------- staging imports -------
local function writeStaged(bytes, srcName)
  if not bytes then return nil end
  initRoots()
  local ext  = pickExt(srcName or "image.png")
  local leaf = tinyHash((srcName or "img") .. ":" .. tostring(os.time()) .. ":" .. tostring(math.random())) .. ext
  local rel  = join(STAGED_ROOT, leaf)
  local ok = writeBytes(rel, bytes)
  if not ok then return nil end
  return rel
end

function M.stageImportAbs(absPath)
  if not sessionActive then M.beginSession() end
  local bytes = readAbsFile(absPath); if not bytes then return nil end
  return writeStaged(bytes, baseName(absPath))
end

function M.stageImportDropped(file)
  if not sessionActive then M.beginSession() end
  if not file or type(file) ~= "userdata" or not file.getFilename then return nil end
  local bytes = readDroppedFile(file); if not bytes then return nil end
  return writeStaged(bytes, baseName(file:getFilename()))
end

function M.removeStaged(relPath)
  if not relPath then return end
  lf.remove(relPath)
end

-- ------- commit / delete -------
-- Move staged -> media/mem/<memId>/ ; keep existing minus removedExistingSet
function M.commit(memId, existing, staged, removedExistingSet)
  initRoots()
  memId = tostring(memId or "u")
  local bucket = join(PERM_ROOT, memId)
  ensureDir(bucket)

  local finalList = {}

  -- keep existing that aren't removed (delete the removed ones)
  for _,rel in ipairs(existing or {}) do
    if removedExistingSet and removedExistingSet[rel] then
      lf.remove(rel)
    else
      finalList[#finalList+1] = rel
    end
  end

  -- move staged into bucket (copy->write, then delete)
  for _,rel in ipairs(staged or {}) do
    local bytes = lf.read(rel)
    if bytes then
      local ext  = pickExt(baseName(rel))
      local leaf = tinyHash(baseName(rel) .. ":" .. tostring(os.time()) .. ":" .. tostring(math.random())) .. ext
      local dst  = join(bucket, leaf)
      local ok = writeBytes(dst, bytes)
      if ok then
        lf.remove(rel)
        finalList[#finalList+1] = dst
      end
    end
  end

  sessionActive = false
  return finalList
end

-- Delete ALL media for a memory id
function M.deleteFor(memId)
  memId = tostring(memId or "u")
  local bucket = join(PERM_ROOT, memId)
  if not lf.getInfo(bucket, "directory") then return end
  for _,leaf in ipairs(lf.getDirectoryItems(bucket)) do
    lf.remove(join(bucket, leaf))
  end
  lf.remove(bucket)
end

return M
