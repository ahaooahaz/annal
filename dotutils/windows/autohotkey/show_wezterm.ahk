#Requires AutoHotkey v2.0

^Space:: {
    if WinExist("ahk_class org.wezfurlong.wezterm") {
        WinActivate
    }
}
