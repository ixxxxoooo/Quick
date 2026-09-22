// SuperPanelPluginTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
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
        #expect(SuperPanelPlugin.triggerWords.contains("超级面板"))
    }

    @Test("空查询不返回结果")
    func emptyQueryYieldsNothing() async {
        let plugin = SuperPanelPlugin()
        let results = await plugin.searchItems(query: "")
        #expect(results.isEmpty)
    }

    @Test("触发词至少给出打开入口")
    func triggerYieldsOpenEntry() async {
        let plugin = SuperPanelPlugin()
        let results = await plugin.searchItems(query: "sp")
        #expect(results.contains { $0.id == "superPanel.open" })
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

@Suite("智能预览检测")
struct SmartPreviewDetectorTests {

    @Test("空文本不返回预览")
    func emptyYieldsNothing() {
        #expect(SmartPreviewDetector.detect("").isEmpty)
        #expect(SmartPreviewDetector.detect("   ").isEmpty)
    }

    @Test("识别网址")
    func detectsURL() {
        let previews = SmartPreviewDetector.detect("https://example.com/path")
        #expect(
            previews.contains {
                if case .url(let url, let domain) = $0 {
                    return url.contains("example.com") && domain == "example.com"
                }
                return false
            })
    }

    @Test("识别 HEX 颜色")
    func detectsColor() {
        let previews = SmartPreviewDetector.detect("#FF5500")
        #expect(
            previews.contains {
                if case .color(let hex, let rgb) = $0 {
                    return hex == "#FF5500" && rgb.contains("255")
                }
                return false
            })
    }

    @Test("识别 Unix 时间戳")
    func detectsTimestamp() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let previews = SmartPreviewDetector.detect("1700000000", now: now)
        #expect(
            previews.contains {
                if case .timestamp(let original, let formatted, _) = $0 {
                    return original == "1700000000" && !formatted.isEmpty
                }
                return false
            })
    }

    @Test("识别文件路径（注入假文件系统）")
    func detectsFilePath() {
        let previews = SmartPreviewDetector.detect(
            "/tmp/demo-project",
            fileExists: { $0 == "/tmp/demo-project" },
            isDirectory: { $0 == "/tmp/demo-project" }
        )
        #expect(
            previews.contains {
                if case .filePath(let path, let exists, let isDir) = $0 {
                    return path == "/tmp/demo-project" && exists && isDir
                }
                return false
            })
    }

    @Test("识别 Base64 明文")
    func detectsBase64() {
        let encoded = "aGVsbG8gd29ybGQhISE="  // "hello world!!!"
        let previews = SmartPreviewDetector.detect(encoded)
        #expect(
            previews.contains {
                if case .base64(let decoded) = $0 {
                    return decoded.contains("hello")
                }
                return false
            })
    }

    @Test("识别 URL 编码")
    func detectsURLEncoded() {
        let previews = SmartPreviewDetector.detect("%E4%BD%A0%E5%A5%BD")
        #expect(
            previews.contains {
                if case .urlEncoded(let decoded) = $0 {
                    return decoded == "你好"
                }
                return false
            })
    }

    @Test("识别 IPv4")
    func detectsIP() {
        let previews = SmartPreviewDetector.detect("8.8.8.8")
        #expect(
            previews.contains {
                if case .ip(let address) = $0 { return address == "8.8.8.8" }
                return false
            })
        // 不应被当成网址
        #expect(
            !previews.contains {
                if case .url = $0 { return true }; return false
            })
    }

    @Test("识别邮箱")
    func detectsEmail() {
        let previews = SmartPreviewDetector.detect("user@example.com")
        #expect(
            previews.contains {
                if case .email(let email) = $0 { return email == "user@example.com" }
                return false
            })
    }

    @Test("识别 JSON")
    func detectsJSON() {
        let previews = SmartPreviewDetector.detect("{\"a\":1}")
        #expect(
            previews.contains {
                if case .json = $0 { return true }; return false
            })
    }

    @Test("识别简单算式")
    func detectsMath() {
        let previews = SmartPreviewDetector.detect("1+2*3")
        #expect(
            previews.contains {
                if case .math(_, let result) = $0 { return result == "7" }
                return false
            })
    }

    @Test("普通中文短句给出翻译候选")
    func detectsTranslationCandidate() {
        let previews = SmartPreviewDetector.detect("你好世界")
        #expect(
            previews.contains {
                if case .translation(_, let lang) = $0 { return lang == "zh" }
                return false
            })
    }

    @Test("无法识别时回落纯文本")
    func fallsBackToPlainText() {
        let previews = SmartPreviewDetector.detect("!!!@@@###")
        #expect(previews.count == 1)
        #expect(
            previews.contains {
                if case .plainText(_, let count) = $0 { return count > 0 }
                return false
            })
    }
}

@Suite("上下文动作构建")
@MainActor
struct ContextActionBuilderTests {

    @Test("网址预览生成打开动作")
    func urlActions() {
        let actions = ContextActionBuilder.actions(
            previews: [.url(url: "https://example.com", domain: "example.com")],
            sourceText: "https://example.com"
        )
        #expect(actions.contains { $0.id == "sp.open-url" })
        #expect(actions.contains { $0.id == "sp.copy-text" })
    }

    @Test("颜色预览生成复制与打开颜色工具")
    func colorActions() {
        let actions = ContextActionBuilder.actions(
            previews: [.color(hex: "#FF5500", rgb: "rgb(255, 85, 0)")],
            sourceText: "#FF5500"
        )
        #expect(actions.contains { $0.id == "sp.copy-hex" })
        #expect(actions.contains { $0.id == "sp.open-color" })
    }

    @Test("常用工具列表非空且 id 唯一")
    func quickToolsAreUnique() {
        let tools = SuperPanelQuickTools.defaults
        #expect(tools.count >= 6)
        #expect(Set(tools.map(\.id)).count == tools.count)
    }
}

@Suite("项目上下文模型")
struct ProjectContextTests {

    @Test("项目类型有图标和显示名")
    func projectTypeMetadata() {
        let types: [ProjectContext.ProjectType] = [
            .xcode, .node, .python, .rust, .golang, .java, .generic
        ]
        for type in types {
            #expect(!type.icon.isEmpty)
            #expect(!type.displayName.isEmpty)
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
        #expect(SuperPanelAction.Category.allCases.contains(.context))
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
        #expect(!actions.isEmpty)
        #expect(actions.contains { $0.id == "sp.open-terminal" })
        #expect(actions.contains { $0.id == "sp.open-finder" })
        #expect(actions.contains { $0.id == "sp.git-branch" })
        #expect(actions.contains { $0.id == "sp.git-status" })
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
        #expect(!actions.isEmpty)
        #expect(!actions.contains { $0.category == .git })
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
        #expect(provider.actions(for: context).count == provider.actions(for: context).count)
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
        #expect(!provider.actions(for: context).isEmpty)
    }
}
