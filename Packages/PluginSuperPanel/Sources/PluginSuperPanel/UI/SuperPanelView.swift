// SuperPanelView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import QuickUI
import SwiftUI

/// 超级面板主视图（对齐 Fasty：上下文态 + 工作台态）
///
/// - 有剪贴板/选中内容 → 默认「上下文」：Spotlight + 智能动作
/// - 无内容 → 默认「工作台」：常用工具 + 剪贴板 + 项目入口
/// - 「项目」页：保留原有 IDE 项目检测与 Git/构建操作
struct SuperPanelView: View {

    enum Tab: String, CaseIterable, Identifiable {
        case context = "上下文"
        case dock = "工作台"
        case project = "项目"
        var id: String { rawValue }
    }

    let plugin: SuperPanelPlugin

    @State private var tab: Tab = .dock
    @State private var clipboardText = ""
    @State private var previews: [SmartPreview] = []
    @State private var contextActions: [SuperPanelAction] = []
    @State private var project: ProjectContext?
    @State private var projectActions: [SuperPanelAction] = []
    @State private var isLoading = true
    @State private var filterText = ""
    @State private var hoveredID: String?

    @AppStorage(PluginSettingKey.SuperPanel.showClipboard) private var showClipboard = true
    @AppStorage(PluginSettingKey.SuperPanel.showQuickTools) private var showQuickTools = true

    private var primaryPreview: SmartPreview? {
        previews.first { $0.isMeaningful } ?? previews.first
    }

    private var hasContext: Bool {
        !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filteredProjectActions: [(SuperPanelAction.Category, [SuperPanelAction])] {
        let filtered: [SuperPanelAction]
        if filterText.isEmpty {
            filtered = projectActions
        } else {
            let query = filterText.lowercased()
            filtered = projectActions.filter {
                $0.title.localizedCaseInsensitiveContains(query)
                    || $0.subtitle.localizedCaseInsensitiveContains(query)
            }
        }
        let grouped = Dictionary(grouping: filtered, by: \.category)
        return SuperPanelAction.Category.allCases.compactMap { cat in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            return (cat, items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)

            if isLoading {
                loadingState
            } else {
                switch tab {
                case .context:
                    contextContent
                case .dock:
                    SuperPanelDockView(
                        clipboardText: clipboardText,
                        showQuickTools: showQuickTools,
                        showClipboard: showClipboard,
                        project: project,
                        onOpenProject: { tab = .project }
                    )
                case .project:
                    projectContent
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await reload() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Spacer(minLength: DesignTokens.Spacing.md)

            Button {
                Task { await reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(DesignTokens.Typography.iconGlyph)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .help("刷新上下文")
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    // MARK: - 上下文

    @ViewBuilder
    private var contextContent: some View {
        if !hasContext {
            VStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: "doc.on.clipboard")
                    .font(DesignTokens.Typography.emptyStateIcon)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text("剪贴板为空")
                    .font(DesignTokens.Typography.panelTitle)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Text("复制网址、色值、时间戳、路径等内容后刷新")
                    .font(DesignTokens.Typography.rowTitle)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Button("切换到工作台") { tab = .dock }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                if let primaryPreview {
                    SuperPanelSpotlightCard(preview: primaryPreview, sourceText: clipboardText)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        sectionTitle("操作")
                        ForEach(contextActions) { action in
                            actionRow(action)
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.bottom, DesignTokens.Spacing.lg)
                }
            }
        }
    }

    // MARK: - 项目

    @ViewBuilder
    private var projectContent: some View {
        if let project {
            projectHeader(project)
            filterBar
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredProjectActions, id: \.0) { category, items in
                        sectionTitle(category.rawValue)
                        ForEach(items) { action in
                            actionRow(action)
                        }
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.lg)
            }
        } else {
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
                Button("手动选择目录") { selectDirectory() }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

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
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                        .fill(Color.accentColor.opacity(0.1))
                )

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(context.name)
                    .font(DesignTokens.Typography.panelTitle)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text(context.type.displayName)
                    if let branch = context.gitBranch {
                        Label(branch, systemImage: "arrow.triangle.branch")
                    }
                }
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.lg)
        .background(DesignTokens.Colors.cardFill)
    }

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

    // MARK: - 共享行

    private func sectionTitle(_ title: String) -> some View {
        HStack {
            Text(title)
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
        } label: {
            HStack(spacing: DesignTokens.Spacing.lg) {
                Image(systemName: action.icon)
                    .font(DesignTokens.Typography.iconGlyph)
                    .foregroundStyle(isHovered ? Color.white : Color.accentColor)
                    .frame(width: DesignTokens.Size.rowIcon, height: DesignTokens.Size.rowIcon)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(action.title)
                        .font(DesignTokens.Typography.rowTitle)
                        .foregroundStyle(isHovered ? Color.white : DesignTokens.Colors.textPrimary)
                    Text(action.subtitle)
                        .font(DesignTokens.Typography.rowTrailing)
                        .foregroundStyle(
                            isHovered ? Color.white.opacity(0.7) : DesignTokens.Colors.textSecondary
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

    private var loadingState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ProgressView().controlSize(.large)
            Text("加载上下文…")
                .font(DesignTokens.Typography.rowTitle)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 数据

    private func reload() async {
        isLoading = true

        // 剪贴板 → 智能预览（对齐 Fasty 选中文本 / 剪贴板上下文）
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        clipboardText = text
        previews = SmartPreviewDetector.detect(text)
        contextActions = ContextActionBuilder.actions(previews: previews, sourceText: text)

        // 项目检测
        project = await plugin.detector.detect()
        if let project {
            projectActions = plugin.actionProvider.actions(for: project)
        } else {
            projectActions = []
        }

        // 有内容默认上下文，否则工作台（有项目时也可以从工作台点进去）
        if hasContext {
            tab = .context
        } else if project != nil, tab == .context {
            tab = .dock
        }

        isLoading = false
    }

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "选择项目根目录"

        if panel.runModal() == .OK, let url = panel.url {
            let ctx = ProjectContext(
                rootPath: url.path,
                name: url.lastPathComponent,
                type: .generic,
                isGitRepo: FileManager.default.fileExists(
                    atPath: url.appendingPathComponent(".git").path),
                gitBranch: nil,
                sourceBundleID: nil
            )
            project = ctx
            projectActions = plugin.actionProvider.actions(for: ctx)
            tab = .project
        }
    }
}
