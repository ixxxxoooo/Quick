// SettingsSidebarView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import SwiftUI

/// 设置侧边栏视图
///
/// 参考 Tinycast / Raycast Preferences：
/// - 顶部为 SettingsSearchField（胶囊形毛玻璃搜索框）
/// - 下方为侧栏列表：小色块图标 + 较宽图标间距 + Regular 标题
/// - 选中态用中性浅灰，不用系统强调蓝
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

    /// 侧栏一行：色块与标题间距、字重按 Raycast 比例手写，不用系统 Label 默认紧排
    private func sidebarRow(
        title: String,
        systemImage: String,
        tintName: String,
        isSelected: Bool,
        subtitle: String? = nil
    ) -> some View {
        HStack(spacing: DesignTokens.Size.settingsSidebarIconGap) {
            SettingsTileIcon(
                systemImage: systemImage,
                tint: .named(tintName)
            )
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(title)
                    .font(DesignTokens.Typography.settingsSidebarLabel)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(DesignTokens.Typography.rowTrailing)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DesignTokens.Size.settingsSidebarRowVertical)
        .padding(.horizontal, DesignTokens.Size.settingsSidebarRowHorizontal)
        .listRowInsets(
            EdgeInsets(
                top: DesignTokens.Spacing.xxs,
                leading: DesignTokens.Spacing.sm,
                bottom: DesignTokens.Spacing.xxs,
                trailing: DesignTokens.Spacing.sm
            )
        )
        .listRowBackground(sidebarSelectionBackground(isSelected: isSelected))
    }

    /// 中性浅灰选中底，圆角与侧栏行齐平
    @ViewBuilder
    private func sidebarSelectionBackground(isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.menu, style: .continuous)
                .fill(DesignTokens.Colors.settingsSidebarSelection)
                .padding(.horizontal, DesignTokens.Spacing.xs)
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

    /// 分区列表：宿主页面在上，「插件」是分类，每个插件一项，关于在最后
    private var browse: some View {
        List(selection: selectionBinding) {
            Section {
                ForEach(SettingsSection.host.tabs) { tab in
                    sidebarRow(
                        title: tab.title,
                        systemImage: tab.systemImage,
                        tintName: tab.iconTintName,
                        isSelected: navigationState.tab == tab
                    )
                    .tag(tab)
                }
            }
            Section("插件") {
                ForEach(pluginRows, id: \.plugin.id) { row in
                    sidebarRow(
                        title: row.plugin.name,
                        systemImage: row.tab.systemImage,
                        tintName: row.tab.iconTintName,
                        isSelected: navigationState.tab == row.tab
                    )
                    .tag(row.tab)
                }
            }
            Section {
                sidebarRow(
                    title: SettingsTab.about.title,
                    systemImage: SettingsTab.about.systemImage,
                    tintName: SettingsTab.about.iconTintName,
                    isSelected: navigationState.tab == .about
                )
                .tag(SettingsTab.about)
            }
        }
        .listStyle(.sidebar)
        // 压低系统强调色，避免盖过自绘的浅灰选中底
        .tint(.clear)
    }

    /// 已注册插件里，能对上设置页的那些。顺序跟插件名单一致
    private var pluginRows: [(plugin: SettingsPlugin, tab: SettingsTab)] {
        dataSource.pluginEntries.compactMap { plugin in
            guard let tab = SettingsTab.tab(forPluginID: plugin.id) else { return nil }
            return (plugin, tab)
        }
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
                        sidebarRow(
                            title: entry.title,
                            systemImage: entry.tab.systemImage,
                            tintName: entry.tab.iconTintName,
                            isSelected: searchSelection == entry.id,
                            subtitle: entry.subtitle
                        )
                        .tag(entry.id)
                    }
                }
            }
            .listStyle(.sidebar)
            .tint(.clear)
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
