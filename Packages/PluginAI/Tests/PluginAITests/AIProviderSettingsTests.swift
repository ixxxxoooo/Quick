// AIProviderSettingsTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Testing

@testable import PluginAI

/// 这一组验证设置页上的 Provider 开关真的改变了行为，而不是只把值写进 `UserDefaults`。
///
/// 插件读的是标准偏好存储，用例也只能写标准存储 —— 换成独立 suite 就测不到接线了。
/// 标准存储是进程共享的，所以用例必须串行并自己收尾（见 `withStandardDefaults`）。
@Suite("AI Provider 开关接线", .serialized)
@MainActor
struct AIProviderSettingsTests {

    private static let providerID = "deepseek"
    private static let touchedKeys = [
        PluginSettingKey.AIPortal.providerEnabled(providerID),
        PluginSettingKey.AIPortal.defaultAlwaysOnTop
    ]

    /// 跑完把碰过的键的旧值原样放回去，不让用例互相污染，也不留在真实偏好里
    private static func withStandardDefaults(_ body: () async throws -> Void) async throws {
        var saved: [String: Any] = [:]
        for key in touchedKeys {
            saved[key] = UserDefaults.standard.object(forKey: key)
        }
        defer {
            for key in touchedKeys {
                if let previous = saved[key] {
                    UserDefaults.standard.set(previous, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
        try await body()
    }

    @Test("没设置过时 Provider 出现在搜索结果里")
    func providerEnabledByDefault() async throws {
        try await Self.withStandardDefaults {
            UserDefaults.standard.removeObject(
                forKey: PluginSettingKey.AIPortal.providerEnabled(Self.providerID))

            let items = await AIPlugin().searchItems(query: Self.providerID)
            #expect(
                items.contains { $0.id == "ai.\(Self.providerID)" },
                "默认应当是启用的，搜索结果里要有对应 Provider")
        }
    }

    @Test("被停用的 Provider 不出现在搜索结果里")
    func disabledProviderHiddenFromSearch() async throws {
        try await Self.withStandardDefaults {
            UserDefaults.standard.set(
                false, forKey: PluginSettingKey.AIPortal.providerEnabled(Self.providerID))

            let items = await AIPlugin().searchItems(query: Self.providerID)
            #expect(
                !items.contains { $0.id == "ai.\(Self.providerID)" },
                "停用后搜索结果里不该再有这个 Provider")
        }
    }

    @Test("被停用的 Provider 打不开窗口")
    func disabledProviderCannotOpen() async throws {
        try await Self.withStandardDefaults {
            UserDefaults.standard.set(
                false, forKey: PluginSettingKey.AIPortal.providerEnabled(Self.providerID))

            let manager = AIWebViewWindowManager()
            let opened = manager.openOrFocus(providerId: Self.providerID)
            #expect(
                !opened,
                "被停用的 Provider 不能报告打开成功 —— 面板上那句「已打开」是照它说的")
            #expect(
                !manager.isWindowOpen(for: Self.providerID),
                "停用的 Provider 不该被打开")
        }
    }

    @Test("面板能看出哪些 Provider 被停用")
    func portalSeesDisabledProviders() async throws {
        try await Self.withStandardDefaults {
            let manager = AIWebViewWindowManager()
            UserDefaults.standard.removeObject(
                forKey: PluginSettingKey.AIPortal.providerEnabled(Self.providerID))
            #expect(
                !manager.disabledProviderIDs().contains(Self.providerID),
                "默认应当是启用的，不该出现在停用集合里")

            UserDefaults.standard.set(
                false, forKey: PluginSettingKey.AIPortal.providerEnabled(Self.providerID))
            #expect(
                manager.disabledProviderIDs().contains(Self.providerID),
                "停用后门户卡片要能知道这个 Provider 打不开")
        }
    }

    @Test("「窗口默认置顶」读取时区分「没设置过」与「显式关掉」")
    func alwaysOnTopDefaultsToOff() async throws {
        try await Self.withStandardDefaults {
            UserDefaults.standard.removeObject(forKey: PluginSettingKey.AIPortal.defaultAlwaysOnTop)
            #expect(
                !PluginDefaults.isEnabled(PluginSettingKey.AIPortal.defaultAlwaysOnTop, default: false),
                "没设置过时应当按设置页显示的「关」")

            UserDefaults.standard.set(true, forKey: PluginSettingKey.AIPortal.defaultAlwaysOnTop)
            #expect(
                PluginDefaults.isEnabled(PluginSettingKey.AIPortal.defaultAlwaysOnTop, default: false))
        }
    }
}
