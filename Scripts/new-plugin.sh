#!/usr/bin/env bash
#
# Quick — 生成一个新的功能插件骨架。
#
#   ./Scripts/new-plugin.sh PluginFoo
#   ./Scripts/new-plugin.sh Foo              （等价，会自动补 Plugin 前缀）
#   ./Scripts/new-plugin.sh PluginFoo --with-platform   需要 QuickPlatform
#
# 生成的内容遵循 AGENTS.md 的插件契约。生成后仍需手动做三件事（脚本会打印提醒）：
#   1. 在 Quick/AppCore.swift#registerPlugins() 注册
#   2. 在 project.yml 加 packages + dependencies 两处，然后 xcodegen generate
#   3. 在 docs/features/<id>.md 写下这个插件的不变量
#
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
readonly ROOT="$PWD"

# ---------------------------------------------------------------------------
# 解析参数
# ---------------------------------------------------------------------------
with_platform=false
name=""

for arg in "$@"; do
    case "$arg" in
    --with-platform) with_platform=true ;;
    -*) echo "未知参数: $arg" >&2; exit 2 ;;
    *)
        if [[ -n "$name" ]]; then
            echo "错误：只能指定一个插件名" >&2
            exit 2
        fi
        name="$arg"
        ;;
    esac
done

if [[ -z "$name" ]]; then
    echo "用法: $0 Plugin<Name> [--with-platform]" >&2
    exit 2
fi

# 允许写 Foo 或 PluginFoo，统一成 PluginFoo
[[ "$name" == Plugin* ]] || name="Plugin${name}"

# 去掉 Plugin 前缀后是插件的「类型前缀」，首字母小写就是插件 id
prefix="${name#Plugin}"

if [[ -z "$prefix" || ! "$prefix" =~ ^[A-Z][A-Za-z0-9]*$ ]]; then
    echo "错误：插件名必须是 Plugin 加一个大驼峰单词，例如 PluginFoo（收到 ${name}）" >&2
    exit 2
fi

# plugin id：前缀首字母小写。launcher / clipboard / systemMonitor
plugin_id="$(echo "${prefix:0:1}" | tr '[:upper:]' '[:lower:]')${prefix:1}"

readonly PKG_DIR="$ROOT/Packages/$name"
readonly TEST_DIR="$PKG_DIR/Tests/${name}Tests"
readonly SRC_DIR="$PKG_DIR/Sources/$name"

if [[ -d "$PKG_DIR" ]]; then
    echo "错误：$PKG_DIR 已存在，不覆盖" >&2
    exit 1
fi

echo "==> 生成插件 $name"
echo "    类型前缀 : $prefix"
echo "    插件 id  : $plugin_id"

# ---------------------------------------------------------------------------
# 目录
# ---------------------------------------------------------------------------
mkdir -p "$SRC_DIR/Model" "$SRC_DIR/Service" "$SRC_DIR/UI" "$SRC_DIR/Settings" "$TEST_DIR"

# ---------------------------------------------------------------------------
# 依赖：默认 QuickCore + QuickUI；需要系统能力时再加 QuickPlatform
# ---------------------------------------------------------------------------
if [[ "$with_platform" == true ]]; then
    deps_decl='        .package(path: "../QuickCore"),
        .package(path: "../QuickUI"),
        .package(path: "../QuickPlatform")'
    deps_list='"QuickCore", "QuickUI", "QuickPlatform"'
else
    deps_decl='        .package(path: "../QuickCore"),
        .package(path: "../QuickUI")'
    deps_list='"QuickCore", "QuickUI"'
fi

cat >"$PKG_DIR/Package.swift" <<EOF
// swift-tools-version: 6.2
// @author ygw
import PackageDescription

let package = Package(
    name: "$name",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "$name", targets: ["$name"])
    ],
    dependencies: [
$deps_decl
    ],
    targets: [
        .target(
            name: "$name",
            dependencies: [$deps_list]
        ),
        .testTarget(name: "${name}Tests", dependencies: ["$name"])
    ]
)
EOF

# ---------------------------------------------------------------------------
# 插件类
# ---------------------------------------------------------------------------
cat >"$SRC_DIR/${prefix}Plugin.swift" <<EOF
// ${prefix}Plugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// $prefix 功能插件
///
/// TODO: 一句话说明这个插件做什么。
/// 不变量与内部约定见 docs/features/$plugin_id.md
@MainActor
public final class ${prefix}Plugin: QuickPlugin {

    // MARK: - QuickPlugin 元信息

    /// 全局唯一主键：事件路由与设置存储都用它。
    /// 一旦发布就不能再改 —— 改了等于用户设置丢失。
    public static let id = "$plugin_id"

    public static let name = "$prefix"

    public static let icon = "square.grid.2x2"

    // MARK: - 状态

