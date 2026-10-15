// SystemControlView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 系统控制插件视图
///
/// 标题栏搜索筛选操作，↑↓ 移动、↵ 执行；破坏性操作先弹应用内确认框。
struct SystemControlView: View {

    /// 导航上下文里携带「待确认操作」的键
    static let confirmContextKey = "confirm"

    let runner: SystemActionRunner
    /// 命令是否被用户在设置里关掉；关掉的操作不展示，和主搜索、热键保持一致
    let isActionEnabled: (SystemAction) -> Bool

    @Environment(PluginSearchQuery.self) private var search: PluginSearchQuery?
    @Environment(\.pluginContext) private var context

    @State private var selected: SystemAction?
    @State private var pendingConfirm: ConfirmRequest?
    @State private var pendingAction: SystemAction?

    private var visibleActions: [SystemAction] {
        SystemActionFilter.filter(
            SystemAction.allCases.filter(isActionEnabled), query: search?.text ?? "")
    }

    var body: some View {
        Group {
            if visibleActions.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .onAppear {
            search?.wantsNavigation = true
            syncSelection()
        }
        .onChange(of: search?.shownToken ?? 0) { _, _ in
            search?.wantsNavigation = true
            syncSelection()
        }
        .onChange(of: search?.commandToken ?? 0) { _, _ in
            guard let command = search?.lastCommand else { return }
            handle(command)
        }
        .onChange(of: visibleActions) { _, _ in syncSelection() }
        // 热键 / 主搜索触发的破坏性操作带着 `confirm` 上下文跳进来，直接弹确认框
        .task(id: context) {
            guard let raw = context[Self.confirmContextKey], let action = SystemAction(rawValue: raw)
            else { return }
            selected = action
            requestConfirmation(for: action)
        }
        .confirmDialog($pendingConfirm, search: search) { _ in
            runPending()
        }
    }

    // MARK: - 列表

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DesignTokens.Spacing.xs) {
                    ForEach(visibleActions, id: \.rawValue) { action in
                        SystemActionRow(action: action, isSelected: action == selected) {
                            selected = action
                            activate(action)
                        }
                        .id(action.rawValue)
                    }
                }
                .padding(DesignTokens.Spacing.xl)
            }
            .onChange(of: selected) { _, newValue in
                guard let newValue else { return }
                proxy.scrollTo(newValue.rawValue)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "power.circle")
                .font(DesignTokens.Typography.emptyStateIcon)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text("没有匹配的系统操作")
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 键盘

    private func handle(_ command: PluginSearchQuery.Navigation) {
        // 确认框显示期间，按键只属于它
        if pendingConfirm != nil {
            switch ConfirmDialogKey.resolve(command) {
            case .confirm:
                pendingConfirm = nil
                runPending()
            case .cancel:
                pendingConfirm = nil
                pendingAction = nil
            case .ignore:
                break
            }
            return
        }
        switch command {
        case .move(let delta):
            moveSelection(by: delta)
        case .submit:
            if let selected { activate(selected) }
        case .tab, .cancel:
            break
        }
    }

    private func moveSelection(by delta: Int) {
        let actions = visibleActions
        guard !actions.isEmpty else { return }
        let current = selected.flatMap { actions.firstIndex(of: $0) } ?? (delta > 0 ? -1 : actions.count)
        selected = actions[max(0, min(actions.count - 1, current + delta))]
    }

    private func syncSelection() {
        if let selected, visibleActions.contains(selected) { return }
        selected = visibleActions.first
    }

    // MARK: - 执行

    private func activate(_ action: SystemAction) {
        if SystemControlPreferences.shouldConfirm(action) {
            requestConfirmation(for: action)
        } else {
            run(action)
        }
    }

    private func requestConfirmation(for action: SystemAction) {
        pendingAction = action
        pendingConfirm = ConfirmRequest(
            id: "system.\(action.rawValue)",
            title: "\(action.title)？",
            message: action.confirmMessage,
            confirmTitle: action.confirmTitle)
    }

    private func runPending() {
        defer { pendingAction = nil }
        guard let pendingAction else { return }
        run(pendingAction)
    }

    private func run(_ action: SystemAction) {
        runner.execute(action)
        EventBus.shared.post(HidePaletteEvent())
    }
}

/// 系统操作行视图
struct SystemActionRow: View {

    let action: SystemAction
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: action.icon)
                .font(DesignTokens.Typography.iconGlyph)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(width: DesignTokens.Size.rowIcon)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(action.title)
                    .font(DesignTokens.Typography.rowTitle)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                Text(action.description)
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            Spacer()

            if action.requiresConfirmation {
                Image(systemName: "exclamationmark.shield")
                    .font(DesignTokens.Typography.sidebarIcon)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .help("执行前会二次确认")
                    .accessibilityLabel("执行前需要确认")
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.row)
                .fill(
                    isSelected
                        ? DesignTokens.Colors.selection
                        : (isHovered ? DesignTokens.Colors.rowHover : .clear))
        }
        .onHover { isHovered = $0 }
        // contentShape 必须在手势之前：命中形状只对它之后添加的手势生效
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
