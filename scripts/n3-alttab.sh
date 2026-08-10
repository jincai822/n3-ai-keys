#!/usr/bin/env bash
# N3 middle knob: window switching (Alt+Tab).
# Rotate = step through windows; stop for ~1s = Alt released, window selected.
set -euo pipefail

DIR="${1:-cw}"
PIDFILE=/tmp/n3-alttab.timer.pid

xdotool keydown alt
if [ "$DIR" = "cw" ]; then
    xdotool key Tab
else
    xdotool key shift+Tab
fi

# cancel the previous pending release, then schedule a fresh one
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
fi
(
    sleep 0.9
    xdotool keyup alt
) &
echo $! > "$PIDFILE"
