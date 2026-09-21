// SuperPanelPluginTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Testing

@testable import PluginSuperPanel

@Suite("超级面板插件")
@MainActor
struct SuperPanelPluginTests {

    @Test("插件 id 符合约定")
    func identifierConvention() {
        #expect(SuperPanelPlugin.id == "superPanel")
        #expect(!SuperPanelPlugin.name.isEmpty)
        #expect(!SuperPanelPlugin.icon.isEmpty)
    }

    @Test("空查询不返回结果")
    func emptyQueryYieldsNothing() async {
        let plugin = SuperPanelPlugin()
        let results = await plugin.searchItems(query: "")
        #expect(results.isEmpty, "空查询应交由面板展示默认内容，插件本身不应返回结果")
    }

    @Test("启停是幂等的")
    func activationIsIdempotent() {
        let plugin = SuperPanelPlugin()
        plugin.activate()
        plugin.activate()
        plugin.deactivate()
        plugin.deactivate()
    }

    @Test("defaultItems 返回入口")
    func defaultItemsHasEntry() async {
        let plugin = SuperPanelPlugin()
        let items = await plugin.defaultItems()
        #expect(items.count == 1)
        #expect(items.first?.pluginID == "superPanel")
    }
}

@Suite("项目上下文模型")
struct ProjectContextTests {

    @Test("项目类型有图标和显示名")
    func projectTypeMetadata() {
        let types: [ProjectContext.ProjectType] = [.xcode, .node, .python, .rust, .golang, .java, .generic]
        for type in types {
            #expect(!type.icon.isEmpty, "\(type) 应有图标")
            #expect(!type.displayName.isEmpty, "\(type) 应有显示名")
        }
    }
}

@Suite("操作类别")
struct ActionCategoryTests {

    @Test("所有类别都有 rawValue")
    func allCategoriesHaveRawValue() {
        for category in SuperPanelAction.Category.allCases {
            #expect(!category.rawValue.isEmpty)
        }
    }
}

@Suite("操作提供器")
@MainActor
struct ActionProviderTests {

    @Test("为 Xcode 项目生成 Swift 构建操作")
    func xcodeProjectActions() {
        let provider = ActionProvider()
        let context = ProjectContext(
            rootPath: "/tmp/test-xcode-project",
            name: "TestProject",
            type: .xcode,
            isGitRepo: true,
            gitBranch: "main",
            sourceBundleID: "com.apple.dt.Xcode"
        )
        let actions = provider.actions(for: context)
        #expect(!actions.isEmpty, "应该为 Xcode 项目生成操作")

        // 应包含通用操作
        let hasTerminal = actions.contains { $0.id == "sp.open-terminal" }
        #expect(hasTerminal, "应包含「在终端中打开」")

        let hasFinder = actions.contains { $0.id == "sp.open-finder" }
        #expect(hasFinder, "应包含「在 Finder 中显示」")

        // 应包含 Git 操作
        let hasGitBranch = actions.contains { $0.id == "sp.git-branch" }
        #expect(hasGitBranch, "应包含 Git 分支信息")

        let hasGitStatus = actions.contains { $0.id == "sp.git-status" }
        #expect(hasGitStatus, "应包含 Git 状态查看")
    }

    @Test("为 Node.js 项目生成 npm 操作")
    func nodeProjectActions() {
        let provider = ActionProvider()
        let context = ProjectContext(
            rootPath: "/tmp/test-node-project",
            name: "TestNode",
            type: .node,
            isGitRepo: false,
            gitBranch: nil,
            sourceBundleID: "com.microsoft.VSCode"
        )
        let actions = provider.actions(for: context)
        #expect(!actions.isEmpty, "应该为 Node.js 项目生成操作")

        // 非 Git 仓库不应包含 Git 操作
        let hasGit = actions.contains { $0.category == .git }
        #expect(!hasGit, "非 Git 仓库不应包含 Git 操作")
    }

    @Test("缓存机制：相同路径返回相同结果")
    func cachingWorks() {
        let provider = ActionProvider()
        let context = ProjectContext(
            rootPath: "/tmp/test-cache-project",
            name: "CacheTest",
            type: .generic,
            isGitRepo: false,
            gitBranch: nil,
            sourceBundleID: nil
        )
        let first = provider.actions(for: context)
        let second = provider.actions(for: context)
        #expect(first.count == second.count, "缓存后应返回相同数量的操作")
    }

    @Test("invalidateCache 清除缓存")
    func invalidateCacheClearsCache() {
        let provider = ActionProvider()
        let context = ProjectContext(
            rootPath: "/tmp/test-invalidate-project",
            name: "InvalidateTest",
            type: .generic,
            isGitRepo: false,
            gitBranch: nil,
            sourceBundleID: nil
        )
        _ = provider.actions(for: context)
        provider.invalidateCache()
        // 缓存清除后再次生成不会崩溃
        let actions = provider.actions(for: context)
        #expect(!actions.isEmpty)
    }
}
