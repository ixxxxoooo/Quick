#!/usr/bin/env python3
"""检查视图里的裸设计字面量（间距 / 尺寸 / 圆角 / 不透明度 / 字号 / 颜色）。

规则来自 docs/ui.md §1：UI 数值只来自 `DesignTokens`。

- 只扫 `Packages/*/Sources/**/*.swift`，跳过 `DesignTokens.swift` 与 `Model/`（数据而非视图）。
- 值为 0 的不算（`spacing: 0`、`.frame(width: 0)` 是「没有」，不是设计数值）。
- 确有正当理由的行，行尾加 `// ui-literal-ok: <理由>` 放行。
- 有命中则退出码为 1，被 `run-tests.sh` 当作一道门禁。

@author ygw
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NUM = r"(?:[1-9]\d*(?:\.\d+)?|0\.\d*[1-9]\d*)"

PATTERNS = [
    (re.compile(rf"\.padding\((?:\.\w+,\s*)?{NUM}\)"), "padding 字面量"),
    (re.compile(rf"\.frame\((?:[^()]*?,\s*)?(?:width|height|minWidth|maxWidth|minHeight|maxHeight|idealWidth|idealHeight):\s*{NUM}"), "frame 尺寸字面量"),
    (re.compile(rf"cornerRadius:\s*{NUM}"), "圆角字面量"),
    (re.compile(rf"\.font\(\.system\(size:\s*{NUM}"), "字号字面量"),
    (re.compile(r"Color\(\s*(?:red|white|hue):"), "颜色字面量"),
    (re.compile(rf"\.opacity\({NUM}\)"), "不透明度字面量"),
    (re.compile(rf"(?:VStack|HStack|ZStack|LazyVStack|LazyHStack|LazyVGrid|LazyHGrid|safeAreaInset)\([^()\n]*?spacing:\s*{NUM}"), "栈间距字面量"),
    (re.compile(rf"\.offset\((?:x|y):\s*-?{NUM}"), "偏移字面量"),
    (re.compile(rf"lineWidth:\s*{NUM}"), "线宽字面量"),
    (re.compile(rf"\.(?:easeIn|easeOut|easeInOut|linear)\(duration:\s*{NUM}"), "动画时长字面量"),
    (re.compile(rf"\.shadow\([^\n]*?radius:\s*{NUM}"), "阴影字面量"),
]

SKIP_NAMES = {"DesignTokens.swift"}


def main() -> int:
    hits: list[str] = []
    for path in sorted((ROOT / "Packages").glob("*/Sources/**/*.swift")):
        if path.name in SKIP_NAMES or "/Model/" in path.as_posix():
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            stripped = line.strip()
            if stripped.startswith("//") or "ui-literal-ok" in line:
                continue
            for pattern, label in PATTERNS:
                if pattern.search(line):
                    rel = path.relative_to(ROOT)
                    hits.append(f"{rel}:{number}: {label}: {stripped[:100]}")
                    break
    if hits:
        print("✗ 视图里有裸设计字面量（改用 DesignTokens，或在行尾加 `// ui-literal-ok: 理由`）：")
        for hit in hits:
            print("  " + hit)
        return 1
    print("✓ 视图里没有裸设计字面量")
    return 0


if __name__ == "__main__":
    sys.exit(main())
