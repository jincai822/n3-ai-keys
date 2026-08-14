#!/usr/bin/env bash
# 一键恢复脚本 - 电脑重置后运行此脚本恢复所有 N3 AI Deck 配置
# 用法: bash restore.sh
set -euo pipefail

echo "=========================================="
echo "  N3 AI Deck 一键恢复脚本"
echo "=========================================="
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 错误处理
error_exit() {
    echo -e "${RED}错误: $1${NC}" >&2
    exit 1
}

# 成功提示
success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# 警告提示
warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# 检查是否已安装
check_command() {
    if command -v "$1" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# 步骤 1: 检查基础依赖
echo "步骤 1/7: 检查基础依赖..."
MISSING_DEPS=()
for cmd in git curl python3 xdotool xclip maim notify-send; do
    if ! check_command "$cmd"; then
        MISSING_DEPS+=("$cmd")
    fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    warn "缺少依赖: ${MISSING_DEPS[*]}"
    echo "正在安装缺失的依赖..."
    sudo apt update
    sudo apt install -y "${MISSING_DEPS[@]}" || error_exit "安装依赖失败"
    success "依赖安装完成"
else
    success "所有依赖已安装"
fi

# 步骤 2: 检查 OpenDeck
echo ""
echo "步骤 2/7: 检查 OpenDeck..."
if ! check_command opendeck; then
    warn "OpenDeck 未安装"
    echo ""
    echo "请手动安装 OpenDeck:"
    echo "  1. 访问 https://github.com/nekename/OpenDeck/releases"
    echo "  2. 下载最新的 .deb 包"
    echo "  3. 运行: sudo dpkg -i opendeck_*.deb"
    echo "  4. 安装完成后重新运行此脚本"
    echo ""
    read -p "按回车键继续（如果你已经安装了 OpenDeck）..."
else
    success "OpenDeck 已安装"
fi

# 步骤 3: 检查 akp03 插件
echo ""
echo "步骤 3/7: 检查 akp03 插件..."
AKP03_DIR="$HOME/.local/share/opendeck/plugins/com.amansprojects.starterpack.sdPlugin"
if [ ! -d "$AKP03_DIR" ]; then
    warn "akp03 插件未安装"
    echo ""
    echo "akp03 插件是 N3 设备的驱动，需要手动安装:"
    echo "  1. 访问 https://github.com/jincai822/opendeck-akp03/releases"
    echo "  2. 下载最新的插件包"
    echo "  3. 解压到 OpenDeck 插件目录"
    echo "  4. 重启 OpenDeck"
    echo ""
    read -p "按回车键继续（如果你已经安装了 akp03 插件）..."
else
    success "akp03 插件已安装"
fi

# 步骤 4: 克隆/更新 n3-ai-keys 仓库
echo ""
echo "步骤 4/7: 设置 n3-ai-keys 快捷键包..."
WORKSPACE="$HOME/workspace"
N3_KEYS_DIR="$WORKSPACE/n3-ai-keys"

mkdir -p "$WORKSPACE"

if [ -d "$N3_KEYS_DIR" ]; then
    echo "更新现有仓库..."
    cd "$N3_KEYS_DIR"
    git pull origin main || warn "更新失败，使用现有版本"
    success "n3-ai-keys 已更新"
else
    echo "克隆仓库..."
    git clone https://github.com/jincai822/n3-ai-keys.git "$N3_KEYS_DIR" || error_exit "克隆失败"
    success "n3-ai-keys 已克隆"
fi

# 步骤 5: 安装 udev 规则
echo ""
echo "步骤 5/7: 安装 udev 规则..."
UDEV_RULE="/etc/udev/rules.d/99-n3-ai-deck.rules"
if [ ! -f "$UDEV_RULE" ]; then
    echo "安装 udev 规则（需要 sudo 权限）..."
    sudo tee "$UDEV_RULE" > /dev/null << 'EOF'
# N3 AI Deck - Mirabox N3 V3.0 (6602:1000)
SUBSYSTEM=="usb", ATTR{idVendor}=="6602", ATTR{idProduct}=="1000", MODE="0666", GROUP="plugdev"
EOF
    sudo udevadm control --reload-rules
    sudo udevadm trigger
    success "udev 规则已安装"
else
    success "udev 规则已存在"
fi

# 步骤 6: 运行 n3-ai-keys 安装脚本
echo ""
echo "步骤 6/7: 安装快捷键包..."
cd "$N3_KEYS_DIR"
bash install.sh || error_exit "安装脚本执行失败"
success "快捷键包安装完成"

# 步骤 7: 配置 API Key
echo ""
echo "步骤 7/7: 配置 DeepSeek API Key..."
ENV_FILE="$HOME/.config/streamdock-n3/service.env"
if [ ! -f "$ENV_FILE" ] || grep -q "在这里填你的DeepSeek密钥" "$ENV_FILE"; then
    warn "API Key 未配置"
    echo ""
    echo "请配置你的 DeepSeek API Key:"
    echo "  1. 访问 https://platform.deepseek.com/ 申请 key"
    echo "  2. 编辑文件: nano $ENV_FILE"
    echo "  3. 把 N3_AI_DECK_API_KEY= 后面换成你的 key"
    echo "  4. 保存并退出"
    echo ""
    read -p "现在配置 API Key? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        nano "$ENV_FILE"
    fi
else
    success "API Key 已配置"
fi

# 完成
echo ""
echo "=========================================="
echo -e "${GREEN}  恢复完成！${NC}"
echo "=========================================="
echo ""
echo "后续步骤:"
echo "  1. 完全退出 OpenDeck（托盘图标右键 → Quit）"
echo "  2. 重新打开 OpenDeck"
echo "  3. 插入 N3 设备"
echo "  4. 测试各个按键功能"
echo ""
echo "如果遇到问题:"
echo "  - 检查 README: cat $N3_KEYS_DIR/README.md"
echo "  - 查看常见问题: https://github.com/jincai822/n3-ai-keys#常见问题"
echo ""
