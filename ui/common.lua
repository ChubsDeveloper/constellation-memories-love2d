-- ui/common.lua
local Common = {}

-- Lua 5.1 / 5.2+ compatibility
Common.unpack = table.unpack or unpack

-- Fonts
Common.fontTitle = nil
Common.fontBody  = nil

-- Theme (shared)
Common.theme = {
  -- HUD pill
  hudPillBg     = {0.12, 0.12, 0.18, 0.92},
  hudPillStroke = {1.00, 0.96, 0.70, 0.65},
  hudPillText   = {1, 1, 1, 0.95},

  -- Help chip
  helpBg        = {0.12, 0.12, 0.18, 0.92},
  helpStroke    = {1.00, 0.96, 0.70, 0.55},
  helpText      = {0.95, 0.95, 1.00, 0.92},
  helpHint      = {0.95, 0.85, 0.60, 0.95},
}

function Common.deepcopy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k,v in pairs(t) do out[k] = Common.deepcopy(v) end
  return out
end

function Common.toRGB(c)
  if type(c) ~= "table" then return 1,1,1 end
  local r = c[1] or c.r or 1
  local g = c[2] or c.g or 1
  local b = c[3] or c.b or 1
  return r,g,b
end

-- Helpers
function Common.clamp(v, a, b) return (v < a) and a or ((v > b) and b or v) end
function Common.mix(a,b,t) return a + (b - a) * t end

-- Single, defensive setAlpha (do not redefine this elsewhere)
function Common.setAlpha(c, mul)
  local aMul = mul or 1
  if type(c) ~= "table" then
    love.graphics.setColor(1, 1, 1, aMul)
    return
  end
  local r = c[1] or c.r or 1
  local g = c[2] or c.g or 1
  local b = c[3] or c.b or 1
  local a = c[4] or c.a or 1
  love.graphics.setColor(r, g, b, a * aMul)
end

-- Fonts + defaults
function Common.load()
  Common.fontTitle = love.graphics.newFont("assets/font.ttf", 20)
  Common.fontBody  = love.graphics.newFont("assets/font.ttf", 16)
end

-- Small reusable “?” help chip (bottom-left)
local helpHover = false
local helpRect  = { x = 12, y = 0, w = 30, h = 26 } -- y set each frame

function Common.drawHelpChip()
  local THEME = Common.theme
  local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
  local font   = Common.fontBody

  -- Make the chip a bit taller automatically (font height + padding)
  local baseH  = (helpRect and helpRect.h) or 24
  local chipH  = math.max(baseH, (font and font:getHeight() or 14) + 10)

  -- Position chip at bottom-right margin (keep existing X/W from helpRect)
  helpRect.y = sh - 12 - chipH
  local cx, cy = helpRect.x, helpRect.y

  -- Hover detection uses the *actual* chipH
  local mx, my = love.mouse.getPosition()
  helpHover = (mx >= cx and mx <= cx + helpRect.w and my >= cy and my <= cy + chipH)

  -- Chip background + border
  Common.setAlpha(THEME.helpBg, helpHover and 1.0 or 0.8)
  love.graphics.rectangle("fill", cx, cy, helpRect.w, chipH, 8, 8)
  Common.setAlpha(THEME.helpStroke, 1)
  love.graphics.setLineWidth(1.0)
  love.graphics.rectangle("line", cx, cy, helpRect.w, chipH, 8, 8)

  -- Center the "?" vertically within the taller chip
  love.graphics.setFont(font)
  love.graphics.setColor(1,1,1,0.95)
  local qy = cy + (chipH - font:getHeight()) * 0.5
  love.graphics.printf("?", cx, qy, helpRect.w, "center")

  if helpHover then
    local tips = {
      { "Right-click", "Create new memory" },
      { "Click star",  "Open memory" },
      { "Hold star",   "Move memory" },
      { "L",           "Toggle link mode" },
      { "Esc",         "Cancel link / close" },
    }

    -- Layout
    local padX, padY, lineGap = 10, 10, 6
    local wLeft, contentW     = 140, 360  -- give left a touch more width; wider popover to reduce wraps

    -- Measure wrapped height per row
    local totalH     = padY * 2 - lineGap
    local rowHeights = {}
    for i = 1, #tips do
      local left, right = tips[i][1], tips[i][2]
      local _, leftLines  = font:getWrap(left,  wLeft - padX)
      local _, rightLines = font:getWrap(right, contentW - wLeft - padX*2)
      local lines = math.max(#leftLines, #rightLines)
      local rh    = lines * font:getHeight()
      rowHeights[i] = rh
      totalH = totalH + rh + lineGap
    end

    -- Place box (prefer right of chip; if it would overflow, place to the left)
    local boxX = cx + helpRect.w + 10
    if boxX + contentW > sw - 10 then
      boxX = cx - 10 - contentW
    end
    local boxY = cy - totalH + chipH

    -- Popover background + border
    Common.setAlpha(THEME.helpBg, 1)
    love.graphics.rectangle("fill", boxX, boxY, contentW, totalH, 8, 8)
    Common.setAlpha(THEME.helpStroke, 1)
    love.graphics.rectangle("line", boxX, boxY, contentW, totalH, 8, 8)

    -- Render rows with their measured heights
    local yPos = boxY + padY
    for i, row in ipairs(tips) do
      Common.setAlpha(THEME.helpHint, 1)
      love.graphics.printf(row[1], boxX + padX, yPos, wLeft - padX, "left")
      Common.setAlpha(THEME.helpText, 1)
      love.graphics.printf(row[2], boxX + wLeft, yPos, contentW - wLeft - padX*2, "left")
      yPos = yPos + rowHeights[i] + lineGap
    end
  end
end

return Common
