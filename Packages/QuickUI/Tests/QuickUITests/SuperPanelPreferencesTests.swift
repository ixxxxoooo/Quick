// SuperPanelPreferencesTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing
@testable import QuickUI

@Suite("超级面板偏好")
struct SuperPanelPreferencesTests {

    @Test("长按阈值夹紧到 50…1000 并对齐 50 步进")
    func clampsThreshold() {
        #expect(SuperPanelPreferences.clampedThreshold(0) == 50)
        #expect(SuperPanelPreferences.clampedThreshold(1200) == 1000)
        #expect(SuperPanelPreferences.clampedThreshold(470) == 450)
        #expect(SuperPanelPreferences.clampedThreshold(450) == 450)
    }

    @Test("不透明度夹紧到 0.30…1.0")
    func clampsOpacity() {
        #expect(SuperPanelPreferences.clampedOpacity(0.1) == 0.30)
        #expect(SuperPanelPreferences.clampedOpacity(1.5) == 1.0)
        #expect(SuperPanelPreferences.clampedOpacity(0.85) == 0.85)
    }

    @Test("鼠标配置的默认值")
    func mouseDefaults() {
        let suite = UserDefaults(suiteName: "superpanel.test.\(UUID().uuidString)")!
        let config = SuperPanelPreferences.mouseConfiguration(from: suite)
        #expect(config.rightLongPressEnabled)
        #expect(config.middleClickEnabled)
        #expect(config.thresholdMilliseconds == SuperPanelPreferences.defaultThresholdMs)
    }

    @Test("工具列表读不出时回落到默认八宫格")
    func quickToolsFallback() {
        let suite = UserDefaults(suiteName: "superpanel.test.\(UUID().uuidString)")!
        #expect(SuperPanelQuickTools.load(from: suite) == SuperPanelQuickTools.defaults)
    }

    @Test("默认八宫格正好 8 项，且都在目录里")
    func defaultsAreEightAndInCatalog() {
        #expect(SuperPanelQuickTools.defaults.count == 8)
        let catalogIDs = Set(SuperPanelQuickTools.catalog.map(\.id))
        #expect(SuperPanelQuickTools.defaults.allSatisfy { catalogIDs.contains($0.id) })
    }

    @Test("目录里的工具 id 与插件 id 都不重复")
    func catalogHasUniqueIdentifiers() {
        let ids = SuperPanelQuickTools.catalog.map(\.id)
        let pluginIDs = SuperPanelQuickTools.catalog.map(\.pluginID)
        #expect(Set(ids).count == ids.count)
        #expect(Set(pluginIDs).count == pluginIDs.count)
    }

    @Test("已下线插件的残留 id 被忽略，不会产生跳到空白页的工具")
    func staleToolIDsAreDropped() {
        let suite = UserDefaults(suiteName: "superpanel.test.\(UUID().uuidString)")!
        SuperPanelQuickTools.save(
            [SuperPanelQuickTool(id: "notes", title: "备忘", icon: "text.page", pluginID: "notes")],
            to: suite)
        // 唯一一项已不在目录里 → 整体回落到默认，而不是留下一个点不开的格子
        #expect(SuperPanelQuickTools.load(from: suite) == SuperPanelQuickTools.defaults)

        suite.set(["notes", "json", "ocr"], forKey: SuperPanelPreferences.Key.quickTools)
        #expect(SuperPanelQuickTools.load(from: suite).map(\.id) == ["json"])
    }
}
