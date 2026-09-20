// SettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import SwiftUI

/// 设置窗口的 SwiftUI 内容根视图（供预览或独立嵌入）
public struct SettingsView: View {

    private let dataSource: any SettingsDataSource
    @State private var navigationState: SettingsNavigationState

    /// 初始化
    /// - Parameters:
    ///   - dataSource: 由组装层注入（AppCore 实现）
    ///   - initialTab: 初始选中的分栏
    public init(dataSource: any SettingsDataSource, initialTab: SettingsTab = .general) {
        self.dataSource = dataSource
        _navigationState = State(initialValue: SettingsNavigationState(tab: initialTab))
    }

    public var body: some View {
        HStack(spacing: 0) {
            SettingsSidebarView(dataSource: dataSource, navigationState: navigationState)
                .frame(width: DesignTokens.Size.settingsSidebar)

            Divider()

            SettingsDetailView(dataSource: dataSource, navigationState: navigationState)
        }
    }
}
