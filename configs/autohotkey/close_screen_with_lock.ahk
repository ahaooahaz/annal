; AHK v2 - Win11 锁屏自动关显示器

#Requires Autohotkey v2.0

; 注册脚本窗口接收会话通知
DllCall("Wtsapi32.dll\WTSRegisterSessionNotification"
    , "Ptr", A_ScriptHwnd
    , "UInt", 0)  ; NOTIFY_FOR_THIS_SESSION

; 注册消息处理函数
OnMessage(0x2B1, WM_WTSSESSION_CHANGE) ; 0x2B1 = WM_WTSSESSION_CHANGE

; 保持脚本驻留
Loop
    Sleep 1000

return

WM_WTSSESSION_CHANGE(wParam, lParam, msg, hwnd) {
    ; WTS_SESSION_LOCK = 0x7
    if (wParam = 0x7) {
        ; 关闭显示器
        DllCall("user32.dll\SendMessageA"
            , "Ptr", 0xFFFF       ; HWND_BROADCAST
            , "UInt", 0x112       ; WM_SYSCOMMAND
            , "UInt", 0xF170      ; SC_MONITORPOWER
            , "Int", 2             ; 2 = 关闭显示器
        )
    }
}
