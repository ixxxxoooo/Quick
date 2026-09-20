#!/usr/bin/env bash
#
# Quick — 质量检查。
#
#   ./Scripts/lint.sh             全量：排版 + 语义
#   ./Scripts/lint.sh --changed   只检查本次暂存的文件（pre-commit 用）
#
# 分工：
#   swift-format（Xcode 自带）→ 排版     —— 必跑
#   swiftlint（需自行安装）   → 语义     —— 装了才跑，没装明确报告跳过
#
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

readonly SOURCE_DIRS=(Quick Packages)
readonly MODE="${1:-all}"
failed=0

# ---------------------------------------------------------------------------
# 1. 排版：swift-format
# ---------------------------------------------------------------------------
if ! xcrun --find swift-format >/dev/null 2>&1; then
    echo "错误：找不到 swift-format。需要 Xcode 26+ 工具链。" >&2
    exit 1
fi

if [[ "$MODE" == "--changed" ]]; then
    staged=$(git diff --cached --name-only --diff-filter=ACM -- '*.swift' || true)
    if [[ -z "$staged" ]]; then
        echo "==> 排版（staged）：无 Swift 文件改动，跳过"
    else
        echo "==> 排版（staged）"
        # shellcheck disable=SC2086
        if xcrun swift-format lint --strict $staged; then
            echo "    ✓ 干净"
        else
            echo "    ✗ 排版有问题 —— 运行 ./Scripts/format.sh --changed 修复" >&2
            failed=1
        fi
    fi
else
    echo "==> 排版（全量）"
    if xcrun swift-format lint --strict -r "${SOURCE_DIRS[@]}"; then
        echo "    ✓ 干净"
    else
        echo "    ✗ 排版有问题 —— 运行 ./Scripts/format.sh 修复" >&2
        failed=1
    fi
fi

# ---------------------------------------------------------------------------
# 2. 语义：SwiftLint（可选依赖）
#
# 没装就跳过并说明，而不是假装通过 —— 一个静默跳过的门禁比没有门禁更危险。
# ---------------------------------------------------------------------------
echo
if command -v swiftlint >/dev/null 2>&1; then
    echo "==> SwiftLint"
    if swiftlint lint --strict --quiet; then
        echo "    ✓ 干净"
    else
        echo "    ✗ SwiftLint 发现问题" >&2
        failed=1
    fi
else
    echo "==> SwiftLint：未安装，已跳过"
    echo "    （安装：brew install swiftlint；配置见 .swiftlint.yml）"
fi

exit "$failed"
