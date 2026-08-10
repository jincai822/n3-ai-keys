#!/usr/bin/env bash
# OpenDeck key "提示词优化": grab the current selection, rewrite it into a
# well-structured prompt via DeepSeek, then paste the result back into the
# focused window. No browser involved — one keypress does everything.
#
# Flow identical to n3-ai-paste.sh:
#   1. back up the clipboard, then Ctrl+C to grab the current selection
#   2. empty selection -> restore the backup, notify, exit
#   3. call DeepSeek to rewrite the text as an optimized prompt
#   4. put the result on the clipboard (piped via stdin to avoid escaping bugs)
#   5. paste it back with Ctrl+V
#   6. any failure -> notify-send the reason, never paste garbage
#
# Safety switch: CLIPBOARD_ONLY=1 skips steps 1 and 5 (no Ctrl+C / Ctrl+V).
# Every step is logged to ~/.cache/n3-prompt.log for debugging.
set -euo pipefail

API_BASE="${DEEPSEEK_BASE_URL:-https://api.deepseek.com}"
MODEL="${DEEPSEEK_MODEL:-deepseek-v4-flash}"
ENV_FILE="$HOME/.config/streamdock-n3/service.env"
LOG="$HOME/.cache/n3-prompt.log"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }
log "=== run start (CLIPBOARD_ONLY=${CLIPBOARD_ONLY:-0}) ==="

# Load the API key at runtime; never echo it.
if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$ENV_FILE"
    set +a
fi

if [ -z "${N3_AI_DECK_API_KEY:-}" ]; then
    log "ERROR: missing N3_AI_DECK_API_KEY"
    notify-send -a "OpenDeck" -i dialog-error "提示词优化" "缺少 N3_AI_DECK_API_KEY" || true
    exit 1
fi

# Step 1: back up the clipboard and grab the current selection.
BACKUP=""
TEXT=""
if [ "${CLIPBOARD_ONLY:-0}" != "1" ]; then
    BACKUP="$(xclip -selection clipboard -o 2>/dev/null || true)"

    # In terminals Ctrl+C means SIGINT, not copy — skip it and rely on
    # the PRIMARY selection (highlighted text) instead.
    ACTIVE_CLASS="$(xprop -id "$(xdotool getactivewindow 2>/dev/null)" WM_CLASS 2>/dev/null | tr 'A-Z' 'a-z')"
    IS_TERMINAL=0
    case "$ACTIVE_CLASS" in
        *gnome-terminal*|*konsole*|*xfce4-terminal*|*xterm*|*kitty*|*alacritty*|*wezterm*) IS_TERMINAL=1 ;;
    esac

    if [ "$IS_TERMINAL" = "0" ]; then
        xdotool key ctrl+c
        # Poll up to 1.5s for the clipboard to actually change (slow apps need time).
        for _ in 1 2 3 4 5 6; do
            sleep 0.25
            TEXT="$(xclip -selection clipboard -o 2>/dev/null || true)"
            [ "$TEXT" != "$BACKUP" ] && break
        done
    fi

    # Fallback: X PRIMARY selection (whatever is currently highlighted).
    # Covers terminals and any app where the synthetic Ctrl+C did not land.
    if [ "$IS_TERMINAL" = "1" ] || [ "$TEXT" = "$BACKUP" ]; then
        PRIMARY="$(xclip -selection primary -o 2>/dev/null || true)"
        if [ -n "$PRIMARY" ]; then
            TEXT="$PRIMARY"
            log "using PRIMARY selection fallback (terminal=$IS_TERMINAL)"
        fi
    fi

    if [ -z "$(printf '%s' "$TEXT" | tr -d '[:space:]')" ]; then
        log "ERROR: no copied text and no PRIMARY selection"
        notify-send -a "OpenDeck" -i dialog-error "提示词优化" "没有检测到选中的文字：请先选中文字，再按本键" || true
        exit 1
    fi
fi

