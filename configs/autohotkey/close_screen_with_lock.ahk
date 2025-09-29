#Requires AutoHotkey v2.0

#L:: {
    DllCall("LockWorkStation")
    Sleep(1500)
    PostMessage(0x112, 0xF170, 2, , "Program Manager")
}
