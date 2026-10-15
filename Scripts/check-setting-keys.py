#!/usr/bin/env python3
"""检查「设置键」都有真正的读取方 —— 防止出现「开关能点、但什么都不会发生」的死设置。

背景：`PluginSettingKey` / `SettingsKey` 里每个键都对应设置页上的一个控件。编译器只保证键被
**定义**了，不保证它被**使用**了；设置页自己的 `@AppStorage` 也只是在读写同一份存储，对功能
毫无影响。一个键如果除了设置页之外没有任何地方引用，那它就是死的（曾经一次出现过 6 个）。

判定：键被「设置页之外」的非测试源码引用 —— 设置页指路径含 `/Settings/` 的文件。
定义键的两个文件本身也不算。

有意保留的例外写在 `ALLOWED_UNREAD` 里，并且必须写明理由。

由 ./Scripts/run-tests.sh 调用。

@author ygw
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KEY_FILES = [
    ROOT / "Packages/QuickCore/Sources/QuickCore/Models/PluginSettingKey.swift",
    ROOT / "Packages/QuickCore/Sources/QuickCore/Models/SettingsKey.swift",
]

# 超级面板的键定义在它自己的偏好类型里（与读取逻辑同文件）。
# 要扫它的键；但读取方恰恰也在这个文件里（`mouseConfiguration` 等），所以它**不**从语料里排除 ——
# 定义行是 `static let x = "superPanel.x"`，不会被 `Key.x` 的引用模式误判成读取。
EXTRA_KEY_FILES = [
    ROOT / "Packages/QuickUI/Sources/QuickUI/SuperPanel/Model/SuperPanelPreferences.swift",
]

# 引用形式 → 说明。键名用「引用文本」表示，例如 `SettingsKey.foo`
ALLOWED_UNREAD: dict[str, str] = {}

LET = re.compile(r'^\s*(?:public\s+)?static\s+let\s+(\w+)\s*=\s*"')
ENUM = re.compile(r"^\s*(?:public\s+)?enum\s+(\w+)")


def collect_keys() -> list[tuple[str, Path, int]]:
    """返回 (引用文本, 定义文件, 行号)。嵌套枚举按 `PluginSettingKey.Foo.bar` 展开。"""
    keys: list[tuple[str, Path, int]] = []
    for path in KEY_FILES + EXTRA_KEY_FILES:
        stack: list[tuple[str, int]] = []  # (枚举名, 进入时的缩进)
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            indent = len(line) - len(line.lstrip())
            while stack and indent <= stack[-1][1] and line.strip().startswith("}"):
                stack.pop()
            enum = ENUM.match(line)
            if enum:
                stack.append((enum.group(1), indent))
                continue
            let = LET.match(line)
            if let and stack:
                keys.append((".".join([name for name, _ in stack] + [let.group(1)]), path, number))
    return keys


def source_files() -> list[Path]:
    files = list((ROOT / "Packages").glob("*/Sources/**/*.swift"))
    files += list((ROOT / "Quick").glob("**/*.swift"))
    result = []
    for path in files:
        posix = path.as_posix()
        if path in KEY_FILES or "/Settings/" in posix or posix.endswith("SettingsView.swift"):
            continue
        result.append(path)
    return result


def main() -> int:
    keys = collect_keys()
    if not keys:
        print("✗ 没有解析到任何设置键 —— 解析规则可能已经失效，请检查 check-setting-keys.py")
        return 1

    corpus = "\n".join(path.read_text(encoding="utf-8") for path in source_files())

    dead = []
    for reference, path, number in keys:
        if reference in ALLOWED_UNREAD:
            continue
        # `SettingsKey.foo` 或 `PluginSettingKey.Foo.bar`；允许类型别名之外的前缀
        if re.search(rf"(?<![\w.]){re.escape(reference)}\b", corpus):
            continue
        # 嵌套在别名里的写法（如 `Key.bar`、`.bar`）无法静态判断：退而求其次按最后一段在
        # 同枚举名下查找
        parts = reference.split(".")
        if len(parts) >= 2 and re.search(
            rf"\b{re.escape(parts[-2])}\.{re.escape(parts[-1])}\b", corpus
        ):
            continue
        dead.append(f"{path.relative_to(ROOT)}:{number}: {reference}")

    if dead:
        print("✗ 这些设置键除了设置页之外没有任何读取方（开关是死的）：")
        for item in dead:
            print("  " + item)
        print("  → 接上真实读取，或删掉这个键与它在设置页上的控件。")
        return 1

    print(f"✓ {len(keys)} 个设置键都有读取方")
    return 0


if __name__ == "__main__":
    sys.exit(main())
