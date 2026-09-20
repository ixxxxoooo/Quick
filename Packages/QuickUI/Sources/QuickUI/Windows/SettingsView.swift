// SettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 设置窗口的内容
///
/// 结构参考实现的设置页：**侧边栏 + 详情**两栏。
///
/// - 侧边栏：顶上一个搜索框，下面是分栏列表；输入后切换成搜索结果。
/// - 详情：分组卡片（`.formStyle(.grouped)`），每行是
///   `SettingsRow`（图标槽位 + 标题/副标题 + 尾部控件）。
///
/// 为什么设置页用侧边栏而不是单栏表单：设置项会越加越多，单栏到十几个分组后
/// 就只能靠滚动找东西；侧边栏把「找哪一类」和「在这一类里找哪一项」分开，
/// 顺带给了搜索一个自然的落点。
///
/// 设置窗口是**普通窗口**，不是面板 —— 它跟随系统的窗口语言，
/// 面板那套（无边框、非激活、跨空间）在这里全都不适用。
public struct SettingsView: View {

    private let dataSource: any SettingsDataSource

    @State private var tab: SettingsTab? = .general
    @State private var query = ""
    @State private var searchSelection: String?
    @FocusState private var searchFocused: Bool

    /// 初始化
    /// - Parameter dataSource: 由组装层注入（AppCore 实现）
    public init(dataSource: any SettingsDataSource) {
        self.dataSource = dataSource
    }

    private var results: [SettingsSearchEntry] {
        SettingsSearchCatalog.results(for: query, modules: dataSource.moduleEntries)
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            detail
        }
        .navigationTitle("Quick 设置")
    }

    // MARK: - 侧边栏

    private var sidebar: some View {
        VStack(spacing: 0) {
            SettingsFilterField(prompt: "搜索设置", query: $query, isFocused: $searchFocused)
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.top, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.sm)

            if query.isEmpty {
                browse
            } else {
                found
            }
        }
        .background(focusShortcut)
    }

    /// 分栏列表
    private var browse: some View {
        List(selection: $tab) {
            Section("设置") {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
        }
        .listStyle(.sidebar)
    }

    /// 搜索结果
    @ViewBuilder
    private var found: some View {
        if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            // 单独一个 List：结果的 id 与分栏的选中值不能共用一套命名空间
            List(selection: $searchSelection) {
                Section("结果") {
                    ForEach(results) { entry in
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                            Text(entry.title)
                            if let subtitle = entry.subtitle {
                                Text(subtitle)
                                    .font(DesignTokens.Typography.rowTrailing)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(entry.id)
                    }
                }
            }
            .listStyle(.sidebar)
            // 在结果里上下移动就把详情切过去，和系统设置的手感一致
            .onChange(of: searchSelection) { _, id in
                guard let entry = results.first(where: { $0.id == id }) else { return }
                tab = entry.tab
            }
        }
    }

    /// ⌘F 聚焦搜索框
    ///
    /// 我们是没有主菜单的 accessory 应用，快捷键没地方挂，所以用一个零尺寸按钮承载。
    private var focusShortcut: some View {
        Button("搜索设置") { searchFocused = true }
            .keyboardShortcut("f", modifiers: .command)
            .buttonStyle(.plain)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    // MARK: - 详情

    @ViewBuilder
    private var detail: some View {
        switch tab ?? .general {
        case .general:
            GeneralPane(dataSource: dataSource)
        case .modules:
            ModulesPane(dataSource: dataSource)
        case .permissions:
            PermissionsPane(dataSource: dataSource)
        case .about:
            AboutPane(dataSource: dataSource)
        }
    }
}
