#!/usr/bin/env bash
# OpenDeck key 2 "认知发芽助手": grab the current selection, send it to
# DeepSeek (deepseek-v4-flash) with the prompt from
# ~/.config/streamdock-n3/key2-prompt.txt, then append the result to today's
# inbox file under ~/认知种子/.
#
# Flow:
#   1. back up the clipboard, then Ctrl+C and poll until the clipboard
#      actually changes (never analyse stale contents)
#   2. if nothing new was grabbed -> notify, exit
#   3. call DeepSeek with the configurable prompt
#   4. show the result in a zenity review dialog; only 保存 continues,
#      丢弃 discards it without writing anything
#   5. append original text + result to ~/认知种子/认知种子-YYYY-MM-DD.md,
#      and if section 10 routes it to 知识卡片/项目种子 also save a
#      standalone copy under ~/认知种子/已发芽/
#   6. any failure -> notify-send the reason, never paste garbage
#
# Safety switch: CLIPBOARD_ONLY=1 skips steps 1 and 4 (no Ctrl+C, no review
# dialog), so the script can be tested safely using the existing clipboard
# contents. N3_FORCE_CONFIRM=1 re-enables the review dialog in test mode.
set -euo pipefail

# Immediate press feedback: the analysis takes ~20s, so confirm the keypress
# right away instead of staying silent.
notify-send -a "OpenDeck" -i dialog-information "认知发芽" "已收到按键，正在分析…约 20 秒后弹出审阅窗" -t 8000 || true

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
    notify-send -a "OpenDeck" -i dialog-error "认知发芽" "缺少 N3_AI_DECK_API_KEY" || true
    exit 1
fi

# Step 1: back up the clipboard and grab the current selection. Then poll
# until the clipboard actually changes — browsers can take a moment to serve
# the copy, and analysing stale clipboard contents is worse than aborting.
# Always request the UTF8_STRING target first: Chrome puts HTML on the
# clipboard, and the default target would hand us raw markup instead of text.
LOG="$HOME/.cache/n3-sprout.log"
echo "$(date '+%F %T') triggered mode=${CLIPBOARD_ONLY:-0}" >> "$LOG"

read_clip() {
    xclip -selection clipboard -t UTF8_STRING -o 2>/dev/null || xclip -selection clipboard -o 2>/dev/null || true
}

BACKUP=""
if [ "${CLIPBOARD_ONLY:-0}" != "1" ]; then
    BACKUP="$(read_clip)"
    xdotool key ctrl+c
    CHANGED=0
    for _ in $(seq 1 15); do
        sleep 0.1
        NEW="$(read_clip)"
        if [ -n "$NEW" ] && [ "$NEW" != "$BACKUP" ]; then
            CHANGED=1
            break
        fi
    done
    if [ "$CHANGED" != "1" ]; then
        echo "$(date '+%F %T') no new selection, abort" >> "$LOG"
        notify-send -a "OpenDeck" -i dialog-information "认知发芽" "没有检测到新选中的文字，请先选中文字再按" || true
        exit 0
    fi
fi

# Step 3: read the clipboard.
TEXT="$(read_clip)"
TEXT="$(printf '%s' "$TEXT" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

if [ -z "$TEXT" ]; then
    if [ -n "$BACKUP" ]; then
        printf '%s' "$BACKUP" | xclip -selection clipboard -i
    fi
    notify-send -a "OpenDeck" -i dialog-information "认知发芽" "没有选中文字" || true
    exit 0
fi

# Step 4: call DeepSeek. The payload is built with python3 so the text needs
# no shell escaping. The prompt prefix is configurable: edit
# ~/.config/streamdock-n3/key2-prompt.txt to change what key 2 does.
PROMPT_FILE="$HOME/.config/streamdock-n3/key2-prompt.txt"
if [ -f "$PROMPT_FILE" ]; then
    PROMPT="$(cat "$PROMPT_FILE")"
else
    PROMPT="把下面的文字总结成一句话，用中文回答："
fi

PAYLOAD="$(printf '%s' "$TEXT" | python3 -c '
import json, sys
text = sys.stdin.read().strip()
prompt = sys.argv[2] + "\n\n" + text
print(json.dumps({
    "model": sys.argv[1],
    "messages": [{"role": "user", "content": prompt}],
    "stream": False,
}, ensure_ascii=False))
' "$MODEL" "$PROMPT")"

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
    notify-send -a "OpenDeck" -i dialog-error "认知发芽" "DeepSeek 调用失败：$RESPONSE" || true
    exit 1
