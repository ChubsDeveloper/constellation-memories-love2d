--[[ 
Cosmic Nebula (Moonshine Effect)
- Multi-layer domain-warped FBM with 3-color mixing
- Safe for LÖVE's GLSL (fixed loop counts, uniforms for knobs)
- Screen-blends onto the scene
Usage:
  local moonshine = require("moonshine")
  local nebulaFx  = require("effects.nebula")
  local fx = moonshine(nebulaFx)
  fx.nebula.intensity = 0.25
  fx.nebula.scale     = {2.5,2.5}
  fx.nebula.color1    = {0.2, 0.6, 1.0}
  fx.nebula.color2    = {1.0, 0.4, 0.1}
  fx.nebula.color3    = {0.8, 0.2, 0.9}
  fx.nebula.layers    = 4
  fx.nebula.warp      = 0.35
  fx.nebula.scroll    = {0,0} -- update every frame
--]]

return function(moonshine)
  local shader = love.graphics.newShader[[
    extern float time;
    extern float intensity;       // overall brightness (0..1+)
    extern vec2  scale;           // base noise scale (frequency)
    extern vec2  scroll;          // screen-space scroll (pixels)
    extern vec3  color1;          // primary gas
    extern vec3  color2;          // secondary gas
    extern vec3  color3;          // tertiary gas
    extern float layers;          // 1..6 effective octaves
    extern float warp;            // domain warp amount (0..1.5)
    extern float cloudLow;        // density threshold low
    extern float cloudHigh;       // density threshold high
    extern float depthFalloff;    // 0..1 how much center falloff matters

    float hash(vec2 p){
      return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453123);
    }
    float noise(vec2 p){
      vec2 i=floor(p), f=fract(p);
      vec2 u = f*f*(3.0-2.0*f);
      float a = hash(i);
      float b = hash(i + vec2(1.0,0.0));
      float c = hash(i + vec2(0.0,1.0));
      float d = hash(i + vec2(1.0,1.0));
      return mix(a,b,u.x) + (c-a)*u.y + (a-b-c+d)*u.x*u.y;
    }

    // fixed 6-octave fbm; 'layers' gates contribution
    float fbm_layers(vec2 p, float layersF){
      float v=0.0, a=0.5, f=1.0;
      for(int i=0;i<6;i++){
        float m = step(float(i), layersF-1.0);
        v += m * a * noise(p * f);
        f *= 2.02; a *= 0.5;
      }
      return v;
    }

    vec2 domainWarp(vec2 p, float amt, float layersF){
      float w1 = fbm_layers(p + vec2(3.4, 1.7), min(layersF, 3.0));
      float w2 = fbm_layers(p + vec2(5.1,-2.3), min(layersF, 3.0));
      return p + amt * vec2(w1, w2);
    }

    vec4 effect(vec4 colour, Image tex, vec2 uv, vec2 sc){
      vec2 res = love_ScreenSize.xy;

      vec2 p = (sc + scroll) / res.y;
      vec2 pw = domainWarp(p * scale, warp, layers);

      float t1 = fbm_layers(pw + vec2(time*0.010, time*0.008), layers);
      float t2 = fbm_layers(pw*1.5 + vec2(time*0.008,-time*0.010), layers);
      float t3 = fbm_layers(pw*0.8 + vec2(-time*0.012, time*0.012), layers);

      float d1 = smoothstep(cloudLow, cloudHigh, t1);
      float d2 = smoothstep(cloudLow+0.05, cloudHigh+0.05, t2);
      float d3 = smoothstep(cloudLow-0.08, cloudHigh-0.08, t3);

      vec3 neb = vec3(0.0);
      neb += color1 * d1 * 0.85;
      neb += color2 * d2 * 0.65;
      neb += color3 * d3 * 0.45;

      float cshift = fbm_layers(pw*2.0 + time*0.005, 2.0);
      neb *= (0.8 + 0.4 * cshift);

      float centerDist = length((sc - res*0.5) / res.y);
      float falloff = 1.0 - smoothstep(0.2, 0.8, centerDist);
      neb *= mix(1.0, falloff, clamp(depthFalloff, 0.0, 1.0));

      vec4 base = Texel(tex, uv);
      vec3 add  = neb * max(0.0, intensity);
      vec3 blended = base.rgb + add * (1.0 - base.rgb);

      return vec4(blended, base.a);
    }
  ]]

  local setters = {}
  local function sendVec2(name, v)
    if type(v)=="table" and #v>=2 then shader:send(name, {v[1], v[2]})
    elseif type(v)=="number" then shader:send(name, {v, v})
    else error("Invalid vec2 for "..name) end
  end
  local function sendColor(name, v)
    if type(v)=="table" and #v>=3 then shader:send(name, {v[1], v[2], v[3]})
    else error("Invalid rgb for "..name) end
  end

  setters.time = function(v) shader:send("time", tonumber(v) or 0) end
  setters.intensity = function(v) shader:send("intensity", math.max(0, tonumber(v) or 0)) end
  setters.scale   = function(v) sendVec2("scale", v) end
  setters.scroll  = function(v) sendVec2("scroll", v) end
  setters.color1  = function(v) sendColor("color1", v) end
  setters.color2  = function(v) sendColor("color2", v) end
  setters.color3  = function(v) sendColor("color3", v) end
  setters.layers  = function(v) shader:send("layers", math.max(1, math.min(6, tonumber(v) or 4))) end
  setters.warp    = function(v) shader:send("warp", math.max(0, tonumber(v) or 0)) end
  setters.cloudLow  = function(v) shader:send("cloudLow",  tonumber(v) or 0.25) end
  setters.cloudHigh = function(v) shader:send("cloudHigh", tonumber(v) or 0.85) end
  setters.depthFalloff = function(v) shader:send("depthFalloff", math.max(0, math.min(1, tonumber(v) or 0.8))) end

  local defaults = {
    time = 0.0,
    intensity = 0.25,
    scale = {2.5, 2.5},
    scroll = {0.0, 0.0},
    color1 = {0.20, 0.60, 1.00},
    color2 = {1.00, 0.40, 0.10},
    color3 = {0.80, 0.20, 0.90},
    layers = 4,
    warp = 0.35,
    cloudLow = 0.25,
    cloudHigh = 0.85,
    depthFalloff = 0.8,
  }

  return moonshine.Effect{
    name = "nebula",
    shader = shader,
    setters = setters,
    defaults = defaults,
  }
end
