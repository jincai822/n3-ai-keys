#!/usr/bin/env bash
# ============================================================
# N3 AI 快捷键包 — 安装脚本
# 适用环境: Ubuntu (X11/GNOME) + OpenDeck + Mirabox N3 设备
# 用法:     进入本包目录后运行  bash install.sh
# 说明:     只写入当前用户目录下的配置，不需要 sudo
# ============================================================
set -euo pipefail

# ---------- 定位包目录（无论从哪里调用都能找到包内文件） ----------
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "===== N3 AI 快捷键包 安装开始 ====="

# ---------- 1. 检查系统依赖 ----------
echo ""
echo "==> [1/7] 检查系统依赖..."
MISSING=""
for cmd in xdotool xclip maim notify-send python3 curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING="$MISSING $cmd"
    fi
done
if [ -n "$MISSING" ]; then
    echo ""
    echo "错误: 缺少以下依赖:$MISSING"
    echo "请先复制下面这行到终端运行，装完再重新运行本脚本:"
    echo ""
    echo "  sudo apt install xdotool xclip maim libnotify-bin python3 curl"
    echo ""
    exit 1
fi

# google-chrome 是可选依赖：1 号键（打开网址）和 7 号键（打开 Chrome）需要它
if ! command -v google-chrome >/dev/null 2>&1; then
    echo "提示: 未检测到 google-chrome（可选依赖，不影响安装）。"
    echo "      如需 1 号/7 号键打开 Chrome 的功能，请自行安装 chrome 后重新运行本脚本。"
fi
echo "    依赖检查通过。"

# ---------- 2. 检查 OpenDeck 是否已安装 ----------
echo ""
echo "==> [2/7] 检查 OpenDeck..."
if [ ! -d "$HOME/.config/opendeck" ]; then
    echo "错误: 没有找到 OpenDeck 的配置目录 (~/.config/opendeck)。"
    echo "请先完成以下步骤，再重新运行本脚本:"
    echo "  1. 安装 OpenDeck 软件（.deb 包）"
    echo "  2. 安装改装版 akp03 插件（支持 Mirabox N3 设备，USB 6602:1000）"
    echo "  3. 插上 N3 设备并打开一次 OpenDeck，让它创建配置目录"
    exit 1
fi
echo "    OpenDeck 已安装。"

# ---------- 3. 探测设备序列号 ----------
# 序列号 = ~/.config/opendeck/profiles/ 下的目录名（形如 n3-XXXXXXXXXXXX）。
# 每台 N3 设备的序列号都不同，这里优先用本机已有的目录名，
# 没有就用占位名 n3-MYDEVICE，首次连接后目录名会变成真实序列号。
echo ""
echo "==> [3/7] 探测 N3 设备序列号..."
SERIAL=""
for d in "$HOME"/.config/opendeck/profiles/n3-*; do
    if [ -d "$d" ] && [ "$(basename "$d")" != "n3-MYDEVICE" ]; then
        SERIAL="$(basename "$d")"
        break
    fi
done
if [ -z "$SERIAL" ]; then
    SERIAL="n3-MYDEVICE"
    echo "    未找到已有设备目录，将使用占位名: $SERIAL"
    echo "    注意: 首次插上 N3 并打开 OpenDeck 后，配置目录名会变成设备的真实序列号"
    echo "    （形如 n3-XXXXXXXXXXXX，和本包导出的机器不同）。"
    echo "    届时请重新运行一次本脚本，即可把配置装到真实序列号目录下。"
else
    echo "    检测到设备序列号: $SERIAL"
fi

# ---------- 4. 安装快捷键脚本到 ~/.local/bin ----------
echo ""
echo "==> [4/7] 安装快捷键脚本到 ~/.local/bin ..."
mkdir -p "$HOME/.local/bin"
install -m 755 "$PKG_DIR"/scripts/n3-*.sh "$HOME/.local/bin/"
echo "    已安装 $(ls "$PKG_DIR"/scripts/n3-*.sh | wc -l) 个脚本。"

# ---------- 5. 安装提示词风格配置 ----------
echo ""
echo "==> [5/7] 安装提示词风格配置到 ~/.config/streamdock-n3 ..."
mkdir -p "$HOME/.config/streamdock-n3"
STYLE_DEST="$HOME/.config/streamdock-n3/prompt-style.txt"
if [ -f "$STYLE_DEST" ]; then
    cp "$STYLE_DEST" "$STYLE_DEST.bak"
    echo "    检测到已有的 prompt-style.txt，已备份为 prompt-style.txt.bak"
