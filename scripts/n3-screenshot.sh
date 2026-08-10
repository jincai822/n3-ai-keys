#!/usr/bin/env bash
# N3 key: interactive area screenshot (maim works under fractional scaling,
# unlike flameshot gui which renders black on this dual 1.5x-scale setup).
set -euo pipefail

DIR="$HOME/Pictures"
mkdir -p "$DIR"
FILE="$DIR/$(date +%Y-%m-%d_%H-%M-%S).png"

# user drags a rectangle; cancel (Esc / right-click) -> maim exits non-zero
if maim -s -m 5 "$FILE"; then
    # xclip stays resident to serve paste requests; run it in background
    xclip -selection clipboard -t image/png -i "$FILE" &
    notify-send -t 3000 '截图' '已保存到 ~/Pictures 并复制到剪贴板' || true
fi
