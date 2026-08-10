#!/usr/bin/env bash
# OpenDeck key "AI总结": grab the current selection, summarize it into one
# Chinese sentence via DeepSeek, then paste the result back into the focused
# window.
#
# Flow:
#   1. back up the clipboard, then Ctrl+C to grab the current selection
#   2. if the grabbed text is empty -> restore the backup, notify, exit
#   3. call DeepSeek (deepseek-v4-flash) to summarize into one Chinese sentence
#   4. put the result on the clipboard (piped via stdin to avoid escaping bugs)
#   5. paste it back with Ctrl+V
#   6. any failure -> notify-send the reason, never paste garbage
#
# Safety switch: CLIPBOARD_ONLY=1 skips steps 1 and 5 (no Ctrl+C / Ctrl+V),
# so the script can be tested safely without touching the keyboard.
set -euo pipefail

API_BASE="${DEEPSEEK_BASE_URL:-https://api.deepseek.com}"
MODEL="${DEEPSEEK_MODEL:-deepseek-v4-flash}"
ENV_FILE="$HOME/.config/streamdock-n3/service.env"

# Load the API key at runtime; never echo it.
if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$ENV_FILE"
    set +a
fi

if [ -z "${N3_AI_DECK_API_KEY:-}" ]; then
    notify-send -a "OpenDeck" -i dialog-error "AI 总结" "缺少 N3_AI_DECK_API_KEY" || true
    exit 1
fi

# Step 1: back up the clipboard and grab the current selection.
BACKUP=""
if [ "${CLIPBOARD_ONLY:-0}" != "1" ]; then
    BACKUP="$(xclip -selection clipboard -o 2>/dev/null || true)"
    xdotool key ctrl+c
    sleep 0.3
fi

# Step 3: read the clipboard.
TEXT="$(xclip -selection clipboard -o 2>/dev/null || true)"
TEXT="$(printf '%s' "$TEXT" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

if [ -z "$TEXT" ]; then
    if [ -n "$BACKUP" ]; then
        printf '%s' "$BACKUP" | xclip -selection clipboard -i
    fi
    notify-send -a "OpenDeck" -i dialog-information "AI 总结" "没有选中文字" || true
    exit 0
fi

# Step 4: call DeepSeek. The payload is built with python3 so the text needs
# no shell escaping.
PAYLOAD="$(printf '%s' "$TEXT" | python3 -c '
import json, sys
text = sys.stdin.read().strip()
prompt = "把下面的文字总结成一句话，用中文回答：\n\n" + text
print(json.dumps({
    "model": sys.argv[1],
    "messages": [{"role": "user", "content": prompt}],
    "stream": False,
}, ensure_ascii=False))
' "$MODEL")"

RESPONSE="$(curl -sS --max-time 60 "$API_BASE/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $N3_AI_DECK_API_KEY" \
    --data "$PAYLOAD")"

if ! RESULT="$(printf '%s' "$RESPONSE" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    content = data["choices"][0]["message"]["content"].strip()
except Exception:
    sys.exit(1)
print(content)
')"; then
    notify-send -a "OpenDeck" -i dialog-error "AI 总结" "DeepSeek 调用失败：$RESPONSE" || true
    exit 1
fi

if [ -z "$RESULT" ]; then
    notify-send -a "OpenDeck" -i dialog-error "AI 总结" "DeepSeek 返回为空" || true
    exit 1
fi

# Step 5: put the result on the clipboard (stdin pipe to avoid escaping bugs).
printf '%s' "$RESULT" | xclip -selection clipboard -i

# Step 6: paste it back into the focused window.
if [ "${CLIPBOARD_ONLY:-0}" != "1" ]; then
    sleep 0.3
    xdotool key ctrl+v
fi