fi
install -m 644 "$PKG_DIR"/config/prompt-style.txt \
    "$PKG_DIR"/config/prompt-style-简洁版.txt \
    "$PKG_DIR"/config/prompt-style-详细版.txt \
    "$HOME/.config/streamdock-n3/"
echo "    已安装 3 个风格文件（当前生效的是 prompt-style.txt）。"
KEY2_DEST="$HOME/.config/streamdock-n3/key2-prompt.txt"
if [ -f "$KEY2_DEST" ]; then
    cp "$KEY2_DEST" "$KEY2_DEST.bak"
    echo "    检测到已有的 key2-prompt.txt，已备份为 key2-prompt.txt.bak"
fi
install -m 644 "$PKG_DIR"/config/key2-prompt.txt "$HOME/.config/streamdock-n3/"
echo "    已安装 2 号键「认知发芽助手」提示词（key2-prompt.txt，可自由编辑）。"

# ---------- 6. 写入 OpenDeck 键位配置和图标 ----------
echo ""
echo "==> [6/7] 写入 OpenDeck 键位配置..."
PROFILE_DIR="$HOME/.config/opendeck/profiles/$SERIAL"
mkdir -p "$PROFILE_DIR"
DEST="$PROFILE_DIR/Default.json"
if [ -f "$DEST" ]; then
    cp "$DEST" "$DEST.bak"
    echo "    检测到已有配置，已备份为 Default.json.bak"
fi
# 模板里的 __HOME__ 占位符替换为当前用户的主目录
sed "s|__HOME__|$HOME|g" "$PKG_DIR/profile/Default.json" > "$DEST"
echo "    键位配置已写入: $DEST"

echo "    安装 9 个按键图标..."
# 图标机制: 每个键的图标放在 images/<序列号>/Default/Keypad.X.0/0.png，
# profile 里对应键 states[].image 指向 "0.png"
for i in 0 1 2 3 4 5 6 7 8; do
    ICON_DIR="$HOME/.config/opendeck/images/$SERIAL/Default/Keypad.$i.0"
    mkdir -p "$ICON_DIR"
    install -m 644 "$PKG_DIR/icons/$((i + 1)).png" "$ICON_DIR/0.png"
done
echo "    9 个图标安装完成。"

# ---------- 7. DeepSeek API key 与语音服务检查 ----------
echo ""
echo "==> [7/7] 检查可选依赖..."
ENV_FILE="$HOME/.config/streamdock-n3/service.env"
if [ ! -f "$ENV_FILE" ]; then
    cat > "$ENV_FILE" <<'EOF'
# 2 号键（AI 智能键，4 模式循环）和 3 号键（提示词优化）需要 DeepSeek API key。
# 申请地址: https://platform.deepseek.com/
# 把下面等号后面换成你的 key 并保存即可，无需重新安装。
N3_AI_DECK_API_KEY=在这里填你的DeepSeek密钥
EOF
    chmod 600 "$ENV_FILE"
    echo "    已创建 $ENV_FILE（模板）。"
    echo "    重要: 请编辑该文件，把 N3_AI_DECK_API_KEY= 后面替换成你自己的 DeepSeek API key。"
    echo "    2 号（AI 智能键）和 3 号（提示词优化）键必须填好 key 才能使用。"
else
    echo "    已存在 $ENV_FILE，跳过创建。请自行确认其中已填好 N3_AI_DECK_API_KEY。"
fi

if systemctl --user is-active vocotype-global-f9.service >/dev/null 2>&1; then
    echo "    vocotype 语音服务正在运行，4 号键（语音输入）可用。"
else
    echo "提示: 未检测到 vocotype 语音服务（vocotype-global-f9.service）。"
    echo "      4 号键（语音输入）需要额外安装 vocotype + Qwen3-ASR 语音服务，"
    echo "      安装方法见 README.md 的「常见问题」。"
    echo "      这不影响安装结果，其余按键照常可用。"
fi

# ---------- 完成 ----------
echo ""
echo "=================================================="
echo "安装完成！最后一步: 重启 OpenDeck 使配置生效。"
echo "  方法: 在系统托盘找到 OpenDeck 图标，右键选 Quit 完全退出，"
echo "        然后再重新打开 OpenDeck。"
echo "=================================================="
