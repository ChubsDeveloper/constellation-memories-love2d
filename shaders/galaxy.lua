local shader = love.graphics.newShader[[
  extern number time;
  extern vec3   starColor;
  extern number intensity;
  extern number coreSize;
  extern number highlight;
  extern number specSize;
  extern number rim;
  extern number depth;
  extern vec2   centerPx;
  extern number radiusPx;

  float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
  float noise(vec2 p){
    vec2 i=floor(p), f=fract(p);
    f=f*f*(3.0-2.0*f);
    return mix(mix(hash(i+vec2(0,0)),hash(i+vec2(1,0)),f.x),
               mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x), f.y);
  }

  vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
    float dist = distance(sc, centerPx) / max(1.0, radiusPx);

    float core     = 1.0 - smoothstep(0.0, coreSize, dist);

    float dens     = mix(8.0, 28.0, clamp(specSize, 0.0, 1.0));
    float s1       = noise(uv * dens + time * 1.7);
    float s2       = noise(uv * (dens*0.6) - time * 1.1);
    float sparkle  = 0.55 + (s1 * 0.6 + s2 * 0.4) * 0.45;

    float pulse    = 0.85 + 0.15 * sin(time * 3.0);

    float centreGlow = (1.0 - smoothstep(0.0, 0.10, dist)) * (0.6 + 0.6 * highlight);

    float edgeVign  = mix(1.0, (1.0 - smoothstep(0.0, 1.0, dist*1.4)), depth);

    float rimBand   = smoothstep(coreSize * 0.85, coreSize * 1.05, dist)
                    * (1.0 - smoothstep(coreSize * 1.05, coreSize * 1.35, dist));
    float rimGlow   = rimBand * rim * 0.9;

    float alpha = (core * sparkle * pulse * intensity);
    alpha       = max(alpha, centreGlow);
    alpha       = alpha + rimGlow;
    alpha       *= edgeVign;

    return vec4(starColor, alpha) * color;
  }
]]
return shader
