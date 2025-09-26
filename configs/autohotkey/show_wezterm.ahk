; Ctrl + Space 聚焦 WezTerm（不会置顶，鼠标仍可点其他窗口）
^SPACE::
IfWinExist, ahk_class org.wezfurlong.wezterm
{
    WinActivate
}
return
