local moonshine = require("libs.moonshine")

moonshine.glow = require("libs.moonshine.effects.glow")(moonshine)
moonshine.vignette = require("libs.moonshine.effects.vignette")(moonshine)
moonshine.haze = require("libs.moonshine.effects.haze")(moonshine)
moonshine.nebula = require("libs.moonshine.effects.nebula")(moonshine)

return moonshine