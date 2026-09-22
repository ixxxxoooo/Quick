// SettingsSidebarView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import SwiftUI

/// 设置侧边栏视图
///
/// 参考 Tinycast 设计：
/// - 顶部为 SettingsSearchField（胶囊形毛玻璃搜索框）
/// - 下方为标准 macOS 侧边栏列表（.listStyle(.sidebar)）
/// - 搜索有内容时显示搜索结果列表
/// - 支持 ⌘F 聚焦搜索框
struct SettingsSidebarView: View {

    let dataSource: any SettingsDataSource
    @Bindable var navigationState: SettingsNavigationState

    @State private var query = ""
    @State private var searchSelection: String?
    @FocusState private var searchFocused: Bool

    private var results: [SettingsSearchEntry] {
        SettingsSearchCatalog.results(for: query, plugins: dataSource.pluginEntries)
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsSearchField(query: $query, isFocused: $searchFocused)
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.bottom, DesignTokens.Spacing.md)

            if query.isEmpty {
                browse
            } else {
                found
            }
        }
        .padding(.top, DesignTokens.Spacing.md)
        .onExitCommand { query = "" }
        .background(focusShortcut)
    }

    /// 分区列表：宿主页面在上，「插件」是分类，每个插件一项，关于在最后
    private var browse: some View {
        List(selection: selectionBinding) {
            Section {
                ForEach(SettingsSection.host.tabs) { tab in
                    sidebarRow(title: tab.title, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            Section("插件") {
                ForEach(pluginRows, id: \.plugin.id) { row in
                    sidebarRow(title: row.plugin.name, systemImage: row.plugin.icon)
                        .tag(row.tab)
                }
            }
            Section {
                sidebarRow(title: SettingsTab.about.title, systemImage: SettingsTab.about.systemImage)
                    .tag(SettingsTab.about)
            }
        }
        .listStyle(.sidebar)
    }

    /// 已注册插件里，能对上设置页的那些。顺序跟插件名单一致
    private var pluginRows: [(plugin: SettingsPlugin, tab: SettingsTab)] {
        dataSource.pluginEntries.compactMap { plugin in
            guard let tab = SettingsTab.tab(forPluginID: plugin.id) else { return nil }
            return (plugin, tab)
        }
    }

    private func sidebarRow(title: String, systemImage: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .font(DesignTokens.Typography.sidebarIcon)
                .frame(
                    width: DesignTokens.Size.sidebarIconSlot,
                    height: DesignTokens.Size.sidebarIconSlot,
                    alignment: .center)
        }
    }

    private var selectionBinding: Binding<SettingsTab?> {
        Binding(
            get: { navigationState.tab },
            set: { tab in
                guard let tab else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    navigationState.tab = tab
                }
            }
        )
    }

    /// 搜索结果
    @ViewBuilder
    private var found: some View {
        if results.isEmpty {
            ContentUnavailableView.search(text: query)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $searchSelection) {
                Section("搜索结果") {
                    ForEach(results) { entry in
                        Label {
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                                Text(entry.title)
                                    .lineLimit(1)
                                if let subtitle = entry.subtitle {
                                    Text(subtitle)
                                        .font(DesignTokens.Typography.rowTrailing)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        } icon: {
                            Image(systemName: entry.tab.systemImage)
                                .font(DesignTokens.Typography.sidebarIcon)
                                .frame(
                                    width: DesignTokens.Size.sidebarIconSlot,
                                    height: DesignTokens.Size.sidebarIconSlot,
                                    alignment: .center)
                        }
                        .tag(entry.id)
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: searchSelection) { _, id in
                guard let entry = results.first(where: { $0.id == id }) else { return }
                navigationState.tab = entry.tab
            }
        }
    }

    /// ⌘F 聚焦搜索框
    private var focusShortcut: some View {
        Button("搜索设置") { searchFocused = true }
            .keyboardShortcut("f", modifiers: .command)
            .buttonStyle(.plain)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }
}