fi

if [ -z "$RESULT" ]; then
    notify-send -a "OpenDeck" -i dialog-error "认知发芽" "DeepSeek 返回为空" || true
    exit 1
fi

echo "$(date '+%F %T') got result, awaiting review" >> "$LOG"

# Step 5: human review gate — show the result in a zenity dialog and only
# save it if the user clicks 保存; 丢弃 discards it and nothing is written.
# Skipped in CLIPBOARD_ONLY test mode unless N3_FORCE_CONFIRM=1 (used for
# end-to-end testing of the dialog itself).
if [ "${CLIPBOARD_ONLY:-0}" != "1" ] || [ "${N3_FORCE_CONFIRM:-0}" = "1" ]; then
    REVIEW_TMP="$(mktemp "$HOME/.cache/n3-review-XXXXXX.md")"
    {
        printf '> 原始记录：\n'
        printf '%s\n' "$TEXT" | sed 's/^/> /'
        printf '\n%s\n' "$RESULT"
    } > "$REVIEW_TMP"
    if ! DISPLAY="${DISPLAY:-:1}" zenity --text-info \
        --title="认知发芽 · 审阅（点保存才会入库）" \
        --filename="$REVIEW_TMP" --width=900 --height=700 \
        --ok-label="保存" --cancel-label="丢弃" 2>/dev/null; then
        rm -f "$REVIEW_TMP"
        notify-send -a "OpenDeck" -i dialog-information "认知发芽" "已丢弃，未保存" || true
        exit 0
    fi
    rm -f "$REVIEW_TMP"
fi

# Step 6: append the approved result (plus the original text) to today's inbox
# file under ~/认知种子/. Also keep a copy on the clipboard for manual pasting.
OUT_DIR="$HOME/认知种子"
OUT_FILE="$OUT_DIR/认知种子-$(date +%F).md"
mkdir -p "$OUT_DIR"

{
    printf '## %s\n\n' "$(date +%H:%M)"
    printf '> 原始记录：\n'
    printf '%s\n' "$TEXT" | sed 's/^/> /'
    printf '\n%s\n\n---\n\n' "$RESULT"
} >> "$OUT_FILE"

# Routing layer: if section 10 routes this seed to 知识卡片 or 项目种子, also
# save a standalone copy under 认知种子/已发芽/ named after the AI-generated
# title, so valuable seeds get their own identity for later filing. Everything
# still lands in the daily inbox file above.
SPROUT_TITLE="$(printf '%s' "$RESULT" | python3 -c '
import re, sys
text = sys.stdin.read()
m = re.search(r"# 10\. 系统路由\s*\n(.*?)(?=\n# |\Z)", text, re.S)
route = m.group(1) if m else ""
# ignore negated mentions like "不进入知识卡片"
hit = False
for line in route.splitlines():
    for kw in ("知识卡片", "项目种子"):
        i = line.find(kw)
        if i >= 0 and "不" not in line[max(0, i-4):i]:
            hit = True
if not hit:
    sys.exit(0)
t = re.search(r"标题[：:]\s*\*?\*?(.+?)\*?\*?\s*$", text, re.M)
title = t.group(1).strip() if t else ""
title = re.sub(r"[\\/:*?\"<>|]", "", title)[:50].strip()
print(title)
')"

SPROUT_FILE=""
if [ -n "$SPROUT_TITLE" ]; then
    SPROUT_DIR="$OUT_DIR/已发芽"
    mkdir -p "$SPROUT_DIR"
    SPROUT_FILE="$SPROUT_DIR/$(date +%F)-$SPROUT_TITLE.md"
    if [ -e "$SPROUT_FILE" ]; then
        SPROUT_FILE="$SPROUT_DIR/$(date +%F-%H%M)-$SPROUT_TITLE.md"
    fi
    {
        printf '> 原始记录（%s）：\n' "$(date '+%F %H:%M')"
        printf '%s\n' "$TEXT" | sed 's/^/> /'
        printf '\n%s\n' "$RESULT"
    } > "$SPROUT_FILE"
fi

printf '%s' "$RESULT" | xclip -selection clipboard -i
if [ -n "$SPROUT_FILE" ]; then
    notify-send -a "OpenDeck" -i dialog-information "认知发芽" "已存入收集箱，并发芽为：$SPROUT_TITLE" || true
else
    notify-send -a "OpenDeck" -i dialog-information "认知发芽" "已存入今日收集箱" || true
fi

