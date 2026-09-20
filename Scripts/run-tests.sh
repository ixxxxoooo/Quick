#!/usr/bin/env bash
#
# Quick — 跑测试。这是提交的硬门禁。
#
#   ./Scripts/run-tests.sh                            全部包
#   ./Scripts/run-tests.sh QuickCore PluginCalculator  指定包
#
# 任何一个包失败，整体退出非零 —— pre-commit 钩子依赖这个信号。
#
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
readonly ROOT="$PWD"

# ---------------------------------------------------------------------------
# 决定要跑哪些包
#
# 默认：所有存在测试源码的包。
# 另外会独立检查「声明了 testTarget 但目录里没有测试文件」的包 ——
# 那种情况 swift test 会直接报 "no tests found" 而失败，必须提前抓出来，
# 否则等到有人提交时才发现。
# ---------------------------------------------------------------------------
has_test_sources() {
    local dir="$1/Tests"
    [[ -d "$dir" ]] && [[ -n "$(find "$dir" -name '*.swift' -print -quit 2>/dev/null)" ]]
}

declares_test_target() {
    grep -q '\.testTarget(' "$1/Package.swift" 2>/dev/null
}

if [[ $# -gt 0 ]]; then
    selected=()
    for name in "$@"; do
        if [[ ! -d "Packages/$name" ]]; then
            echo "错误：Packages/$name 不存在" >&2
            exit 2
        fi
        selected+=("Packages/$name")
    done
else
    selected=()
    for pkg in Packages/*/; do
        pkg="${pkg%/}"
        if has_test_sources "$pkg"; then
            selected+=("$pkg")
        fi
    done
fi

if [[ ${#selected[@]} -eq 0 ]]; then
    echo "错误：没有找到任何带测试的包" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 独立检查：声明了测试目标却是空的
# ---------------------------------------------------------------------------
empty_targets=()
for pkg in Packages/*/; do
    pkg="${pkg%/}"
    if declares_test_target "$pkg" && ! has_test_sources "$pkg"; then
        empty_targets+=("$(basename "$pkg")")
    fi
done

if [[ ${#empty_targets[@]} -gt 0 ]]; then
    echo "✗ 以下包声明了 testTarget 但没有任何测试文件：" >&2
    for name in "${empty_targets[@]}"; do
        echo "    - ${name}（swift test 会因 'no tests found' 失败）" >&2
    done
    echo "  修复：在 Packages/<包名>/Tests/<包名>Tests/ 下添加至少一个 .swift 测试文件，" >&2
    echo "        或在 Package.swift 里移除 .testTarget 声明。" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 独立检查：有源码却没有测试的包
#
# 「每个包都要有测试」而不是「想测才测」。系统依赖重不等于没有可测的东西 ——
# 把系统调用挤到边缘、把纯计算剥到 Model/ 再测，见 docs/testing.md。
# 这条检查的意义是让缺口在提交时暴露，而不是等到有人想起来去数。
# ---------------------------------------------------------------------------
untested=()
for pkg in Packages/*/; do
    pkg="${pkg%/}"
    has_sources=$([[ -n "$(find "$pkg/Sources" -name '*.swift' -print -quit 2>/dev/null)" ]] && echo yes || echo no)
    if [[ "$has_sources" == yes ]] && ! has_test_sources "$pkg"; then
        untested+=("$(basename "$pkg")")
    fi
done

if [[ ${#untested[@]} -gt 0 ]]; then
    echo "✗ 以下包有源码但没有任何测试：" >&2
    for name in "${untested[@]}"; do
        echo "    - ${name}" >&2
    done
    echo "  修复：加一个测试目标并写至少一个测真实行为的用例。" >&2
    echo "        纯逻辑抽到 Sources/<包名>/Model/（Foundation-only）后就能独立测；" >&2
    echo "        系统依赖的部分测「我们对返回值的处理」，见 docs/testing.md。" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 逐包跑
# ---------------------------------------------------------------------------
echo "==> 测试 ${#selected[@]} 个包"
echo

failures=()
passed=0

for pkg in "${selected[@]}"; do
    name="$(basename "$pkg")"
    printf '%-24s' "$name"

    log_file="$(mktemp)"
    if (cd "$pkg" && swift test >"$log_file" 2>&1); then
        # Swift Testing 的输出形如：✔ Test run with 6 tests in 2 suites passed after 0.001 seconds.
        summary=$(grep -E 'Test run with' "$log_file" | tail -1 | sed 's/^[^T]*//' || true)
        # 也兼容 XCTest 风格的汇总行
        if [[ -z "$summary" ]]; then
            summary=$(grep -E 'Executed [0-9]+ tests?' "$log_file" | tail -1 | xargs || true)
        fi
        echo "✓  ${summary:-通过}"
        passed=$((passed + 1))
    else
        echo "✗  失败"
        failures+=("$name")
        echo
        echo "---- $name 输出（末尾 40 行）----"
        tail -40 "$log_file"
        echo "--------------------------------"
        echo
    fi

    rm -f "$log_file"
done

echo
if [[ ${#failures[@]} -gt 0 ]]; then
    echo "✗ ${#failures[@]} 个包失败：${failures[*]}" >&2
    exit 1
fi

echo "✓ 全部通过（$passed 个包）"
