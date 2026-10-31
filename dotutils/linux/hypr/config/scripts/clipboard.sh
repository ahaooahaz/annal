#!/bin/bash
KEY=${1^^} # 统一转大写，C 或 V
CLASS=$(hyprctl activewindow -j | jq -r '.class')

case "$CLASS" in
kitty | Alacritty | foot | WezTerm)
    MODS="CTRL SHIFT"
    ;;
*)
    MODS="CTRL"
    ;;
esac

hyprctl dispatch "hl.dsp.send_shortcut({ mods = \"$MODS\", key = \"$KEY\", window = \"activewindow\" })"
