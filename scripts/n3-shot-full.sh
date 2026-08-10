#!/usr/bin/env bash
# OpenDeck key "整屏截图": capture all monitors (physical pixels) with maim.
# flameshot produces corrupted frames on the 4K / fractional-scaling display;
# maim reads the X11 root window directly and is pixel-perfect on both screens.
set -euo pipefail

DIR="$HOME/Pictures"
mkdir -p "$DIR"
FILE="$DIR/$(date +%F_%H-%M-%S).png"

maim -u "$FILE"
xclip -selection clipboard -t image/png -i "$FILE"
notify-send -t 3000 "截图" "已保存到 ~/Pictures 并复制到剪贴板" || true
