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

    /// 分区列表（参考 Tinycast SettingsSidebarView）
    private var browse: some View {
        List(selection: selectionBinding) {
            ForEach(SettingsSection.allCases) { section in
                Section(section.title) {
                    ForEach(section.tabs) { tab in
                        Label {
                            Text(tab.title)
                        } icon: {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 13, weight: .regular))
                                .frame(width: 18, height: 18, alignment: .center)
                        }
                        .tag(tab)
                    }
                }
            }
        }
        .listStyle(.sidebar)
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
                                .font(.system(size: 13, weight: .regular))
                                .frame(width: 18, height: 18, alignment: .center)
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
