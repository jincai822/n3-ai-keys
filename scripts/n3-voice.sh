#!/usr/bin/env bash
# N3 key: push-to-talk voice input via VocoType (Qwen3-ASR).
#
# TOGGLE mode (the only reliable one): the deck's button reports press and
# release back-to-back even when held (measured: 0.02s), so down/up pairing
# can never work. Bind:  down = "n3-voice.sh toggle",  up = "" (empty!).
#   1st press -> keydown F9 (recording starts) + state file + notification
#   2nd press -> keyup F9  (recording stops, vocotype transcribes + pastes)
# If the state file ever desyncs, the next press self-heals.
set -euo pipefail

STATE="${XDG_RUNTIME_DIR:-/tmp}/n3-voice-recording"

case "${1:-toggle}" in
    toggle)
        if [ -f "$STATE" ]; then
            rm -f "$STATE"
            xdotool keyup F9
        else
            xdotool keydown F9
            touch "$STATE"
            notify-send -t 2500 '语音输入' '录音中…说完再按一次 4 号键' >/dev/null 2>&1 &
        fi
        ;;
    down)
        xdotool keydown F9
        touch "$STATE"
        notify-send -t 2500 '语音输入' '录音中…说完再按一次 4 号键' >/dev/null 2>&1 &
        ;;
    up)
        rm -f "$STATE"
        xdotool keyup F9
        ;;
esac
