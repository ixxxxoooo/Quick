#!/usr/bin/env bash
#
# Quick — 构建 .app。
#
#   ./Scripts/build.sh            构建 Debug
#   ./Scripts/build.sh --run      构建并启动
#   ./Scripts/build.sh --path     只打印产物路径
#   ./Scripts/build.sh --release  构建 Release
#
# 用了固定的 derivedDataPath，所以产物路径是确定的，
# --run / --path 不需要去猜 Xcode 把东西放哪了。
#
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
readonly ROOT="$PWD"

readonly DERIVED_DATA="$ROOT/build/DerivedData"
readonly CONFIG="Debug"

run_after=false
print_path_only=false
config="$CONFIG"

for arg in "$@"; do
    case "$arg" in
    --run) run_after=true ;;
    --path) print_path_only=true ;;
    --release) config="Release" ;;
    *)
        echo "未知参数: $arg" >&2
        exit 2
        ;;
    esac
done

readonly APP="$DERIVED_DATA/Build/Products/$config/Quick.app"

if [[ "$print_path_only" == true ]]; then
    echo "$APP"
    exit 0
fi

# 工程由 project.yml 生成；缺失时先生成，避免「改了 project.yml 忘了 generate」。
if [[ ! -d Quick.xcodeproj ]]; then
    echo "==> Quick.xcodeproj 不存在，正在生成"
    xcodegen generate
fi

echo "==> 构建 Quick（${config}）"
xcodebuild \
    -project Quick.xcodeproj \
    -scheme Quick \
    -configuration "$config" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    build 2>&1 | grep -E 'error:|warning:.*\.swift|BUILD (SUCCEEDED|FAILED)' || true

if [[ ! -d "$APP" ]]; then
    echo "✗ 构建失败：找不到 $APP" >&2
    exit 1
fi

echo "    ✓ $APP"

if [[ "$run_after" == true ]]; then
    echo "==> 启动"
    # 先杀掉旧实例，否则 open 只会把已有实例带到前台，你调试的其实是旧二进制。
    pkill -f 'Quick.app/Contents/MacOS/Quick' 2>/dev/null || true
    sleep 0.3
    open "$APP"
    echo "    ✓ 已启动。日志：./Scripts/logs.sh"
fi
