-------------------
---- AUTOSTART ----
-------------------

-- See https://wiki.hypr.land/configuring/core/autostart/

-- Autostart necessary processes (like notifications daemons, status bars, etc.)
-- Or execute your favorite apps at launch like this:
--

hl.on("hyprland.start", function()
    hl.exec_cmd("caelestia shell -d")
    hl.exec_cmd("fcitx5 -d --replace")
    hl.exec_cmd("nutstore")
    hl.exec_cmd("wl-paste --type text --watch cliphist store") -- 监听文本复制
    hl.exec_cmd("wl-paste --type image --watch cliphist store") -- 监听图片复制
end)
