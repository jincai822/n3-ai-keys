#!/usr/bin/env bash
# N3 key: WeChat — focus the window if already running, otherwise launch it.
set -euo pipefail

if xdotool search --class wechat >/dev/null 2>&1; then
    xdotool search --class wechat windowactivate --sync 2>/dev/null || true
else
    wechat >/dev/null 2>&1 &
fi
