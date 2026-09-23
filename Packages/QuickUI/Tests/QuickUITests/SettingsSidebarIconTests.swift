// SettingsSidebarIconTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Testing
@testable import QuickUI

/// 设置侧栏色块尺寸与符号契约：对齐 Raycast Preferences 比例，防止再被面板缩放撑大
@Suite("SettingsSidebarIcon")
struct SettingsSidebarIconTests {

    @Test("色块边长固定 18pt，不跟 panelScale")
    func tileSizeIsFixedEighteen() {
        #expect(DesignTokens.Size.settingsIconTile == 18)
        #expect(DesignTokens.Size.settingsIconGlyph == 10)
        #expect(DesignTokens.Size.settingsIconGlyph < DesignTokens.Size.settingsIconTile)
    }

    @Test("色块与标题间距不小于色块一半，避免挤在一起")
    func iconTitleGapIsRoomy() {
        #expect(DesignTokens.Size.settingsSidebarIconGap >= 10)
        #expect(DesignTokens.Radius.settingsIconTile <= 6)
    }

    @Test("每个设置分栏都有非空 SF Symbol 与 tint 名")
    func everyTabHasIconMetadata() {
        for tab in SettingsTab.allCases {
            #expect(!tab.systemImage.isEmpty)
            #expect(!tab.iconTintName.isEmpty)
        }
    }

    @Test("常用插件符号保持简洁（无 badge / 双齿轮）")
    func pluginSymbolsStaySimple() {
        #expect(!SettingsTab.fileSearch.systemImage.contains("badge"))
        #expect(SettingsTab.general.systemImage == "gearshape.fill")
        #expect(SettingsTab.ocr.systemImage == "text.viewfinder")
        #expect(SettingsTab.killProcess.systemImage == "xmark.app.fill")
    }
}
