// SuperPanelView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 超级面板在面板内的主视图
///
/// 展示当前项目上下文和可用操作。布局参考 Fasty 的超级面板：
/// 顶部是项目信息卡片，下方按分类列出操作。
struct SuperPanelView: View {

    let plugin: SuperPanelPlugin

    @State private var context: ProjectContext?
    @State private var actions: [SuperPanelAction] = []
    @State private var isLoading = true
    @State private var filterText = ""
    @State private var hoveredID: String?

    /// 按分类分组后的操作
    private var groupedActions: [(SuperPanelAction.Category, [SuperPanelAction])] {
        let filtered: [SuperPanelAction]
        if filterText.isEmpty {
            filtered = actions
        } else {
            let query = filterText.lowercased()
            filtered = actions.filter {
                $0.title.localizedCaseInsensitiveContains(query)
                    || $0.subtitle.localizedCaseInsensitiveContains(query)
                    || $0.category.rawValue.localizedCaseInsensitiveContains(query)
            }
        }

        let grouped = Dictionary(grouping: filtered, by: \.category)
        return SuperPanelAction.Category.allCases
            .compactMap { cat in
                guard let items = grouped[cat], !items.isEmpty else { return nil }
                return (cat, items)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                loadingState
            } else if let context {
                // 项目信息头
                projectHeader(context)

                // 搜索过滤
                filterBar

                // 操作列表
                actionList
            } else {
                noProjectState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await loadContext()
        }
    }

    // MARK: - 项目头部

    private func projectHeader(_ context: ProjectContext) -> some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: context.type.icon)
                .font(DesignTokens.Typography.iconGlyph)
                .foregroundStyle(Color.accentColor)
                .frame(
                    width: DesignTokens.Size.rowIcon + DesignTokens.Spacing.xl,
                    height: DesignTokens.Size.rowIcon + DesignTokens.Spacing.xl
                )
                .background(
                    RoundedRectangle(
                        cornerRadius: DesignTokens.Radius.card, style: .continuous
                    )
                    .fill(Color.accentColor.opacity(0.1))
                )

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(context.name)
                    .font(DesignTokens.Typography.panelTitle)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                HStack(spacing: DesignTokens.Spacing.sm) {
                    Label(context.type.displayName, systemImage: context.type.icon)
                        .font(DesignTokens.Typography.rowTrailing)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)

                    if let branch = context.gitBranch {
                        Label(branch, systemImage: "arrow.triangle.branch")
                            .font(DesignTokens.Typography.rowTrailing)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                }
            }

            Spacer()

            // 刷新按钮
            Button {
                Task { await refreshContext() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(DesignTokens.Typography.iconGlyph)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .help("刷新项目信息")
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.lg)
        .background(DesignTokens.Colors.cardFill)
    }

    // MARK: - 过滤栏

    private var filterBar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(DesignTokens.Typography.inlineIcon)
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            TextField("过滤操作…", text: $filterText)
                .textFieldStyle(.plain)
                .font(DesignTokens.Typography.rowTitle)
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    // MARK: - 操作列表

    private var actionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groupedActions, id: \.0) { category, items in
                    sectionHeader(category)

                    ForEach(items) { action in
                        actionRow(action)
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.bottom, DesignTokens.Spacing.lg)
        }
    }

    private func sectionHeader(_ category: SuperPanelAction.Category) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Text(category.rawValue)
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.top, DesignTokens.Spacing.sectionSpacing)
        .padding(.bottom, DesignTokens.Spacing.sectionHeaderBottom)
    }

    private func actionRow(_ action: SuperPanelAction) -> some View {
        let isHovered = hoveredID == action.id

        return Button {
            action.execute()
            EventBus.shared.post(HidePaletteEvent())
        } label: {
            HStack(spacing: DesignTokens.Spacing.lg) {
                Image(systemName: action.icon)
                    .font(DesignTokens.Typography.iconGlyph)
                    .foregroundStyle(
                        isHovered ? Color.white : Color.accentColor
                    )
                    .frame(width: DesignTokens.Size.rowIcon, height: DesignTokens.Size.rowIcon)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(action.title)
                        .font(DesignTokens.Typography.rowTitle)
                        .foregroundStyle(
                            isHovered
                                ? Color.white : DesignTokens.Colors.textPrimary
                        )

                    Text(action.subtitle)
                        .font(DesignTokens.Typography.rowTrailing)
                        .foregroundStyle(
                            isHovered
                                ? Color.white.opacity(0.7) : DesignTokens.Colors.textSecondary
                        )
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                    .fill(isHovered ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hoveredID = $0 ? action.id : nil }
    }

    // MARK: - 空状态

    private var loadingState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ProgressView()
                .controlSize(.large)
            Text("检测项目…")
                .font(DesignTokens.Typography.rowTitle)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noProjectState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "questionmark.folder")
                .font(DesignTokens.Typography.emptyStateIcon)
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            Text("未检测到项目")
                .font(DesignTokens.Typography.panelTitle)
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Text("请先在 IDE 或终端中打开一个项目")
                .font(DesignTokens.Typography.rowTitle)
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            Button("手动选择目录") {
                selectDirectory()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 数据加载

    private func loadContext() async {
        isLoading = true
        context = await plugin.detector.detect()
        if let context {
            actions = plugin.actionProvider.actions(for: context)
        }
        isLoading = false
    }

    private func refreshContext() async {
        plugin.actionProvider.invalidateCache()
        context = await plugin.detector.refresh()
        if let context {
            actions = plugin.actionProvider.actions(for: context)
        }
    }

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "选择项目根目录"

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                let ctx = ProjectContext(
                    rootPath: url.path,
                    name: url.lastPathComponent,
                    type: .generic,
                    isGitRepo: FileManager.default.fileExists(
                        atPath: url.appendingPathComponent(".git").path),
                    gitBranch: nil,
                    sourceBundleID: nil
                )
                context = ctx
                actions = plugin.actionProvider.actions(for: ctx)
            }
        }
    }
}
