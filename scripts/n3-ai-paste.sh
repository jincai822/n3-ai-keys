#!/usr/bin/env bash
# OpenDeck key "AI 智能键": multi-mode AI interaction that cycles through
# different operations with each press.
#
# Mode cycle (press LCD 2 repeatedly):
#   1st press -> ANALYZE: smart analysis (code->explain, error->diagnose, etc.)
#   2nd press -> TRANSLATE: translate to Chinese (or English if already Chinese)
#   3rd press -> SIMPLIFY: rewrite in plain language anyone can understand
#   4th press -> EXTRACT: extract action items / to-do list
#   5th press -> back to ANALYZE (cycle repeats)
#
# State is tracked in a temp file; resets to ANALYZE after 3 seconds of
# inactivity, so each fresh selection starts from ANALYZE.
#
# Safety switch: CLIPBOARD_ONLY=1 skips Ctrl+C / Ctrl+V.
set -euo pipefail

N3_APP_NAME="OpenDeck"
N3_LABEL="AI"

# shellcheck source=n3-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/n3-common.sh"

# ---------- mode state management ----------

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/n3-ai-mode"
MODES=("analyze" "translate" "simplify" "extract")
STALE_SECONDS=3

# Read current mode, advancing the cycle. Reset if stale.
get_and_advance_mode() {
    local current="analyze"
    local idx=0

    if [ -f "$STATE_FILE" ]; then
        # Check if state is stale (older than STALE_SECONDS)
        local file_age
        file_age=$(( $(date +%s) - $(stat -c %Y "$STATE_FILE" 2>/dev/null || echo 0) ))
        if [ "$file_age" -lt "$STALE_SECONDS" ]; then
            current="$(cat "$STATE_FILE")"
            # Find index and advance
            for i in "${!MODES[@]}"; do
                if [ "${MODES[$i]}" = "$current" ]; then
                    idx=$(( (i + 1) % ${#MODES[@]} ))
                    break
                fi
            done
        fi
    fi

    current="${MODES[$idx]}"
    # Save next mode for next press
    echo "${MODES[$(( (idx + 1) % ${#MODES[@]} ))]}" > "$STATE_FILE"
    echo "$current"
}

# ---------- prompts for each mode ----------

get_prompt() {
    local mode="$1"
    case "$mode" in
        analyze)
            cat <<'PROMPT'
你是一位智能助手。请分析下面这段文字，根据内容类型给出最合适的回复：
- 如果是文章/新闻：提炼 2~3 个要点，最后给一句话结论
- 如果是代码：用中文解释这段代码做什么，指出关键逻辑
- 如果是报错信息：诊断原因，给出解决方案
- 如果是数据/表格：分析趋势、异常值或关键信息
- 如果是英文：翻译成中文，并简要说明语境
- 如果是对话/聊天记录：提取关键信息和待办事项
- 如果是其他内容：给出简洁的理解和分析

要求：用中文回答，控制在 200 字以内，直接输出分析结果。
PROMPT
            ;;
        translate)
            cat <<'PROMPT'
你是专业翻译。请把下面的文字翻译成中文。如果已经是中文，则翻译成英文。
要求：翻译准确自然，保留专业术语，直接输出翻译结果。
PROMPT
            ;;
        simplify)
            cat <<'PROMPT'
你是一位善于用大白话解释复杂概念的老师。请把下面的文字用最简单、最通俗的语言重新表达，让小学生也能听懂。
要求：用日常用语，避免专业术语，可以用比喻，控制在 150 字以内，直接输出简化后的内容。
PROMPT
            ;;
        extract)
            cat <<'PROMPT'
你是一位效率专家。请从下面的文字中提取出所有需要执行的行动项/待办事项。
要求：
- 用清晰的编号列表输出
- 每条待办用动词开头（如"完成..."、"检查..."、"联系..."）
- 如果有截止日期或优先级，标注出来
- 如果没有明显的行动项，输出"未检测到明确的待办事项"
直接输出待办清单。
PROMPT
            ;;
    esac
}

# ---------- mode display names for notification ----------

get_mode_label() {
    case "$1" in
        analyze)    echo "📊 分析" ;;
        translate)  echo "🌐 翻译" ;;
        simplify)   echo "💡 简化" ;;
        extract)    echo "✅ 待办" ;;
        *)          echo "AI" ;;
    esac
}

# ---------- main flow ----------

n3_load_env || exit 1

# Determine current mode
MODE="$(get_and_advance_mode)"
MODE_LABEL="$(get_mode_label "$MODE")"
N3_LABEL="$MODE_LABEL"

# Grab selected text
n3_grab_text
if ! n3_finalize_text; then
    exit 0
fi

# Show which mode is active
notify-send -a "$N3_APP_NAME" -i dialog-information "$MODE_LABEL" "处理中…" -t 2000 || true

# Get the prompt for current mode and call API
PROMPT="$(get_prompt "$MODE")"
if ! n3_call_api "$PROMPT"; then
    notify-send -a "$N3_APP_NAME" -i dialog-error "$MODE_LABEL" "DeepSeek 调用失败" || true
    exit 1
fi

# Put result on clipboard and paste back
printf '%s' "$RESULT" | xclip -selection clipboard -i
n3_paste_back
