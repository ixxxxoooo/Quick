#!/usr/bin/env python3
#
# Quick — 检查「插件声明」与「真实注册表」是否一致。
#
# 为什么需要它：插件被下线后，包目录、project.yml、超级面板目录、导航动作里的字符串
# 引用都可能被遗忘 —— 编译器看不见这些字符串，运行时表现为「点了没反应 / 面板空白」。
# 这条检查把以下三件事变成提交门禁：
#
#   1. Packages/Plugin* 目录、project.yml 的 packages 声明、AppCore 的注册表三者完全一致；
#   2. 超级面板「工作台」目录（SuperPanelQuickTool.swift）里每个 pluginID 都真实存在；
#   3. 超级面板上下文动作里的 `navigate("...")` 目标都真实存在。
#
# 由 ./Scripts/run-tests.sh 调用。
#
# @author ygw

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACKAGES = ROOT / "Packages"


def plugin_packages() -> dict[str, str]:
    """包目录名 → 插件 id。只认带 Package.swift 的 Plugin* 目录。"""
    result: dict[str, str] = {}
    for pkg in sorted(PACKAGES.glob("Plugin*/")):
        if not (pkg / "Package.swift").exists():
            continue
        plugin_id = None
        for source in (pkg / "Sources").rglob("*Plugin.swift"):
            match = re.search(
                r'static\s+(?:nonisolated\s+)?let\s+id\s*=\s*"([^"]+)"', source.read_text()
            )
            if match:
                plugin_id = match.group(1)
                break
        result[pkg.name] = plugin_id or ""
    return result


def main() -> int:
    problems: list[str] = []
    packages = plugin_packages()

    # 1. 三方一致
    project_yml = (ROOT / "project.yml").read_text()
    declared = set(re.findall(r"^\s*-\s*package:\s*(Plugin\w+)\s*$", project_yml, re.M))
    app_core = (ROOT / "Quick" / "AppCore.swift").read_text()
    registered_types = set(re.findall(r"\(\s*(\w+Plugin)\.self", app_core))

    for name, plugin_id in packages.items():
        if not plugin_id:
            problems.append(f"{name}：找不到 `static let id`，无法确定插件 id")
        if name not in declared:
            problems.append(f"{name}：目录存在，但 project.yml 的 Quick target 没有依赖它")
        expected_type = name.removeprefix("Plugin") + "Plugin"
        if expected_type not in registered_types:
            problems.append(f"{name}：目录存在，但 AppCore.registerPlugins 没有注册 {expected_type}")
    for name in sorted(declared - set(packages)):
        problems.append(f"{name}：project.yml 依赖了它，但 Packages/ 下没有这个包")

    known_ids = {pid for pid in packages.values() if pid}

    # 2. 工作台目录
    catalog = (
        ROOT / "Packages/QuickUI/Sources/QuickUI/SuperPanel/Model/SuperPanelQuickTool.swift"
    ).read_text()
    for plugin_id in re.findall(r'pluginID:\s*"([^"]+)"', catalog):
        if plugin_id not in known_ids:
            problems.append(f"超级面板工作台目录引用了不存在的插件 id：{plugin_id}")

    # 3. 上下文动作的导航目标
    builder = (
        ROOT / "Packages/QuickUI/Sources/QuickUI/SuperPanel/Service/SuperPanelContextBuilder.swift"
    ).read_text()
    for plugin_id in re.findall(r'navigate\("([^"]+)"\)', builder):
        if plugin_id not in known_ids:
            problems.append(f"超级面板动作导航到不存在的插件 id：{plugin_id}")

    if problems:
        print("✗ 插件声明与注册表不一致：", file=sys.stderr)
        for item in problems:
            print(f"    - {item}", file=sys.stderr)
        return 1

    print(f"✓ 插件声明一致（{len(packages)} 个包，project.yml / AppCore / 超级面板目录互相对得上）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
