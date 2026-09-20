#!/usr/bin/env bash
#
# Quick — 首次克隆后初始化本机开发环境。
#
# 目前只做一件事，但它是质量门禁的前提：启用版本控制的 git 钩子。
# 不执行这一步，pre-commit 的测试门禁就是不存在的。
#
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
readonly REPO_ROOT="$PWD"

echo "==> Quick 环境初始化"

# ---------------------------------------------------------------------------
# 1. git 钩子
#
# 钩子放在 .githooks/ 而不是 .git/hooks/，这样它能被版本控制、跟着仓库走。
# core.hooksPath 让 git 去那里找钩子。
# ---------------------------------------------------------------------------
if [[ ! -d .githooks ]]; then
    echo "错误：找不到 .githooks/ 目录" >&2
    exit 1
fi

chmod +x .githooks/* 2>/dev/null || true
chmod +x Scripts/*.sh 2>/dev/null || true

git config core.hooksPath .githooks
echo "    ✓ git 钩子已启用（core.hooksPath = .githooks）"

# ---------------------------------------------------------------------------
# 2. 工具检查（缺了不阻断，只提示）
# ---------------------------------------------------------------------------
echo
echo "==> 工具检查"

check() {
    local name="$1" hint="$2"
    if command -v "$name" >/dev/null 2>&1; then
        echo "    ✓ $name"
    else
        echo "    ✗ $name 未安装 — $hint"
    fi
}

check xcodegen "brew install xcodegen（生成 Quick.xcodeproj 必需）"
check swiftlint "brew install swiftlint（语义检查；缺失时 lint.sh 会跳过）"
check jq "brew install jq（日志脚本用到）"

if xcrun --find swift-format >/dev/null 2>&1; then
    echo "    ✓ swift-format（随 Xcode 提供）"
else
    echo "    ✗ swift-format 不可用 — 需要 Xcode 26+ 工具链" >&2
fi

# ---------------------------------------------------------------------------
# 3. 工程文件
# ---------------------------------------------------------------------------
echo
if [[ ! -d Quick.xcodeproj ]]; then
    echo "==> Quick.xcodeproj 不存在，正在生成"
    xcodegen generate
fi

echo
echo "==> 完成。下一步："
echo "    ./Scripts/run-tests.sh     # 确认基线是绿的"
echo "    ./Scripts/build.sh --run   # 构建并启动"
echo
echo "提示：提交前钩子会自动跑测试；规则见 AGENTS.md"
