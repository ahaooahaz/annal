-- Pull in the wezterm API
local wezterm = require("wezterm")

-- This will hold the configuration.
local config = wezterm.config_builder()


config.font = wezterm.font("JetBrainsMono Nerd Font")
config.color_scheme = "Afterglow"

-- 配置透明背景
config.window_background_opacity = 0.95 -- 设置透明度
config.text_background_opacity = 1 -- 设置文字透明度
-- 非活动窗格的样式
config.inactive_pane_hsb = {
    saturation = 0.9,
    brightness = 0.8,
}
-- 设置背景图片
config.window_background_image = ""

-- 如果只有一个标签页，则隐藏标签栏
config.hide_tab_bar_if_only_one_tab = false
-- 隐藏底部状态栏
config.window_decorations = "RESIZE"
-- 禁用滚动条
config.enable_scroll_bar = false
-- 配置字体大小
config.font_size = 13
-- 配置窗口打开时默认大小
config.initial_cols = 150
config.initial_rows = 35
config.use_fancy_tab_bar = false
config.enable_tab_bar = true
config.show_tab_index_in_tab_bar = true
-- 配置窗口为圆角
config.window_background_image_hsb = {
	brightness = 1, -- 调整背景图片亮度
	hue = 1, -- 调整背景图片色调
	saturation = 1, -- 调整背景图片饱和度
}
-- 修改行间距
-- config.line_height = 1.7

-- -- Set PowerShell as the default shell
if wezterm.target_triple == "x86_64-pc-windows-msvc" then
	config.default_prog = { "nu.exe" }
end

-- -- 设置powershell默认的工作目录
-- -- config.default_cwd = "D:"

-- 修改切换终端快捷键
config.keys = {
	-- F11 切换全屏
	{ key = "F11", mods = "NONE", action = wezterm.action.ToggleFullScreen },
	-- 垂直分屏
	{ key = "-", mods = "ALT", action = wezterm.action({ SplitVertical = { domain = "CurrentPaneDomain" } }) },
	-- 水平分屏
	{ key = "\\", mods = "ALT", action = wezterm.action({ SplitHorizontal = { domain = "CurrentPaneDomain" } }) },
	-- 关闭当前窗格
	{ key = "w", mods = "ALT", action = wezterm.action({ CloseCurrentPane = { confirm = true } }) },
	-- 切换到左侧窗格
	{ key = "h", mods = "ALT", action = wezterm.action({ ActivatePaneDirection = "Left" }) },
	-- 切换到下方窗格
	{ key = "j", mods = "ALT", action = wezterm.action({ ActivatePaneDirection = "Down" }) },
	-- 切换到上方窗格
	{ key = "k", mods = "ALT", action = wezterm.action({ ActivatePaneDirection = "Up" }) },
	-- 切换到右侧窗格
	{ key = "l", mods = "ALT", action = wezterm.action({ ActivatePaneDirection = "Right" }) },
	-- 切换到右侧窗格
	{ key = "f", mods = "ALT", action = wezterm.action.TogglePaneZoomState },
	-- 新建选项卡
	{ key = 't', mods = 'ALT', action = wezterm.action.SpawnTab 'DefaultDomain' },
	-- 搜索
	{ key = 'f', mods = 'SHIFT|CTRL', action = wezterm.action.Search { CaseInSensitiveString = '' } },
	-- 下一个选项卡
	{ key = ']', mods = 'ALT', action = wezterm.action.MoveTabRelative(1), },
	{ key = '[', mods = 'ALT', action = wezterm.action.MoveTabRelative(-1), },
}

-- -- 配置SSH域
config.ssh_domains = {
}


-- 关闭时不进行确认
config.window_close_confirmation = "NeverPrompt"

-- Finally, return the configuration to wezterm
return config