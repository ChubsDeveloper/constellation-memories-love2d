-- fx/presets.lua
local U = require("core.utils")

local M = {}

local function PRESETS(CONFIG)
  -- Helper to reuse CONFIG values cleanly
  local function I() return CONFIG.NEBULA_INTENSITY end

  return {
    -- Originals
    orion = {
      colors = { {0.20,0.60,1.00}, {1.00,0.45,0.10}, {0.85,0.20,0.90} },
      intensity = I(), scale = {2.5,2.5}, layers = 4, warp = 0.35,
      thresholds = {low=0.25, high=0.85}, depthFalloff = 0.80,
    },
    eagle = {
      colors = { {0.25,0.85,0.90}, {1.00,0.60,0.20}, {0.60,0.20,0.80} },
      intensity = I(), scale = {2.2,2.2}, layers = 5, warp = 0.40,
      thresholds = {low=0.26, high=0.86}, depthFalloff = 0.85,
    },
    carina = {
      colors = { {0.90,0.30,0.35}, {0.20,0.50,1.00}, {1.00,0.80,0.40} },
      intensity = I(), scale = {2.8,2.0}, layers = 5, warp = 0.45,
      thresholds = {low=0.30, high=0.86}, depthFalloff = 0.80,
    },
    tarantula = {
      colors = { {0.10,0.90,0.70}, {1.00,0.30,0.60}, {1.00,0.80,0.30} },
      intensity = I(), scale = {3.0,2.2}, layers = 5, warp = 0.50,
      thresholds = {low=0.28, high=0.88}, depthFalloff = 0.75,
    },
    veil = {
      colors = { {0.20,0.80,0.90}, {0.70,0.50,1.00}, {0.95,0.95,1.00} },
      intensity = I(), scale = {2.0,2.8}, layers = 4, warp = 0.25,
      thresholds = {low=0.22, high=0.80}, depthFalloff = 0.90,
    },
    andromeda = {
      colors = { {0.40,0.60,1.00}, {0.90,0.60,0.70}, {0.90,0.80,0.60} },
      intensity = I(), scale = {1.8,2.0}, layers = 3, warp = 0.20,
      thresholds = {low=0.24, high=0.82}, depthFalloff = 0.85,
    },

    -- 🔥 New “wow” presets
    pillars = { -- deep blues + ember cores, pronounced depth
      colors = { {0.10,0.35,0.95}, {1.00,0.55,0.15}, {0.65,0.10,0.85} },
      intensity = I(), scale = {2.6,3.2}, layers = 6, warp = 0.55,
      thresholds = {low=0.22, high=0.90}, depthFalloff = 0.92,
    },
    horsehead = { -- dusty magentas + cyan wisps, wide clouds
      colors = { {0.85,0.30,0.55}, {0.10,0.85,0.95}, {0.98,0.85,0.60} },
      intensity = I(), scale = {3.6,2.4}, layers = 6, warp = 0.42,
      thresholds = {low=0.30, high=0.86}, depthFalloff = 0.88,
    },
    helix = { -- teal to lime, subtle warp, very layered gas
      colors = { {0.20,0.85,0.85}, {0.70,1.00,0.35}, {0.95,0.95,1.00} },
      intensity = I(), scale = {2.1,2.1}, layers = 6, warp = 0.28,
      thresholds = {low=0.18, high=0.82}, depthFalloff = 0.95,
    },
    trifid = { -- tri-split hues, lively warp
      colors = { {0.20,0.70,1.00}, {1.00,0.45,0.55}, {0.90,0.85,0.35} },
      intensity = I(), scale = {2.4,2.8}, layers = 5, warp = 0.52,
      thresholds = {low=0.24, high=0.87}, depthFalloff = 0.82,
    },
    lagoon = { -- turquoise fog + warm core
      colors = { {0.10,0.85,0.85}, {1.00,0.55,0.25}, {0.95,0.85,0.65} },
      intensity = I(), scale = {2.9,2.2}, layers = 5, warp = 0.48,
      thresholds = {low=0.26, high=0.88}, depthFalloff = 0.86,
    },
    cygnus = { -- purple river with electric blue edges
      colors = { {0.55,0.20,0.85}, {0.15,0.70,1.00}, {1.00,0.80,0.50} },
      intensity = I(), scale = {3.0,2.6}, layers = 6, warp = 0.60,
      thresholds = {low=0.28, high=0.90}, depthFalloff = 0.80,
    },
    witchhead = { -- ghostly teal/blue, high falloff for “face” feel
      colors = { {0.50,0.85,1.00}, {0.85,0.90,1.00}, {0.35,0.55,1.00} },
      intensity = I(), scale = {2.3,3.0}, layers = 4, warp = 0.22,
      thresholds = {low=0.20, high=0.80}, depthFalloff = 0.96,
    },
    catspaw = { -- emerald + gold claws
      colors = { {0.20,0.95,0.65}, {1.00,0.80,0.30}, {0.85,0.30,0.90} },
      intensity = I(), scale = {2.6,2.6}, layers = 5, warp = 0.46,
      thresholds = {low=0.25, high=0.86}, depthFalloff = 0.88,
    },
    rose = { -- rose gold bloom, gentle warp
      colors = { {1.00,0.55,0.65}, {1.00,0.80,0.55}, {0.85,0.30,0.50} },
      intensity = I(), scale = {2.0,2.6}, layers = 4, warp = 0.24,
      thresholds = {low=0.22, high=0.82}, depthFalloff = 0.92,
    },
    aurora = { -- aurora-like ribbons
      colors = { {0.15,0.90,0.60}, {0.20,0.65,1.00}, {0.95,0.95,1.00} },
      intensity = I(), scale = {1.8,3.2}, layers = 6, warp = 0.62,
      thresholds = {low=0.18, high=0.84}, depthFalloff = 0.90,
    },

    -- Stylized vibes
    synthwave = { -- neon magenta/teal, bold warp
      colors = { {1.00,0.20,0.70}, {0.10,0.90,0.95}, {1.00,0.85,0.30} },
      intensity = I(), scale = {2.2,2.2}, layers = 5, warp = 0.65,
      thresholds = {low=0.26, high=0.86}, depthFalloff = 0.78,
    },
    noir = { -- moody desaturated, high depth falloff
      colors = { {0.35,0.45,0.55}, {0.55,0.55,0.65}, {0.85,0.85,0.90} },
      intensity = I(), scale = {2.6,2.6}, layers = 4, warp = 0.22,
      thresholds = {low=0.24, high=0.78}, depthFalloff = 0.98,
    },
    emberstorm = { -- fiery clouds with charcoal shadows
      colors = { {1.00,0.35,0.10}, {1.00,0.75,0.25}, {0.25,0.25,0.35} },
      intensity = I(), scale = {3.2,2.0}, layers = 6, warp = 0.58,
      thresholds = {low=0.32, high=0.92}, depthFalloff = 0.84,
    },

    -- User-driven
    custom = function()
      return {
        colors = CONFIG.NEBULA_COLORS or {{0.2,0.6,1.0},{1.0,0.4,0.1},{0.8,0.2,0.9}},
        intensity = CONFIG.NEBULA_INTENSITY,
        scale = CONFIG.NEBULA_SCALE,
        layers = CONFIG.NEBULA_LAYERS,
        warp = CONFIG.NEBULA_WARP,
        thresholds = CONFIG.NEBULA_THRESHOLDS,
        depthFalloff = CONFIG.NEBULA_DEPTH_FALLOFF,
      }
    end
  }
