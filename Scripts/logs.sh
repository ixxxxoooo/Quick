#!/usr/bin/env bash
#
# Quick — 查看统一日志系统里本应用的日志。
#
#   ./Scripts/logs.sh                 实时跟踪正式版（com.ixxxxoooo.quick，含 debug）
#   ./Scripts/logs.sh --dev           实时跟踪 Debug 频道（com.ixxxxoooo.quick.dev）
#   ./Scripts/logs.sh --errors        只看近 1 小时的 error / fault
#   ./Scripts/logs.sh --saved         只看已落盘的历史（notice 及以上）
#   ./Scripts/logs.sh -c palette      只看某个 category
#
# 为什么默认是「实时跟踪」而不是「查历史」：
# os.Logger 的 .debug 与 .info 级别不写入磁盘，`log show` 事后读不到；
# 只有 notice 及以上才会持久化。排查刚发生的事用实时跟踪；查过去只能查到
# notice / warning / error / fault。分级规则见 docs/logging.md
#
# @author ygw
set -euo pipefail

# 用户 shell 里可能有同名函数或别名覆盖 log，所以走绝对路径。
readonly LOG_BIN=/usr/bin/log

SUBSYSTEM="com.ixxxxoooo.quick"
category=""
mode="stream"

while [[ $# -gt 0 ]]; do
    case "$1" in
    --dev)
        SUBSYSTEM="com.ixxxxoooo.quick.dev"
        shift
        ;;
    --errors)
        mode="errors"
        shift
        ;;
    --saved)
        mode="saved"
        shift
        ;;
    -c | --category)
        category="$2"
        shift 2
        ;;
    -h | --help)
        sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        echo "未知参数: $1" >&2
        echo "用法: $0 [--dev] [--errors|--saved] [-c <category>]" >&2
        exit 2
        ;;
    esac
done

predicate="subsystem == \"${SUBSYSTEM}\""
if [[ -n "$category" ]]; then
    predicate="${predicate} AND category == \"${category}\""
fi

case "$mode" in
stream)
    echo "==> 实时跟踪（subsystem=${SUBSYSTEM}，含 debug；Ctrl-C 退出）"
    echo "    提示：面板显隐、聚合搜索等高频日志在 debug/info 级别，只有这里能看到。"
    exec "$LOG_BIN" stream --predicate "$predicate" --level debug --style compact
    ;;
errors)
    # messageType 只有 default/info/debug/error/fault，没有 warning，
    # 所以能按级别过滤的就是 error（16）与 fault（17）。
    echo "==> 近 1 小时的 error / fault（subsystem=${SUBSYSTEM}）"
    exec "$LOG_BIN" show --predicate "$predicate AND messageType >= 16" --last 1h --style compact
    ;;
saved)
    echo "==> 已落盘的历史（notice 及以上，近 1 小时）"
    echo "    注意：debug / info 不落盘，这里看不到。"
    exec "$LOG_BIN" show --predicate "$predicate" --last 1h --style compact
    ;;
esac
