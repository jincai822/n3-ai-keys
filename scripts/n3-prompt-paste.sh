#!/usr/bin/env bash
# OpenDeck key "提示词优化": grab the current selection, rewrite it into a
# well-structured prompt via DeepSeek, then paste the result back into the
# focused window.
#
# Every step is logged to ~/.cache/n3-prompt.log for debugging.
# Safety switch: CLIPBOARD_ONLY=1 skips Ctrl+C / Ctrl+V.
set -euo pipefail

N3_APP_NAME="OpenDeck"
N3_LABEL="提示词优化"
LOG="$HOME/.cache/n3-prompt.log"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }
log "=== run start (CLIPBOARD_ONLY=${CLIPBOARD_ONLY:-0}) ==="

# shellcheck source=n3-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/n3-common.sh"

n3_load_env || { log "ERROR: missing N3_AI_DECK_API_KEY"; exit 1; }

# Step 1: grab selected text.
n3_grab_text

# prompt-paste has a stricter empty check: error instead of silent exit.
if [ "${CLIPBOARD_ONLY:-0}" != "1" ] && [ -z "$TEXT" ]; then
    if [ -z "$(printf '%s' "${TEXT:-}" | tr -d '[:space:]')" ]; then
        log "ERROR: no copied text and no PRIMARY selection"
        notify-send -a "$N3_APP_NAME" -i dialog-error "$N3_LABEL" "没有检测到选中的文字：请先选中文字，再按本键" || true
        exit 1
    fi
fi

if ! n3_finalize_text; then
    log "empty selection, restored backup"
    exit 0
fi
log "input text (${#TEXT} chars): ${TEXT:0:80}"

notify-send -a "$N3_APP_NAME" -i dialog-information "$N3_LABEL" "优化中…约需 5~30 秒，期间请勿切换窗口" -t 35000 || true

# Step 2: build the prompt from the style config file.
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

# Step 3: call DeepSeek.
START=$(date +%s)
if ! n3_call_api "$STYLE"; then
    log "ERROR: DeepSeek call failed or returned empty"
    notify-send -a "$N3_APP_NAME" -i dialog-error "$N3_LABEL" "DeepSeek 调用失败，请稍后再试" || true
    exit 1
fi
log "API call took $(( $(date +%s) - START ))s"

# Step 4: put the result on the clipboard (stdin pipe to avoid escaping bugs).
printf '%s' "$RESULT" | xclip -selection clipboard -i
log "result (${#RESULT} chars): ${RESULT:0:80}"

# Step 5: paste it back into the focused window.
n3_paste_back
log "pasted"
log "=== run done ==="
