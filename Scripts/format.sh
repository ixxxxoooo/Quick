#!/usr/bin/env bash
#
# Quick — 就地格式化 Swift 源码。
#
# 只用 xcrun swift-format（随 Xcode 提供，不需要额外安装）。
# 排版由工具决定，不要在评审里争论换行位置。
#
#   ./Scripts/format.sh             格式化全部
#   ./Scripts/format.sh --changed   只格式化本次暂存的文件
#   ./Scripts/format.sh --check     只检查，不修改（退出码表示是否干净）
#
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

readonly SOURCE_DIRS=(Quick Packages)
readonly MODE="${1:-all}"

if ! xcrun --find swift-format >/dev/null 2>&1; then
    echo "错误：找不到 swift-format。需要 Xcode 26+ 工具链。" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 收集目标文件：排除 SwiftPM 构建产物
# ---------------------------------------------------------------------------
collect_all() {
    find "${SOURCE_DIRS[@]}" -name '*.swift' -not -path '*/.build/*' -not -path '*/DerivedData/*'
}

# 只处理暂存区里「新增或修改」的 .swift 文件。
# 这是一种棘轮策略：历史文件不强制一次改完，但只要你碰了它，它就得是干净的。
collect_changed() {
    git diff --cached --name-only --diff-filter=ACM -- '*.swift' || true
}

case "$MODE" in
--check)
    echo "==> 检查排版（全部文件）"
    if xcrun swift-format lint --strict -r "${SOURCE_DIRS[@]}"; then
        echo "    ✓ 排版干净"
    else
        echo "    ✗ 排版有问题，运行 ./Scripts/format.sh 修复" >&2
        exit 1
    fi
    ;;
--changed)
    files=$(collect_changed)
    if [[ -z "$files" ]]; then
        echo "==> 没有暂存待检查的 Swift 文件，跳过"
        exit 0
    fi
    echo "==> 检查暂存文件的排版"
    # shellcheck disable=SC2086
    if xcrun swift-format lint --strict $files; then
        echo "    ✓ 暂存文件排版干净"
    else
        echo "    ✗ 暂存文件排版有问题，运行 ./Scripts/format.sh --changed 修复" >&2
        exit 1
    fi
    ;;
all)
    echo "==> 格式化全部 Swift 文件"
    # shellcheck disable=SC2046
    xcrun swift-format format --in-place $(collect_all)
    echo "    ✓ 完成"
    ;;
*)
    echo "用法: $0 [--check|--changed]" >&2
    exit 2
    ;;
esac
