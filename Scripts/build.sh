#!/usr/bin/env bash
#
# Quick — 构建 .app。
#
#   ./Scripts/build.sh            构建 Debug（Quick Dev.app / com.ixxxxoooo.quick.dev）
#   ./Scripts/build.sh --run      构建并启动
#   ./Scripts/build.sh --path     只打印产物路径
#   ./Scripts/build.sh --release  构建 Release（Quick.app / com.ixxxxoooo.quick）
#
# 用了固定的 derivedDataPath，所以产物路径是确定的，
# --run / --path 不需要去猜 Xcode 把东西放哪了。
#
# @author ygw
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

# Debug 渠道产物名是「Quick Dev.app」，Release 才是「Quick.app」
if [[ "$config" == "Debug" ]]; then
    readonly APP_PRODUCT="Quick Dev.app"
else
    readonly APP_PRODUCT="Quick.app"
fi
readonly APP="$DERIVED_DATA/Build/Products/$config/$APP_PRODUCT"

if [[ "$print_path_only" == true ]]; then
    echo "$APP"
    exit 0
fi

# 工程由 project.yml 生成；缺失时先生成，避免「改了 project.yml 忘了 generate」。
if [[ ! -d Quick.xcodeproj ]]; then
    echo "==> Quick.xcodeproj 不存在，正在生成"
    xcodegen generate
fi

# 自签名证书缺失时：本机构建退回 ad-hoc（开发尚可，但 TCC 身份每次会变）；
# 正式 DMG 由 build-dmg.sh 守门，不允许悄悄 ad-hoc。
#
# 不能用 `grep -q`：它在命中后立刻关掉管道，`security` 随即收到 SIGPIPE，
# 在 `set -o pipefail` 下整条管道被判为失败 —— 有证书也会落进 ad-hoc 分支。
SIGN_OVERRIDES=()
if ! security find-identity -p codesigning 2>/dev/null | grep '"Quick"' >/dev/null; then
    echo "    ⚠️  找不到自签名证书「Quick」，本次用 ad-hoc 签名"
    echo "        正式发布前请跑：bash Scripts/generate-signing-cert.sh"
    SIGN_OVERRIDES+=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Automatic)
fi

echo "==> 构建 Quick（${config} → ${APP_PRODUCT}）"
# 空数组在 set -u 下不能 "${arr[@]}"，有覆盖才展开。
xcodebuild_args=(
    -project Quick.xcodeproj
    -scheme Quick
    -configuration "$config"
    -destination 'platform=macOS'
    -derivedDataPath "$DERIVED_DATA"
)
if ((${#SIGN_OVERRIDES[@]})); then
    xcodebuild_args+=("${SIGN_OVERRIDES[@]}")
fi
xcodebuild "${xcodebuild_args[@]}" \
    build 2>&1 | grep -E 'error:|warning:.*\.swift|BUILD (SUCCEEDED|FAILED)' || true

if [[ ! -d "$APP" ]]; then
    echo "✗ 构建失败：找不到 $APP" >&2
    exit 1
fi

echo "    ✓ $APP"

if [[ "$run_after" == true ]]; then
    # 日常改完请优先用 ./Scripts/restart.sh（等进程退出更稳，支持 --show）。
    echo "==> 启动（等价于 ./Scripts/restart.sh --no-build，但不等待进程退出）"
    pkill -f 'Quick Dev.app/Contents/MacOS/Quick Dev' 2>/dev/null || true
    pkill -f 'Quick.app/Contents/MacOS/Quick' 2>/dev/null || true
    sleep 0.5
    open -n "$APP"
    echo "    ✓ 已启动。日志：./Scripts/logs.sh$([ "$config" = Debug ] && echo ' --dev')"
fi
