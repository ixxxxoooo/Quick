#!/usr/bin/env python3
#
# Quick — 检查插件的 triggerWords 是否全局唯一。
#
# 为什么需要它：`matchesAnyTrigger` 是子串匹配，两个插件声明同一个触发词会让
# 同一条查询同时唤醒它们，两批结果一起涌进面板。触发词是字符串空间里的隐式
# 命名空间，编译器看不见，只能靠这个脚本守。
#
# 通用词（「编码」「格式化」这类）应该放在命令的 keywords 里 —— 命令级关键词可以
# 重复，因为 CommandIndex 会按相关度统一排序，不会出现「两个插件各自铺满结果」。
# 参考 URLCodec 的处理：它把「编码 / 解码」让给了 Base64，自己只留带 URL 限定的词。
#
# 触发词有三种写法，都要认：
#   1. 直接字面量数组        static let triggerWords = ["a", "b"]
#   2. 引用另一个类型的常量  static let triggerWords = OCRQuery.triggers
#   3. 常量相加              static let triggerWords = areaKeywords + fullKeywords
#
# 由 ./Scripts/run-tests.sh 调用。
#
# @author ygw

from __future__ import annotations

import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# 插件源码目录下的全部 Swift 文件（含 Model/ Service/ UI/ 子目录）
SOURCE_GLOBS = ("Sources/**/*.swift",)


def literal_list(text: str, name: str) -> list[str] | None:
    """取某个静态常量的字面量数组；找不到或不是字面量时返回 None。"""
    pattern = (
        rf"static\s+(?:nonisolated\s+)?(?:let|var)\s+{re.escape(name)}\s*"
        rf"(?::\s*\[String\])?\s*=\s*\[(.*?)\]"
    )
    match = re.search(pattern, text, re.S)
    if not match:
        return None
    return re.findall(r'"([^"]+)"', match.group(1))


def concat_parts(expression: str) -> list[str]:
    """把 `areaKeywords + fullKeywords` 拆成常量名列表，忽略字面量。"""
    return [p.strip() for p in expression.split("+") if p.strip()]


def resolve_words(package: Path, expression: str, sources: dict[str, str]) -> list[str]:
    """把 triggerWords 的赋值表达式解析成词表。

    `sources` 是「文件名 → 内容」，用于跨文件找常量（如 OCR 的 triggerWords 引用
    Model/OCRQuery.swift 里的 triggers）。
    """
    expression = expression.strip()

    # 形式 1：字面量数组（可能带换行与注释）
    if expression.startswith("["):
        inner = expression.rsplit("]", 1)[0][1:]
        return re.findall(r'"([^"]+)"', inner)

    # 形式 2 / 3：常量引用（可能相加）
    words: list[str] = []
    for part in concat_parts(expression):
        # 取最后一段作为常量名：`OCRQuery.triggers` → `triggers`
        name = part.split(".")[-1]
        if not name.isidentifier():
            continue
        for text in sources.values():
            found = literal_list(text, name)
            if found:
                words.extend(found)
                break
    return words


def main() -> int:
    owners: dict[str, list[str]] = defaultdict(list)
    checked = 0
    unresolved: list[str] = []

    for package in sorted((ROOT / "Packages").glob("Plugin*")):
        sources: dict[str, str] = {}
        for pattern in SOURCE_GLOBS:
            for path in package.glob(pattern):
                sources[str(path)] = path.read_text(encoding="utf-8")

        # triggerWords 只在插件主文件里声明，但它的取值可能引用其它文件
        for path_text, text in sources.items():
            if not path_text.endswith("Plugin.swift"):
                continue
            match = re.search(
                r"static\s+(?:nonisolated\s+)?(?:let|var)\s+triggerWords\s*"
                r"(?::\s*\[String\])?\s*=\s*(.+)",
                text,
            )
            if not match:
                continue

            # 多行字面量：从 `=` 后的第一个 `[` 配对到它的 `]`
            raw = match.group(1).strip()
            if raw.startswith("["):
                start = text.index("[", match.start(1))
                expression = text[start : text.index("]", start) + 1]
            else:
                expression = raw

            words = resolve_words(package, expression, sources)
            if not words:
                # 解析不出来必须报出来：否则冲突会从这里漏过去
                unresolved.append(package.name)
                continue

            checked += 1
            for word in words:
                owners[word].append(package.name)

    if unresolved:
        print(f"✗ 以下插件的 triggerWords 无法解析，冲突检查存在盲区：", file=sys.stderr)
        for name in unresolved:
            print(f"    {name}", file=sys.stderr)
        print("  修复：把触发词写成字面量数组，或引用一个静态字面量常量。", file=sys.stderr)
        return 1

    conflicts = {word: pkgs for word, pkgs in owners.items() if len(pkgs) > 1}

    if conflicts:
        print("✗ 以下触发词被多个插件声明（会让同一条查询唤醒两个插件）：", file=sys.stderr)
        for word, pkgs in sorted(conflicts.items()):
            print(f"    {word!r} → {', '.join(sorted(pkgs))}", file=sys.stderr)
        print(file=sys.stderr)
        print("  修复：只让语义更专一的那个插件保留它，其余插件删掉。", file=sys.stderr)
        print("        通用词改放进 CommandDescriptor.keywords（命令级关键词允许重复）。", file=sys.stderr)
        return 1

    print(f"✓ 触发词全局唯一（检查了 {checked} 个插件，{len(owners)} 个词）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
