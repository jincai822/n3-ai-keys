#!/usr/bin/env bash
# n3-common.sh — shared functions for n3-ai-paste.sh and n3-prompt-paste.sh.
# Source this file, don't execute it directly.
#
# Provides:
#   n3_load_env          — load API key from ~/.config/streamdock-n3/service.env
#   n3_grab_text         — grab selected text (Ctrl+C + polling + PRIMARY fallback)
#   n3_call_api PROMPT   — call OpenAI-compatible chat API; sets RESULT
#   n3_paste_back        — paste clipboard with terminal-aware key selection
#
# Required globals (set before sourcing or inside the caller):
#   N3_APP_NAME   — notification app name (e.g. "OpenDeck")
#   N3_LABEL      — human-readable label for notifications (e.g. "AI 总结")

# ---------- environment / API key ----------

n3_load_env() {
    local env_file="$HOME/.config/streamdock-n3/service.env"
    if [ -f "$env_file" ]; then
        set -a
        # shellcheck disable=SC1091
        . "$env_file"
        set +a
    fi
    if [ -z "${N3_AI_DECK_API_KEY:-}" ]; then
        notify-send -a "$N3_APP_NAME" -i dialog-error "$N3_LABEL" "缺少 N3_AI_DECK_API_KEY" || true
        return 1
    fi
}

# ---------- grab selected text ----------

# After calling n3_grab_text, these globals are set:
#   TEXT     — the grabbed text (trimmed), or empty
#   BACKUP   — the original clipboard content before grabbing
#   ACTIVE_CLASS — the WM_CLASS of the active window (lowercased)
#   IS_TERMINAL — 1 if the active window is a terminal, 0 otherwise

n3_grab_text() {
    BACKUP=""
    TEXT=""
    ACTIVE_CLASS=""
    IS_TERMINAL=0

    if [ "${CLIPBOARD_ONLY:-0}" = "1" ]; then
        return 0
    fi

    BACKUP="$(xclip -selection clipboard -o 2>/dev/null || true)"

    # In terminals Ctrl+C means SIGINT, not copy — skip it and rely on
    # the PRIMARY selection (highlighted text) instead.
    ACTIVE_CLASS="$(xprop -id "$(xdotool getactivewindow 2>/dev/null)" WM_CLASS 2>/dev/null | tr 'A-Z' 'a-z')"
    case "$ACTIVE_CLASS" in
        *gnome-terminal*|*konsole*|*xfce4-terminal*|*xterm*|*kitty*|*alacritty*|*wezterm*) IS_TERMINAL=1 ;;
    esac

    if [ "$IS_TERMINAL" = "0" ]; then
        xdotool key ctrl+c
        # Poll up to 1.5s for the clipboard to actually change (slow apps need time).
        local clip_text
        for _ in 1 2 3 4 5 6; do
            sleep 0.25
            clip_text="$(xclip -selection clipboard -o 2>/dev/null || true)"
            if [ "$clip_text" != "$BACKUP" ]; then
                TEXT="$clip_text"
                break
            fi
        done
    fi

    # Fallback: X PRIMARY selection (whatever is currently highlighted).
    if [ "$IS_TERMINAL" = "1" ] || [ "$TEXT" = "$BACKUP" ]; then
        local primary
        primary="$(xclip -selection primary -o 2>/dev/null || true)"
        if [ -n "$primary" ]; then
            TEXT="$primary"
        fi
    fi
}

# Trim TEXT and handle empty case. Returns 1 if empty (after restoring backup).
n3_finalize_text() {
    # If TEXT is still empty (CLIPBOARD_ONLY mode), read the clipboard.
    if [ -z "$TEXT" ]; then
        TEXT="$(xclip -selection clipboard -o 2>/dev/null || true)"
    fi
    TEXT="$(printf '%s' "$TEXT" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

    if [ -z "$TEXT" ]; then
        if [ -n "$BACKUP" ]; then
            printf '%s' "$BACKUP" | xclip -selection clipboard -i
        fi
        notify-send -a "$N3_APP_NAME" -i dialog-information "$N3_LABEL" "没有选中文字" || true
        return 1
    fi
    return 0
}

# ---------- API call ----------

# n3_call_api PROMPT_TEXT
# Calls the API and sets RESULT on success. Returns 1 on failure.
n3_call_api() {
    local prompt_text="$1"
    local api_base="${DEEPSEEK_BASE_URL:-https://api.deepseek.com}"
    local model="${DEEPSEEK_MODEL:-deepseek-v4-flash}"

    local payload
    payload="$(printf '%s' "$TEXT" | N3_PROMPT="$prompt_text" python3 -c '
import json, os, sys
text = sys.stdin.read().strip()
prompt = os.environ["N3_PROMPT"].strip() + "\n\n" + text
print(json.dumps({
    "model": sys.argv[1],
    "messages": [{"role": "user", "content": prompt}],
    "stream": False,
}, ensure_ascii=False))
' "$model")"

    local response
    response="$(curl -sS --max-time 60 "$api_base/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $N3_AI_DECK_API_KEY" \
        --data "$payload")"

    if ! RESULT="$(printf '%s' "$response" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    content = data["choices"][0]["message"]["content"].strip()
except Exception:
    sys.exit(1)
print(content)
')"; then
        return 1
    fi

    if [ -z "$RESULT" ]; then
        return 1
    fi
    return 0
}

# ---------- paste back ----------

n3_paste_back() {
    if [ "${CLIPBOARD_ONLY:-0}" = "1" ]; then
        return 0
    fi
    sleep 0.3
    local paste_key="ctrl+v"
    case "$ACTIVE_CLASS" in
        *gnome-terminal*|*konsole*|*xfce4-terminal*|*xterm*|*kitty*|*alacritty*|*wezterm*|*orca*)
            # In terminals, highlighting text does NOT select it for editing.
            # Pasting would only INSERT at cursor, leaving the original text in
            # place. Since we cannot reliably know the cursor position after the
            # async AI call, we show the result in a persistent notification
            # instead of pasting. The result is also on the clipboard.
            notify-send -a "$N3_APP_NAME" -i dialog-information "$N3_LABEL" \
                "结果已复制到剪贴板，请手动粘贴（Ctrl+Shift+V）" -t 15000 || true
            return 0
            ;;
    esac
    xdotool key "$paste_key"
}