    /// 插件自己的日志通道。分类用插件 id，便于按插件过滤。
    private let log = QuickLog.plugin(${prefix}Plugin.id)

    /// 插件是否启用。持久化到 SettingsKey.pluginEnabled(id) 的键上。
    public var isEnabled: Bool = true

    // MARK: - 生命周期

    public init() {}

    /// 应用启动或插件被启用时调用。这里预热缓存、启动监听。
    public func activate() {
        log.info("插件已激活")
        // TODO: 加载持久化数据、启动监听
    }

    /// 应用退出或插件被禁用时调用。**必须有落盘**，否则运行时状态会丢。
    public func deactivate() {
        log.info("插件已停用")
        // TODO: 保存运行时状态
    }

    // MARK: - 搜索

    /// 纯查询：不要在这里启停插件、写盘、发网络请求。
    /// 它会在每次按键（防抖后）被调用。
    public func searchItems(query: String) async -> [SearchableItem] {
        guard !query.isEmpty else { return [] }
        log.debug("搜索，\(query.count) 字符")

        // TODO: 返回匹配结果。relevance 约定见 docs/architecture.md：
        // 完全匹配 1.0 / 前缀 0.9 / 模糊 0.5~0.8 / 工具入口 <0.3
        return []
    }

    // MARK: - 视图

    /// 面板内的插件主视图。不要在这里设外层尺寸与背景 —— 面板外壳负责。
    public func makeView() -> AnyView {
        AnyView(${prefix}View(plugin: self))
    }
}
EOF

cat >"$SRC_DIR/UI/${prefix}View.swift" <<EOF
// ${prefix}View.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickUI
import SwiftUI

/// $prefix 插件在面板内的主视图。
///
/// 只管内容区：外层尺寸、圆角、背景由面板外壳负责。
/// 所有数值取自 DesignTokens，不写裸字面量（见 docs/ui.md）。
struct ${prefix}View: View {

    let plugin: ${prefix}Plugin

    @State private var items: [SearchableItem] = []

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // TODO: 首次出现时准备数据
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: DesignTokens.Spacing.xxs) {
                ForEach(items) { item in
                    Text(item.title)
                        .font(DesignTokens.Typography.rowTitle)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        .padding(.vertical, DesignTokens.Spacing.md)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
        }
    }

    /// 空状态必须有：一个图标 + 一句说明。不要留一片空白。
    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: ${prefix}Plugin.icon)
                .font(DesignTokens.Typography.emptyStateIcon)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text("暂无内容")
                .font(DesignTokens.Typography.rowTitle)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
    }
}
EOF

# ---------------------------------------------------------------------------
# 测试（必须非空 —— 空的 testTarget 会让 swift test 直接失败）
# ---------------------------------------------------------------------------
cat >"$TEST_DIR/${prefix}PluginTests.swift" <<EOF
// ${prefix}PluginTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Testing

@testable import $name

@Suite("$prefix 插件")
@MainActor
struct ${prefix}PluginTests {

    @Test("插件 id 符合约定")
    func identifierConvention() {
        // id 是事件路由与设置存储的主键，必须是稳定的 lowerCamelCase
        #expect(${prefix}Plugin.id == "$plugin_id")
        #expect(!${prefix}Plugin.name.isEmpty)
        #expect(!${prefix}Plugin.icon.isEmpty)
    }

    @Test("空查询不返回结果")
    func emptyQueryYieldsNothing() async {
        let plugin = ${prefix}Plugin()
        let results = await plugin.searchItems(query: "")
        #expect(results.isEmpty, "空查询应交由面板展示默认内容，插件本身不应返回结果")
    }

    @Test("启停是幂等的")
    func activationIsIdempotent() {
        // 插件可能被反复启停，activate/deactivate 必须可以重复调用而不出错
        let plugin = ${prefix}Plugin()
        plugin.activate()
        plugin.activate()
        plugin.deactivate()
        plugin.deactivate()
    }
}
EOF

# 空目录在 git 里不保留，放一个占位说明
for dir in Model Service Settings; do
    cat >"$SRC_DIR/$dir/.gitkeep" <<EOF
EOF
done

echo
echo "    ✓ 已生成"
echo
echo "==> 还需要手动做三件事："
echo
echo "  1) 在 Quick/AppCore.swift 的 registerPlugins() 里注册"
echo "     plugins.append(${prefix}Plugin())"
echo
echo "  2) 在 project.yml 里加两处，然后 xcodegen generate"
echo "     packages:"
echo "       $name:"
echo "         path: Packages/$name"
echo "     targets.Quick.dependencies:"
echo "       - package: $name"
echo
echo "  3) 在 docs/features/$plugin_id.md 写下这个插件的不变量"
echo
echo "  然后：./Scripts/run-tests.sh $name"
echo
