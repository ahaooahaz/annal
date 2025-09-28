; AHK v2 - Win11 锁屏后延迟5秒黑屏
#Requires Autohotkey v2.0

; 注册脚本窗口接收会话通知
DllCall("Wtsapi32.dll\WTSRegisterSessionNotification", "Ptr", A_ScriptHwnd, "UInt", 0)

; 全局变量记录定时器状态
g_ScreenOffTimer := 0

OnMessage(0x2B1, WM_WTSSESSION_CHANGE)
Persistent true
OnExit((*) => DllCall("Wtsapi32.dll\WTSUnRegisterSessionNotification", "Ptr", A_ScriptHwnd))

WM_WTSSESSION_CHANGE(wParam, lParam, msg, hwnd) {
    global g_ScreenOffTimer

    if (wParam = 0x7) { ; 锁屏
        ; 取消可能存在的旧定时器
        if (g_ScreenOffTimer) {
            SetTimer(g_ScreenOffTimer, 0)
        }
        ; 设置5秒后关闭屏幕的新定时器
        g_ScreenOffTimer := CloseScreenAfterDelay
        SetTimer(g_ScreenOffTimer, -5000)
    }
    else if (wParam = 0x8) { ; 解锁
        ; 取消定时器
        if (g_ScreenOffTimer) {
            SetTimer(g_ScreenOffTimer, 0)
            g_ScreenOffTimer := 0
        }
        ; 恢复屏幕
        RestoreScreen()
    }
}

CloseScreenAfterDelay() {
    ; 关闭屏幕背光
    DllCall("user32.dll\SendMessage", "Ptr", 0xFFFF, "UInt", 0x112, "UInt", 0xF170, "Int", 2)
    ; 清空定时器引用
    g_ScreenOffTimer := 0
}

RestoreScreen() {
    ; 恢复屏幕显示
    DllCall("user32.dll\SendMessage", "Ptr", 0xFFFF, "UInt", 0x112, "UInt", 0xF170, "Int", -1)
}