end

function M.resolve(CONFIG)
  local name = (CONFIG.NEBULA_PRESET or "orion"):lower()
  M.lastName = name
  local p = PRESETS(CONFIG)[name] or PRESETS(CONFIG).orion
  if type(p)=="function" then p = p() end
  return {
    colors = p.colors or CONFIG.NEBULA_COLORS,
    intensity = p.intensity or CONFIG.NEBULA_INTENSITY,
    scale = p.scale or CONFIG.NEBULA_SCALE,
    layers = p.layers or CONFIG.NEBULA_LAYERS,
    warp = p.warp or CONFIG.NEBULA_WARP,
    thresholds = p.thresholds or CONFIG.NEBULA_THRESHOLDS,
    depthFalloff = p.depthFalloff or CONFIG.NEBULA_DEPTH_FALLOFF,
  }
end

function M.normalizeLoaded(loaded, bundled)
  local mem, links = {}, {}
  if type(loaded) == "table" and (loaded.memories or loaded.links) then
    mem   = loaded.memories or {}
    links = loaded.links    or {}
  elseif type(loaded) == "table" then
    mem = loaded
  end
  if #mem == 0 then
    mem   = (bundled and bundled.memories) or {}
    links = (bundled and bundled.links)    or {}
  end
  return mem, links
end

function M.normalizeLayout(memories, winW, winH, margin)
  if type(memories) ~= "table" or #memories == 0 then return end
  margin = margin or 60
  local needScale = false
  local minX, minY, maxX, maxY
  for _, m in ipairs(memories) do
    if m and m.x and m.y and not m._scaled then
      needScale = true
      minX = (minX and math.min(minX, m.x)) or m.x
      minY = (minY and math.min(minY, m.y)) or m.y
      maxX = (maxX and math.max(maxX, m.x)) or m.x
      maxY = (maxY and math.max(maxY, m.y)) or m.y
    end
  end
  if needScale and minX and minY and maxX and maxY then
    local bboxW, bboxH = (maxX - minX), (maxY - minY)
    local scale = 1
    if bboxW > 0 and bboxH > 0 then
      scale = math.min((winW - 2*margin) / bboxW, (winH - 2*margin) / bboxH)
    end
    for _, m in ipairs(memories) do
      if m and m.x and m.y and not m._scaled then
        m.x = (m.x - minX) * scale + margin
        m.y = (m.y - minY) * scale + margin
        m._scaled = true
      end
    end
  end
end

-- Robust ID handling: supports numeric, "17", or "mem-17"; preserves non-numeric ids
local function parseIdNum(raw)
  if type(raw) == "number" then return raw end
  if type(raw) == "string" then
    local n = tonumber(raw)
    if n then return n end
    local digits = raw:match("(%d+)$")
    if digits then return tonumber(digits) end
  end
  return nil
end

local function computeNextNumericId(memories, startAt)
  local maxId = tonumber(startAt) or 0
  for _, v in ipairs(memories or {}) do
    local n = v and parseIdNum(v.id)
    if n and n > maxId then maxId = n end
  end
  return maxId + 1
end

function M.ensureIds(memories)
  if type(memories) ~= "table" then return end

  -- Mark duplicates and build set of used string ids
  local used = {}
  for _, m in ipairs(memories) do
    if m and m.id ~= nil and m.id ~= "" then
      local key = tostring(m.id)
      if used[key] then
        -- duplicate: clear so we reassign
        m.id = nil
      else
        used[key] = true
      end
    end
  end

  -- Assign fresh numeric ids (as strings) to those missing/cleared
  local nextNum = computeNextNumericId(memories, 0)
  for _, m in ipairs(memories) do
    if m and (m.id == nil or m.id == "") then
      while used[tostring(nextNum)] do
        nextNum = nextNum + 1
      end
      m.id = tostring(nextNum)
      used[m.id] = true
      nextNum = nextNum + 1
    end
  end
end

return M
