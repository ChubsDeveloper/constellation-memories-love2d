// shaders/haze.glsl   – drifting haze (no external noise dependencies)
//
// uniforms supplied from Lua  :  time , strength , scale
// converts scrCoord → 0..1  so works at any resolution.

extern float time;       // seconds
extern float strength;   // 0‥1   overall opacity
extern vec2  scale;      // noise frequency

// ------------------------------------------------------------------
// tiny value-noise  →  3-octave FBM
// ------------------------------------------------------------------
float hash(vec2 p) {
    return fract(sin(dot(p , vec2(127.1,311.7))) * 43758.5453123);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);

    // bilinear interpolation
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));

    vec2  u = f*f*(3.0 - 2.0*f);      // smoothstep
    return mix(a, b, u.x) +
           (c - a)*u.y  +
           (a - b - c + d)*u.x*u.y;
}

float fbm(vec2 p) {
    float v   = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 3; i++) {     // 3 octaves are enough for soft fog
        v   += amp * noise(p);
        p   *= 2.0;
        amp *= 0.5;
    }
    return v;
}

// ------------------------------------------------------------------
// main
// ------------------------------------------------------------------
vec4 effect(vec4 colour, Image tex, vec2 texCoord, vec2 scrCoord)
{
    // screen pixel in 0‥1
    vec2 uv  = scrCoord / love_ScreenSize.xy;

    // animated FBM – slow lateral drift
    float n  = fbm( uv * scale + vec2(time * .02, 0.0));

    // remap & bias so only darker pockets appear
    n = pow(clamp(n * 0.5 + 0.5, 0.0, 1.0), 3.0);

    // base frame buffer
    vec4 base = Texel(tex, texCoord);

    // fog tint (same blue-grey your UI uses)
    vec3 fog  = vec3(0.10, 0.12, 0.18);

    float a   = n * strength;
    vec3 rgb  = mix(base.rgb, fog, a);

    return vec4(rgb, base.a);
}
