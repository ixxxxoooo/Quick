// SettingsDetailView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import SwiftUI

/// 设置详情列宿主视图
///
/// 参考 Tinycast 设计：
/// - 根据当前选中 Tab 展示对应面板
/// - 纯净内容背景（VisualEffectView(material: .contentBackground, blending: .behindWindow)）
/// - 顶部由系统工具栏与窗口标题占据，内容区无需冗余标题与搜索框
struct SettingsDetailView: View {

    let dataSource: any SettingsDataSource
    let navigationState: SettingsNavigationState

    var body: some View {
        Group {
            switch navigationState.tab {
            case .general:
                GeneralPane(dataSource: dataSource)
            case .appearance:
                AppearancePane(dataSource: dataSource)
            case .shortcuts:
                ShortcutsPane(dataSource: dataSource)
            case .search:
                SearchPane(dataSource: dataSource)
            case .permissions:
                PermissionsPane(dataSource: dataSource)
            case .plugins:
                ContentUnavailableView(
                    "选择一个插件",
                    systemImage: "square.grid.2x2",
                    description: Text("插件在左侧单独列出。点进去可以看介绍、命令和它自己的设置。")
                )
            case .applications:
                ApplicationsSettingsPane(dataSource: dataSource)
            case .systemActions:
                SystemActionsSettingsPane(dataSource: dataSource)
            case .commands:
                CommandsSettingsPane(dataSource: dataSource)
            case .about:
                AboutPane(dataSource: dataSource)
            default:
                FeatureSettingsPane(tab: navigationState.tab, dataSource: dataSource)
            }
        }
        .id(navigationState.tab)
        .transaction { $0.disablesAnimations = true }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .contentBackground, blending: .behindWindow)
                .ignoresSafeArea()
        )
        .scrollContentBackground(.hidden)
    }
}
