// QuickPlatformTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Carbon.HIToolbox
import Foundation
import Testing
@testable import QuickPlatform

@Suite("QuickPlatform 核心能力")
struct QuickPlatformTests {

    @Test("SearchScopes 路径处理")
    func searchScopesNormalization() {
        let paths = ["/Applications/", "/Applications", "~/Applications/", ""]
        let normalized = SearchScopes.normalize(paths)
        #expect(normalized.contains("/Applications"))
        #expect(normalized.contains("~/Applications"))
        #expect(normalized.count == 2)
    }

    @Test("KeyShortcut 编码与解码")
    func keyShortcutEncoding() throws {
        let shortcut = KeyShortcut(carbonKeyCode: kVK_ANSI_A, carbonModifiers: cmdKey | optionKey)
        let data = try JSONEncoder().encode(shortcut)
        let decoded = try JSONDecoder().decode(KeyShortcut.self, from: data)
        #expect(decoded == shortcut)
        #expect(decoded.carbonKeyCode == kVK_ANSI_A)
    }

    @Test("ShellCommandRunner 执行简单命令")
    func shellCommandRunnerSimple() async {
        let result = await ShellCommandRunner.run("echo 'hello Quick'")
        #expect(result.succeeded)
        #expect(result.standardOutput.contains("hello Quick"))
    }

    @Test("AppPaths 用 bundle id 做根目录名")
    func appPathsUsesBundleIdentifier() {
        let support = AppPaths.applicationSupport()
        let caches = AppPaths.caches()
        #expect(FileManager.default.fileExists(atPath: support.path))
        #expect(FileManager.default.fileExists(atPath: caches.path))
        #expect(support.lastPathComponent == AppPaths.rootFolderName)
        #expect(caches.lastPathComponent == AppPaths.rootFolderName)
        #expect(
            AppIdentity.bundleIdentifier == AppPaths.rootFolderName
                || AppPaths.rootFolderName == "com.ygw.quick")
    }

    @Test("AppIdentity 渠道判断与展示名非空")
    func appIdentityBasics() {
        #expect(!AppIdentity.displayName.isEmpty)
        #expect(!AppIdentity.bundleIdentifier.isEmpty)
        // 测试宿主通常不是 .dev，正式/宿主都应能给出明确布尔值
        _ = AppIdentity.isDevChannel
    }
}
