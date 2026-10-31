---------------------
---- KEYBINDINGS ----
---------------------
local terminal = "kitty"
local fileManager = "dolphin"

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- Example binds, see https://wiki.hypr.land/configuring/core/binds/ for more
hl.bind(mainMod .. " + Space", hl.dsp.global("caelestia:launcher"))
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
local closeWindowBind = hl.bind(mainMod .. " + Q", hl.dsp.window.close())
-- closeWindowBind:set_enabled(false)
-- hl.bind(
-- 	mainMod .. " + M",
-- 	hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'")
-- )
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + Shift + F", hl.dsp.window.fullscreen({ action = "toggle" }))

hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("~/.config/hypr/scripts/clipboard.sh c"))
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("~/.config/hypr/scripts/clipboard.sh v"))
hl.bind(mainMod .. " + A", hl.dsp.send_shortcut({ mods = "CTRL", key = "A" }))

hl.bind("ALT + Tab", hl.dsp.window.cycle_next())
hl.bind(mainMod .. " + R", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit")) -- dwindle only

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Laptop multimedia keys for volume and LCD brightness
hl.bind(
    "XF86AudioRaiseVolume",
    hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"),
    { locked = true, repeating = true }
)
hl.bind(
    "XF86AudioLowerVolume",
    hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),
    { locked = true, repeating = true }
)
hl.bind(
    "XF86AudioMute",
    hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),
    { locked = true, repeating = true }
)
hl.bind(
    "XF86AudioMicMute",
    hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),
    { locked = true, repeating = true }
)
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), { locked = true, repeating = true })

-- Requires playerctl
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

-- 将当前窗口“最小化”到特殊工作区，再按一次则恢复
hl.bind("SUPER + H", function()
    -- 检查特殊工作区是否已存在（即已有最小化的窗口）
    if hl.get_workspace("special:minimized") then
        -- 恢复：将带 "minimized" 标签的窗口移回当前工作区，并清除标签
        hl.dispatch(hl.dsp.window.move({
            workspace = hl.get_active_workspace(),
            window = "tag:minimized",
        }))
        hl.dispatch(hl.dsp.window.clear_tags({ window = "tag:minimized" }))
    else
        -- 最小化：给当前窗口打上标签，并移动到特殊工作区（不跟随切换）
        hl.dispatch(hl.dsp.window.tag({
            tag = "minimized",
            window = hl.get_active_window(),
        }))
        hl.dispatch(hl.dsp.window.move({
            workspace = "special:minimized",
            follow = false,
        }))
    end
end)

-- hl.bind("F1", hl.dsp.exec_cmd("omasnap --editor=overlay"), { description = "Screenshot" })
-- hl.bind("F1", hl.dsp.exec_cmd("caelestia screenshot --region --freeze"), { description = "Region Screenshot" })
hl.bind("F1", function()
    local mon = hl.get_active_monitor()
    local n = mon and mon.id or 0
    hl.exec_cmd("flameshot screen --number " .. n .. " --edit")
end, {
    description = "Flameshot Screenshot",
})
hl.window_rule({
    match = { class = "flameshot" },
    no_anim = true,
    pin = true,
    float = true,
    decorate = false,
    no_blur = true,
    no_shadow = true,
})
hl.bind("F2", hl.dsp.exec_cmd("caelestia clipboard"), { description = "Clipboard History" })
hl.bind(mainMod .. " + L", hl.dsp.global("caelestia:lock"))
