#!/usr/bin/env bash
# n3-doctor.sh — N3 设备一键自检工具
# 用法: bash n3-doctor.sh
# 设备不亮/按键没反应时先运行本脚本，它会逐层检查并告诉你哪里出了问题。
set -u

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓ $1${NC}"; }
bad()  { echo -e "${RED}✗ $1${NC}"; }
tip()  { echo -e "${YELLOW}  → $1${NC}"; }

FAIL=0

echo "==============================="
echo "  N3 设备自检"
echo "==============================="
echo ""

# 检查 1: USB 是否识别
echo "[1/5] 检查 USB 设备..."
if lsusb | grep -q "6602:1000"; then
    ok "电脑已识别 N3 设备（6602:1000）"
else
    bad "电脑没有检测到 N3 设备"
    tip "检查 USB 线是否插好，换一个 USB 口试试"
    tip "如果换口无效，换一根 USB 数据线（有的线只能充电）"
    FAIL=$((FAIL+1))
    echo ""
    echo "USB 层都没通过，后面的检查跳过。先解决连接问题。"
    exit 1
fi

# 检查 2: udev 权限规则
echo ""
echo "[2/5] 检查权限规则..."
if [ -f /etc/udev/rules.d/60-n3-ai-deck.rules ] || [ -f /etc/udev/rules.d/99-n3-ai-deck.rules ]; then
    ok "udev 权限规则已安装"
else
    bad "缺少 udev 权限规则"
    tip "运行以下命令安装："
    tip "echo 'SUBSYSTEM==\"hidraw\", ATTRS{idVendor}==\"6602\", ATTRS{idProduct}==\"1000\", TAG+=\"uaccess\"' | sudo tee /etc/udev/rules.d/60-n3-ai-deck.rules"
    tip "sudo udevadm control --reload-rules && sudo udevadm trigger"
    tip "然后拔插一次设备"
    FAIL=$((FAIL+1))
fi

# 检查 3: 用户是否有 hidraw 访问权限
echo ""
echo "[3/5] 检查设备访问权限..."
HIDRAW_OK=0
for h in /dev/hidraw*; do
    [ -e "$h" ] || continue
    # 找到属于 N3 的 hidraw 节点
    udev_info="$(udevadm info "$h" 2>/dev/null)"
    if echo "$udev_info" | grep -q "6602" && echo "$udev_info" | grep -qi "1000"; then
        if [ -r "$h" ] && [ -w "$h" ]; then
            HIDRAW_OK=1
            ok "你的用户可以读写 $h"
            break
        fi
    fi
done
if [ "$HIDRAW_OK" = "0" ]; then
    bad "找不到可读写的 N3 hidraw 节点"
    tip "拔掉 USB 线，等 3 秒，插回去（让权限规则重新生效）"
    FAIL=$((FAIL+1))
fi

# 检查 4: OpenDeck 是否在运行
echo ""
echo "[4/5] 检查 OpenDeck..."
if pgrep -f "/usr/bin/opendeck" >/dev/null 2>&1; then
    ok "OpenDeck 正在运行"
else
    bad "OpenDeck 没有运行"
    tip "从应用菜单打开 OpenDeck"
    FAIL=$((FAIL+1))
fi

# 检查 5: akp03 插件是否连上设备
echo ""
echo "[5/5] 检查 akp03 插件连接..."
AKP03_PID="$(pgrep -f "opendeck-akp03" | head -1 || true)"
if [ -z "$AKP03_PID" ]; then
    bad "akp03 插件进程不存在"
    tip "重启 OpenDeck：托盘图标右键 → Quit → 重新打开"
    FAIL=$((FAIL+1))
elif ls -l "/proc/$AKP03_PID/fd" 2>/dev/null | grep -q "hidraw"; then
    ok "akp03 插件已连接设备"
else
    bad "akp03 插件在运行，但没有连上设备"
    tip "第一步：拔掉 USB 线，等 3 秒，插回去"
    tip "第二步：还不行就重启 OpenDeck（托盘右键 → Quit → 重新打开）"
    FAIL=$((FAIL+1))
fi

# 总结
echo ""
echo "==============================="
if [ "$FAIL" = "0" ]; then
    echo -e "${GREEN}  全部通过！设备链路正常。${NC}"
    echo "  如果屏幕还是不亮，重启 OpenDeck 刷新一次图标。"
else
    echo -e "${RED}  发现 $FAIL 个问题，按上面的提示逐个处理。${NC}"
fi
echo "==============================="