# Step 2: read the clipboard.
TEXT="$(xclip -selection clipboard -o 2>/dev/null || true)"
TEXT="$(printf '%s' "$TEXT" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
log "input text (${#TEXT} chars): ${TEXT:0:80}"

if [ -z "$TEXT" ]; then
    if [ -n "$BACKUP" ]; then
        printf '%s' "$BACKUP" | xclip -selection clipboard -i
    fi
    log "empty selection, restored backup"
    notify-send -a "OpenDeck" -i dialog-information "提示词优化" "没有选中文字" || true
    exit 0
fi

notify-send -a "OpenDeck" -i dialog-information "提示词优化" "优化中…约需 5~30 秒，期间请勿切换窗口" -t 35000 || true

# Step 3: call DeepSeek. The optimization style lives in an editable config
# file (~/.config/streamdock-n3/prompt-style.txt) so the user can change the
# rewriting behavior without touching this script; fall back to the built-in
# default when the file is missing or empty.
STYLE_FILE="$HOME/.config/streamdock-n3/prompt-style.txt"
DEFAULT_STYLE='你是一位专业的提示词优化专家。请把下面这段粗糙的文字（可能是语音输入的口语）改写成可以直接发给 AI 使用的高质量提示词。
要求：
1. 完整保留原意，不遗漏任何要求；
2. 根据需要补充：角色定位、任务目标、具体要求、输出格式；
3. 不要回答文字里提出的问题，只输出优化后的提示词本身；
4. 用中文输出；
5. 直接输出提示词正文，不要用 markdown 代码块（```）包裹。'
STYLE="$DEFAULT_STYLE"
if [ -s "$STYLE_FILE" ]; then
    STYLE="$(cat "$STYLE_FILE")"
fi

PAYLOAD="$(printf '%s' "$TEXT" | N3_STYLE="$STYLE" python3 -c '
import json, os, sys
text = sys.stdin.read().strip()
prompt = os.environ["N3_STYLE"].strip() + "\n\n原始文字：\n" + text
print(json.dumps({
    "model": sys.argv[1],
    "messages": [{"role": "user", "content": prompt}],
    "stream": False,
}, ensure_ascii=False))
' "$MODEL")"

START=$(date +%s)
RESPONSE="$(curl -sS --max-time 60 "$API_BASE/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $N3_AI_DECK_API_KEY" \
    --data "$PAYLOAD")"
log "API call took $(( $(date +%s) - START ))s"

if ! RESULT="$(printf '%s' "$RESPONSE" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    content = data["choices"][0]["message"]["content"].strip()
except Exception:
    sys.exit(1)
print(content)
')"; then
    log "ERROR: DeepSeek call failed: ${RESPONSE:0:300}"
    notify-send -a "OpenDeck" -i dialog-error "提示词优化" "DeepSeek 调用失败，请稍后再试" || true
    exit 1
fi

if [ -z "$RESULT" ]; then
    log "ERROR: DeepSeek returned empty"
    notify-send -a "OpenDeck" -i dialog-error "提示词优化" "DeepSeek 返回为空" || true
    exit 1
fi

# Step 4: put the result on the clipboard (stdin pipe to avoid escaping bugs).
printf '%s' "$RESULT" | xclip -selection clipboard -i
log "result (${#RESULT} chars): ${RESULT:0:80}"

# Step 5: paste it back into the focused window. Paste shortcut depends on
# the app: terminals and the orca chat client only accept Ctrl+Shift+V
# (proven by the vocotype daemon), everything else takes plain Ctrl+V.
if [ "${CLIPBOARD_ONLY:-0}" != "1" ]; then
    sleep 0.3
    PASTE_KEY="ctrl+v"
    case "$ACTIVE_CLASS" in
        *gnome-terminal*|*konsole*|*xfce4-terminal*|*xterm*|*kitty*|*alacritty*|*wezterm*|*orca*) PASTE_KEY="ctrl+shift+v" ;;
    esac
    xdotool key "$PASTE_KEY"
    log "pasted with $PASTE_KEY"
fi
log "=== run done ==="
