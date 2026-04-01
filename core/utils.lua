local U = {}

function U.deepcopy(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = U.deepcopy(v) end
  return r
end

function U.rrange(a,b) return love.math.random()*(b-a)+a end
function U.lerp(a,b,t) return a + (b-a)*t end
function U.angle(dx,dy)
  if dx == 0 then return (dy>=0) and (math.pi/2) or (-math.pi/2) end
  return math.atan(dy/dx) + (dx<0 and math.pi or 0)
end

U.EASE = {
  linear     = function(t) return t end,
  quadout    = function(t) t=1-t; return 1 - t*t end,
  quartout   = function(t) t=1-t; return 1 - t*t*t*t end,
  cubicout   = function(t) t=1-t; return 1 - t*t*t end,
  backout    = function(t) local s=1.70158; t=t-1; return t*t*((s+1)*t+s)+1 end,
  quadinout  = function(t) if t<0.5 then return 2*t*t else t=1-t; return 1-2*t*t end end,
  elasticout = function(t) if t==0 or t==1 then return t end
    return math.pow(2,-10*t)*math.sin((t-0.075)*(2*math.pi)/0.3)+1 end,
}

return U
