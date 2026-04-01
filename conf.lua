function love.conf(t)
  t.gammacorrect   = true
  t.window.title   = "Ruins of Argiah"
  t.window.fullscreen = false
  t.window.borderless = false
  t.fullscreentype = "desktop"
  t.window.width   = 0
  t.window.height  = 0
  t.window.vsync   = 0
  t.window.highdpi = false
  t.window.resizable = false

  -- ADD THIS:
  t.window.icon = "assets/icon.png"  -- PNG bundled in your game data
end
