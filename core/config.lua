return {
  GLOW_STRENGTH = 10,
  ENABLE_CHROMASEP = true,
  CHROMASEP_RADIUS = 0.002,
  CHROMASEP_ANGLE  = 0.0,
  ENABLE_FILMGRAIN = true,
  FILMGRAIN_SIZE   = 1.5,
  FILMGRAIN_OPACITY= 0.05,
  ENABLE_SCANLINES = false,
  SCANLINES_THICKNESS=1.5,
  SCANLINES_OPACITY  =0.03,
  VIGNETTE_RADIUS  = 0.90,
  VIGNETTE_SOFTNESS= 0.45,
  VIGNETTE_OPACITY = 0.40,
  VIGNETTE_COLOR   = {0, 0, 0},

  USE_MOONSHINE_NEBULA = true,
  NEBULA_ENABLED   = true,
  NEBULA_PRESET    = "pillars",
  NEBULA_COLORS    = { {0.20,0.60,1.00}, {1.00,0.40,0.10}, {0.80,0.20,0.90} },
  NEBULA_INTENSITY = 0.015,
  NEBULA_SCALE     = {2.5, 2.5},
  NEBULA_LAYERS    = 2,
  NEBULA_WARP      = 0.35,
  NEBULA_THRESHOLDS= { low=0.25, high=0.85 },
  NEBULA_DEPTH_FALLOFF = 0.60,
  NEBULA_SCROLL_SPEED  = { x = 0.008, y = 0.002 },

  FALLBACK_DOWNSCALE = 1,
  TOOLTIP_FONT = { path = "assets/font.ttf", size = 14 },

  BACKGROUND_STARS_COUNT = 600,
  BG_WARM_BIAS         = 0.85,
  BG_RADIUS            = { min = 0.9, max = 1.5 },
  BG_ALPHA             = { min = 0.45, max = 0.75 },
  BG_TWINKLE_SPEED     = { min = 1.4, max = 1.8 },
  BG_TWINKLE_AMPLITUDE = 2.75,
  BG_TWINKLE_FADE_SPEED= 2.0,

  MEM_RADIUS_BASE   = 3,
  MEM_SIZE_MULT     = 0.25,
  MEM_SCALE_HOVER   = 1.2,
  MEM_SCALE_SPEED   = 10,
  MEM_GLOW_IDLE     = 0.05,
  MEM_GLOW_HOVER    = 0.75,
  MEM_GLOW_SPEED    = 8,

  STAR_GLOW = {
    outer_scale = 3.6,  outer_alpha = 0.06,
    mid_scale   = 2.2,  mid_alpha   = 0.10,
    inner_scale = 1.4,  inner_alpha = 0.18,
    shader_intensity_mult = 0.70,
  },

  STAR_RINGS = {
    enabled         = true,
    segments        = 16,
    base_radius     = 1.6,
    per_ring_step   = 0.52,
    alpha_base      = 0.45,
    alpha_falloff   = 0.10,
    width_base      = 2.0,
    width_falloff   = 0.26,
    wobble1         = { amp = 0.12, freq = 4.0, speed = 2.0 },
    wobble2         = { amp = 0.06, freq = 8.0, speed = -1.0 },
  },

  STAR_PARTICLES = {
    enabled        = true,
    count_mult     = 0.6,
    orbit          = { min = 8, max = 14, add_core = true },
    size           = { min = 0.7, max = 1.6 },
    alpha          = { min = 0.5, max = 0.9 },
    orbit_speed    = { min = 0.25, max = 0.6 },
    float_speed    = { min = 0.8,  max = 1.5 },
    float_amp      = { min = 2.0,  max = 6.0 },
  },

  STAR_AURA_SPARKLES = {
    rate = 0.002,
    radius_inner_mult = 1.05,
    radius_outer_mult = 1.6,
    count = 3,
  },
  
  STAR_OUTER_RING = {
  enabled       = true,
  radius_mult   = 2.8,   -- relative to star radius
  width         = 2.4,   -- line width
  alpha         = 0.20,  -- transparency
  segments      = 48,    -- number of line segments
  wobble        = { amp = 0.10, freq = 3.0, speed = 1.2 },
},

  MEM_RING_ALPHA = 0.22,

  FS_ANGLE_DEG  = { min = 20, max = 70 },
  FS_SPEED      = { min = 700, max = 1200 },
  FS_SIZE       = { min = 3,  max = 6 },
  FS_LIFE       = 1.5,
  FS_ALPHA_BASE = { min = 0.6, extra = 0.25 },
  FS_TRAIL_LENGTH     = 12,
  FS_TRAIL_WIDTH_BASE = 0.5,
  FS_TRAIL_WIDTH_STEP = 0.15,
  FS_TRAIL_WIDTH_BOOST_NEAR= 0.25,

  SPARKLE_COUNT_DEFAULT = 15,
  SPARKLE_SPEED = { min = 50,  max = 150 },
  SPARKLE_SIZE  = { min = 1,   max = 3   },
  SPARKLE_LIFE  = { min = 1.0, max = 1.5 },
  HOVER_SPAWN_SPARKLE_RATE= 2.0,

  LINK_WIDTH              = 1.0,
  LINK_HALO_WIDTH         = 2.5,
  LINK_BASE_ALPHA         = 0.20,
  LINK_LINE_ALPHA         = 0.85,
  LINK_HOVER_BOOST        = 0.35,
  LINK_SEGMENTS           = 24,
  LINK_ANIM_SPEED         = 0.9,
  LINK_SPARKLE_COUNT      = 20,
  LINK_BOUNCE_SCALE       = 0.85,
  LINK_BOUNCE_IN_DUR      = 0.24,
  LINK_BOUNCE_OUT_DUR     = 0.48,

  HOLD_TO_MOVE_SECONDS = 1.0,

  CORE_REL_MIN = 0.10,
  CORE_REL_MAX = 0.85,
  
PULSE = {
  enabled     = true,   -- optional, defaults to true
  amount_mult = 0.45,   -- try 0.35–0.60
  speed_mult  = 1.0,
},

}
