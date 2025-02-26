local wezterm = require("wezterm")
local platform = require("utils.platform")

local font = "JetBrainsMono NF"
local font_size = platform().is_mac and 12 or 13

return {
    font = wezterm.font(font),
    font_size = font_size,

    freetype_load_target = "Normal", ---@type 'Normal'|'Light'|'Mono'|'HorizontalLcd'
    freetype_render_target = "Normal", ---@type 'Normal'|'Light'|'Mono'|'HorizontalLcd'
}