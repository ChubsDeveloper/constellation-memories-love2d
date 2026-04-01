-- data/memory_schema.lua
-- Normalizes memory objects and back-fills new fields for old data.
-- Mood is no longer authored here (kept only for backward-compat lookups).

local Schema = {}

-- Back-compat: keep this so viewer/old saves can read moods if present.
Schema.MOOD_PRESETS = {
  happy     = { emoji = "😊", color = {1.00, 0.86, 0.40} },
  love      = { emoji = "💖", color = {1.00, 0.60, 0.80} },
  calm      = { emoji = "🌿", color = {0.55, 0.95, 0.75} },
  sad       = { emoji = "💧", color = {0.70, 0.80, 1.00} },
  proud     = { emoji = "⭐", color = {1.00, 0.90, 0.60} },
  nostalgic = { emoji = "📻", color = {0.90, 0.85, 1.00} },
  default   = { emoji = "✨", color = {0.90, 0.90, 1.00} },
}

-- Background style presets (the composer/viewer decide whether to use them).
Schema.BACKGROUND_PRESETS = {
  none     = { kind = "none" },
  color    = function(rgb) return { kind = "color", color = rgb } end,
  gradient = function(a, b) return { kind = "gradient", from = a, to = b } end,
  blurMain = { kind = "blur_main_image", strength = 0.6 },
}

local function clone(t)
  local n = {}
  for k, v in pairs(t or {}) do
    if type(v) == "table" then n[k] = clone(v) else n[k] = v end
  end
  return n
end

-- Convert legacy memory into the richer shape without breaking old saves.
-- Legacy fields supported: label -> title, text -> a text block, style.* -> star look.
function Schema.normalizeMemory(m)
  local mem = clone(m)

  -- 1) Title/subtitle (legacy: label -> title)
  mem.title    = mem.title or mem.label or "Untitled"
  mem.subtitle = mem.subtitle or nil

  -- 2) Tags
  mem.tags = mem.tags or {}

  -- 3) Mood: no longer set by schema.
  -- Keep any existing mem.mood/mem.moodData from legacy, but don't create them.

  -- 4) Background: do not auto-derive. Leave as-is.
  -- If composer/user chooses "Default", viewer will use star color.

  -- 5) Star visual (keep legacy style for star look)
  mem.star = mem.star or {}
  local legacyStyle = mem.style or {}
  mem.star.color      = mem.star.color      or legacyStyle.color or {1, 1, 1}
  mem.star.radius     = mem.star.radius     or legacyStyle.radius or 9
  mem.star.spikeCount = mem.star.spikeCount or legacyStyle.spikeCount or 8

  -- 6) Media (optional)
  mem.images = mem.images or {}
  mem.audio  = mem.audio  or nil
  mem.video  = mem.video  or nil

  -- 7) Optional metadata
  mem.people   = mem.people   or {}
  mem.location = mem.location or nil
  mem.when     = mem.when     or nil

  -- 8) Blocks (diary-style). Migrate legacy `text` if blocks missing.
  if not mem.blocks or #mem.blocks == 0 then
    mem.blocks = {
      { type="text", text = mem.text or "" }
    }
  end

  -- 9) Legacy accessors for safety
  mem.label = mem.title
  mem.text  = (mem.blocks[1] and mem.blocks[1].type == "text") and mem.blocks[1].text or (mem.text or "")

  return mem
end

-- Normalize an entire array and return the normalized list.
function Schema.normalizeAll(raw)
  local out = {}
  for i = 1, #raw do
    out[i] = Schema.normalizeMemory(raw[i])
  end
  return out
end

return Schema
