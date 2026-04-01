-- memory_store.lua
-- Lightweight persistence for memories and links using Lua chunk files.

local MemoryStore = {}

local SAVE_FILE_MEMS  = "user_memories.lua"
local SAVE_FILE_LINKS = "user_links.lua"

-- --- utils ---------------------------------------------------------------

local function esc(str)
  return tostring(str)
    :gsub("\\", "\\\\")
    :gsub("\r", "\\r")
    :gsub("\n", "\\n")
    :gsub("\"", "\\\"")
end

local function serializeValue(v)
  local tv = type(v)
  if tv == "string" then
    return '"' .. esc(v) .. '"'
  elseif tv == "number" or tv == "boolean" then
    return tostring(v)
  elseif tv == "table" then
    local parts = {}
    -- detect simple array (1..n)
    local isArray, n = true, 0
    for k,_ in pairs(v) do
      if type(k) ~= "number" then isArray = false break end
      if k > n then n = k end
    end
    if isArray then
      for i = 1, n do
        parts[#parts+1] = serializeValue(v[i])
      end
    else
      for k, val in pairs(v) do
        local key
        if type(k) == "string" and k:match("^[_%a][_%w]*$") then
          key = k .. "="
        else
          key = "[" .. serializeValue(k) .. "]="
        end
        parts[#parts+1] = key .. serializeValue(val)
      end
    end
    return "{" .. table.concat(parts, ",") .. "}"
  else
    return "nil"
  end
end

local function safeLoadTable(path)
  local info = love.filesystem.getInfo(path)
  if not info then return nil end
  local chunk, err = love.filesystem.load(path)
  if not chunk then
    print("[MemoryStore] load error:", err)
    return nil
  end
  local ok, t = pcall(chunk)
  if not ok then
    print("[MemoryStore] eval error:", t)
    return nil
  end
  if type(t) ~= "table" then return nil end
  return t
end

local function writeTable(path, tbl)
  local chunkStr = "return " .. serializeValue(tbl or {})
  local ok, err = love.filesystem.write(path, chunkStr)
  if not ok then
    print("[MemoryStore] save error (" .. path .. "):", err)
  end
end

-- tolerant id equality (handles number vs string)
local function idsEqual(a, b)
  if a == nil or b == nil then return false end
  return tostring(a) == tostring(b)
end

-- --- bundled helpers (for first-run seeding / pruning) --------------------

local function getBundled()
  local ok, mod = pcall(require, "data.memories")
  if not ok or type(mod) ~= "table" then return nil end
  return mod
end

local function buildIdSetFrom(tbl)
  local have = {}
  for _, m in ipairs(tbl or {}) do
    if m and m.id ~= nil then
      have[tostring(m.id)] = true
    end
  end
  return have
end

local function buildIdSetPreferSavedThenBundled(bundledMemories)
  local saved = safeLoadTable(SAVE_FILE_MEMS)
  if type(saved) == "table" and #saved > 0 then
    return buildIdSetFrom(saved)
  end
  local src = bundledMemories
  if not src then
    local B = getBundled()
    src = (B and B.memories) or {}
  end
  return buildIdSetFrom(src)
end

local function pruneLinksTable(links, idSet)
  local have = idSet or buildIdSetPreferSavedThenBundled(nil)
  local seen, out = {}, {}
  for _, L in ipairs(links or {}) do
    if L and L.a ~= nil and L.b ~= nil then
      local a, b = tostring(L.a), tostring(L.b)
      if a ~= b and have[a] and have[b] then
        local k = (a < b) and (a .. "|" .. b) or (b .. "|" .. a)
        if not seen[k] then
          seen[k] = true
          out[#out+1] = { a = L.a, b = L.b }
        end
      end
    end
  end
  return out
end

-- --- migration helpers ----------------------------------------------------

local function migrateMemoryRow(m)
  if type(m) ~= "table" then return false end
  local changed = false

  -- Old versions sometimes wrote body into subtitle or left text nil.
  -- If we have a proper body in `memory`, ensure `text` mirrors it.
if m.memory and (m.text == nil or m.text == m.subtitle) then
  m.text = m.memory
  -- Clear subtitle if it was the same as the main content
  if m.subtitle == m.memory then
    m.subtitle = nil
  end
  changed = true
end

  -- Normalize color arrays if they were 0..255
  if m.style and m.style.color and type(m.style.color) == "table" then
    local c = m.style.color
    local r,g,b = c[1], c[2], c[3]
    if r and g and b and (r > 1 or g > 1 or b > 1) then
      m.style.color = { r/255, g/255, b/255, (c[4] and ((c[4] > 1) and (c[4]/255) or c[4])) or nil }
      changed = true
    end
  end

  return changed
end

local function migrateMemoriesList(list)
  local changed = false
  for _, m in ipairs(list or {}) do
    if migrateMemoryRow(m) then changed = true end
  end
  return changed
end

-----------------------------------------------------------------------
-- public: memories
-----------------------------------------------------------------------

function MemoryStore.save(memories)
  writeTable(SAVE_FILE_MEMS, memories or {})
end

function MemoryStore.load(bundled)
  -- try saved first
  local saved = safeLoadTable(SAVE_FILE_MEMS)
  if type(saved) == "table" and #saved > 0 then
    -- migrate in-place if needed
    if migrateMemoriesList(saved) then
      writeTable(SAVE_FILE_MEMS, saved)
    end
    return saved
  end

  -- seed from bundled (argument) or data.memories
  local source
  if type(bundled) == "table" and type(bundled.memories) == "table" then
    source = bundled.memories
  elseif type(bundled) == "table" and bundled[1] ~= nil then
    source = bundled
  else
    local B = getBundled()
    source = B and (B.memories or B) or {}
  end

  local seed = {}
  if type(source) == "table" then
    for i = 1, #source do
      seed[i] = source[i]
    end
  end

  -- migrate seed (just in case the bundled has older fields)
  migrateMemoriesList(seed)
  writeTable(SAVE_FILE_MEMS, seed or {})
  return seed
end

function MemoryStore.add(current, mem)
  table.insert(current, mem)
  MemoryStore.save(current)
end

function MemoryStore.update(current, updated)
  if not updated or updated.id == nil then return end
  local found = false
  for i = 1, #current do
    if idsEqual(current[i].id, updated.id) then
      current[i] = updated
      found = true
      break
    end
  end
  if not found then
    table.insert(current, updated)
  end
  MemoryStore.save(current)
end

function MemoryStore.remove(current, id)
  if id == nil then return end
  for i = #current, 1, -1 do
    if idsEqual(current[i].id, id) then
      table.remove(current, i)
      break
    end
  end
  MemoryStore.save(current)
end

-----------------------------------------------------------------------
-- public: links
-----------------------------------------------------------------------

-- normalized, order-independent key (works for number or string ids)
local function linkKey(a, b)
  if a == nil or b == nil then return nil end
  local sa, sb = tostring(a), tostring(b)
  if sa == sb then return nil end
  if sa > sb then sa, sb = sb, sa end
  return sa .. "|" .. sb
end

function MemoryStore.loadLinks(bundledOrLinks, bundledMemories)
  -- Accept either:
  --   loadLinks()                                -- use saved or data.memories
  --   loadLinks(bundled)                         -- where bundled has .links/.memories
  --   loadLinks(links, memories)                 -- two arrays
  local providedLinks, providedMems
  if type(bundledOrLinks) == "table" and (bundledOrLinks.memories or bundledOrLinks.links) then
    providedLinks = bundledOrLinks.links
    providedMems  = bundledOrLinks.memories
  else
    providedLinks = bundledOrLinks
    providedMems  = bundledMemories
  end

  local saved = safeLoadTable(SAVE_FILE_LINKS)

  -- Seed from bundled when missing/empty
  if (not saved) or #saved == 0 then
    local seedL = providedLinks
    if not seedL then
      local B = getBundled()
      seedL = B and B.links or {}
      providedMems = providedMems or (B and B.memories) or {}
    end
    saved = {}
    for i, L in ipairs(seedL or {}) do
      if L and L.a ~= nil and L.b ~= nil then
        saved[i] = { a = L.a, b = L.b }
      end
    end
  end

  -- Build an ID set to prune with:
  -- prefer saved memories; if none yet, prefer provided (bundled) memories; else fall back to data.memories
  local idSet
  local savedMems = safeLoadTable(SAVE_FILE_MEMS)
  if type(savedMems) == "table" and #savedMems > 0 then
    idSet = buildIdSetFrom(savedMems)
  elseif type(providedMems) == "table" then
    idSet = buildIdSetFrom(providedMems)
  else
    local B = getBundled()
    idSet = buildIdSetFrom(B and B.memories or {})
  end

  local pruned = pruneLinksTable(saved, idSet)
  writeTable(SAVE_FILE_LINKS, pruned)
  return pruned
end

function MemoryStore.saveLinks(links, bundledMemories)
  local idSet = buildIdSetPreferSavedThenBundled(bundledMemories)
  writeTable(SAVE_FILE_LINKS, pruneLinksTable(links or {}, idSet))
end

-- optionally, a helper to replace all links at once (already normalized)
function MemoryStore.replaceAllLinks(links, bundledMemories)
  MemoryStore.saveLinks(links, bundledMemories)
end

return MemoryStore
