#!/usr/bin/env bash
#
# Quick — 重新构建并重启最新 Debug 实例。
#
# 日常改完代码后手跑这一条，确保热键和面板跑的是刚编出来的二进制：
#
#   ./Scripts/restart.sh              构建 Debug → 杀旧进程 → 启动新实例
#   ./Scripts/restart.sh --show       同上，启动后立刻弹出面板
#   ./Scripts/restart.sh --no-build   不构建，只杀旧进程并启动已有产物
#   ./Scripts/restart.sh --release    对 Release（Quick.app）做同样的事
#
# 为什么必须先杀再开：旧进程占着 ⌥Space，新实例注册热键会失败，
# 表现就是「改了却没生效」。见 AGENTS.md「每次改动的收尾」。
#
# @author ygw
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
readonly ROOT="$PWD"

show_palette=false
skip_build=false
config="Debug"

for arg in "$@"; do
    case "$arg" in
    --show | --show-palette) show_palette=true ;;
    --no-build) skip_build=true ;;
    --release) config="Release" ;;
    -h | --help)
        sed -n '2,16p' "$0" | sed 's/^# \?//'
        exit 0
        ;;
    *)
        echo "未知参数: $arg" >&2
        echo "用法: ./Scripts/restart.sh [--show] [--no-build] [--release]" >&2
        exit 2
        ;;
    esac
done

if [[ "$config" == "Debug" ]]; then
    readonly APP_PRODUCT="Quick Dev.app"
    readonly PROCESS_PATTERN='Quick Dev'
    readonly LOG_FLAG='--dev'
else
    readonly APP_PRODUCT="Quick.app"
    readonly PROCESS_PATTERN='Quick.app/Contents/MacOS/Quick'
    readonly LOG_FLAG=''
fi

readonly APP="$ROOT/build/DerivedData/Build/Products/$config/$APP_PRODUCT"

# ---------------------------------------------------------------------------
# 1. 构建（可跳过）
# ---------------------------------------------------------------------------
if [[ "$skip_build" == false ]]; then
    if [[ "$config" == "Release" ]]; then
        ./Scripts/build.sh --release
    else
        ./Scripts/build.sh
    fi
else
    if [[ ! -d "$APP" ]]; then
        echo "✗ 找不到产物：$APP" >&2
        echo "  先跑一次 ./Scripts/build.sh 再 --no-build。" >&2
        exit 1
    fi
    echo "==> 跳过构建，使用已有产物"
    echo "    $APP"
fi

# ---------------------------------------------------------------------------
# 2. 杀掉旧实例（必须在 open -n 之前）
# ---------------------------------------------------------------------------
echo "==> 结束旧进程 (${PROCESS_PATTERN})"
# 先按产物路径精确杀，再按显示名兜底，避免漏掉残留。
pkill -f "${APP_PRODUCT}/Contents/MacOS/" 2>/dev/null || true
pkill -f "${PROCESS_PATTERN}" 2>/dev/null || true

# 等到进程真正退出，最多等 3 秒。
for _ in 1 2 3 4 5 6; do
    if ! pgrep -f "${PROCESS_PATTERN}" >/dev/null 2>&1; then
        break
    fi
    sleep 0.5
done

if pgrep -f "${PROCESS_PATTERN}" >/dev/null 2>&1; then
    echo "    ⚠️  旧进程仍在，强制结束"
    pkill -9 -f "${PROCESS_PATTERN}" 2>/dev/null || true
    sleep 0.5
fi
echo "    ✓ 旧进程已退出"

# ---------------------------------------------------------------------------
# 3. 启动新实例
# ---------------------------------------------------------------------------
echo "==> 启动新实例"
# -n：强制新实例。不加的话 open 可能只把旧进程（若漏杀）带到前台。
if [[ "$show_palette" == true ]]; then
    open -n "$APP" --args -showPalette
    echo "    ✓ 已启动并弹出面板"
else
    open -n "$APP"
    echo "    ✓ 已启动（⌥Space 或菜单「显示 Quick」唤出面板）"
fi

echo "    日志: ./Scripts/logs.sh ${LOG_FLAG}"
