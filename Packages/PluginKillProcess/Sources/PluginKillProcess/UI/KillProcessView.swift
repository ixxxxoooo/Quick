// KillProcessView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 结束进程主视图
///
/// 标题栏搜索由 `supportsPanelSearch` 提供；本视图只负责排序切换、列表与结束动作。
struct KillProcessView: View {

    let service: KillProcessService

    @Environment(PluginSearchQuery.self) private var search: PluginSearchQuery?
    @AppStorage(PluginSettingKey.KillProcess.showPID) private var showPID = false
    @AppStorage(PluginSettingKey.KillProcess.searchInPath) private var searchInPath = false
    @AppStorage(PluginSettingKey.KillProcess.searchInPID) private var searchInPID = false

    @State private var selectedID: Int32?
    /// 待确认的结束请求；非 nil 时显示确认框
    @State private var pendingConfirm: ConfirmRequest?
    /// 待确认请求对应的目标与方式（`ConfirmRequest` 只带展示文案）
    @State private var pendingKill: (process: ProcessRecord, force: Bool)?
    @FocusState private var isFocused: Bool

    private var visibleProcesses: [ProcessRecord] {
        KillProcessListing.filter(
            service.processes,
            query: search?.text ?? "",
            searchPath: searchInPath,
            searchPID: searchInPID
        )
    }

    private var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return visibleProcesses.firstIndex { $0.id == selectedID }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(DesignTokens.Opacity.divider)
            if visibleProcesses.isEmpty {
                emptyState
            } else {
                processList
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear {
            search?.wantsNavigation = true
            isFocused = true
            syncSelection()
            // 采样走 service 持有的受控循环：面板被 orderOut 隐藏时 SwiftUI 的
            // .task 不会取消，受控循环才能由面板显隐事件叫停
            service.noteViewAppeared()
        }
        .onChange(of: search?.shownToken ?? 0) { _, _ in
            search?.wantsNavigation = true
            isFocused = true
            syncSelection()
        }
        .onDisappear {
            service.noteViewDisappeared()
        }
        .onChange(of: search?.commandToken ?? 0) { _, _ in
            guard let command = search?.lastCommand else { return }
            handle(command)
        }
        .onChange(of: visibleProcesses.map(\.id)) { _, _ in
            syncSelection()
        }
        .confirmDialog($pendingConfirm, search: search) { _ in
            performPendingKill()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Text("进程")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text("\(visibleProcesses.count) 个运行中")
                .font(DesignTokens.Typography.keyCap)
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            Spacer()

            Picker(
                "排序",
                selection: Binding(
                    get: { service.sortMode },
                    set: { mode in
                        service.setSortMode(mode)
                        Task { await service.refresh() }
                    }
                )
            ) {
                ForEach(KillProcessSortMode.allCases, id: \.rawValue) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: DesignTokens.Size.monitorSidebar)
            .labelsHidden()
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    // MARK: - List

    private var processList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visibleProcesses) { process in
                        processRow(process)
                            .id(process.id)
                    }
                }
            }
            // 边缘跟随、不做动画：见 `ListScrollFollow`。居中 + 动画会让长按方向键时整个列表一直在滑。
            .onChange(of: selectedID) { _, newValue in
                guard let newValue,
                    let index = visibleProcesses.firstIndex(where: { $0.id == newValue })
                else { return }
                proxy.scrollTo(
                    newValue,
                    anchor: ListScrollFollow.anchor(for: index, count: visibleProcesses.count))
            }
        }
    }

    private func processRow(_ process: ProcessRecord) -> some View {
        let isSelected = process.id == selectedID
        return Button {
            selectedID = process.id
        } label: {
            HStack(spacing: DesignTokens.Spacing.md) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(process.name)
                        .font(DesignTokens.Typography.bar)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)
                    if showPID || process.displayPath(home: Self.homeDirectory) != nil {
                        Text(Self.subtitle(for: process, showPID: showPID))
                            .font(DesignTokens.Typography.keyCap)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: DesignTokens.Spacing.sm)
                metricLabel(for: process)
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                    .fill(isSelected ? DesignTokens.Colors.rowHover : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("结束") { requestKill(process, force: false) }
            Button("强制结束", role: .destructive) { requestKill(process, force: true) }
        }
    }

    /// 家目录在视图层取一次（模型层不碰环境）
    private static let homeDirectory = NSHomeDirectory()

    /// 副标题：`PID 123 · ~/path`，两段各自可缺
    private static func subtitle(for process: ProcessRecord, showPID: Bool) -> String {
        [showPID ? "PID \(process.id)" : nil, process.displayPath(home: homeDirectory)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func metricLabel(for process: ProcessRecord) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: service.sortMode == .cpu ? "cpu" : "memorychip")
                .font(DesignTokens.Typography.sidebarIcon)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text(service.sortMode == .cpu ? process.cpuText : process.memoryText)
                .font(DesignTokens.Typography.code)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .monospacedDigit()
        }
    }

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "tray")
                .font(DesignTokens.Typography.emptyStateIcon)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text((search?.text.isEmpty ?? true) ? "暂无进程" : "没有匹配的进程")
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "xmark.circle")
                    .font(DesignTokens.Typography.sidebarIcon)
                Text("结束进程")
                    .font(DesignTokens.Typography.bar)
            }
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(
                Capsule(style: .continuous)
                    .fill(DesignTokens.Colors.controlSurface)
            )

            Spacer()

            Button {
                killSelected(force: false)
            } label: {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text("结束")
                        .font(DesignTokens.Typography.bar)
                    KeyCapChip(text: "↵", style: .outline, scale: .compact)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .frame(height: DesignTokens.Size.barButtonHeight)
                .background(
                    Capsule(style: .continuous)
                        .fill(DesignTokens.Colors.controlSurface)
                )
            }
            .buttonStyle(.plain)
            .disabled(selectedProcess == nil)
            .keyboardShortcut(.return, modifiers: [])

            Button {
                killSelected(force: true)
            } label: {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text("强制结束")
                        .font(DesignTokens.Typography.bar)
                    KeyCapChip(text: "⌘↵", style: .outline, scale: .compact)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .frame(height: DesignTokens.Size.barButtonHeight)
                .background(
                    Capsule(style: .continuous)
                        .fill(DesignTokens.Colors.controlSurface)
                )
            }
            .buttonStyle(.plain)
            .disabled(selectedProcess == nil)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .frame(height: DesignTokens.Size.bottomBarHeight)
        .background(DesignTokens.Colors.cardFill.opacity(DesignTokens.Opacity.cardFillDim))
    }

    private var selectedProcess: ProcessRecord? {
        guard let selectedID else { return nil }
        return visibleProcesses.first { $0.id == selectedID }
    }

    // MARK: - Navigation

    private func handle(_ command: PluginSearchQuery.Navigation) {
        // 确认框显示期间，按键只属于它：↵ 确认、Esc 取消，其余吞掉
        if pendingConfirm != nil {
            switch ConfirmDialogKey.resolve(command) {
            case .confirm:
                let request = pendingConfirm
                pendingConfirm = nil
                if request != nil { performPendingKill() }
            case .cancel:
                pendingConfirm = nil
                pendingKill = nil
            case .ignore:
                break
            }
            return
        }
        switch command {
        case .move(let delta):
            moveSelection(by: delta)
        case .tab(let delta):
            cycleSort(by: delta)
        case .submit:
            killSelected(force: false)
        case .cancel:
            break
        }
    }

    private func moveSelection(by delta: Int) {
        guard !visibleProcesses.isEmpty else { return }
        let current = selectedIndex ?? 0
        let next = max(0, min(visibleProcesses.count - 1, current + delta))
        selectedID = visibleProcesses[next].id
    }

    private func cycleSort(by delta: Int) {
        let all = KillProcessSortMode.allCases
        guard let index = all.firstIndex(of: service.sortMode) else { return }
        let next = (index + delta + all.count) % all.count
        service.setSortMode(all[next])
        Task { await service.refresh() }
    }

    private func syncSelection() {
        if let selectedID, visibleProcesses.contains(where: { $0.id == selectedID }) {
            return
        }
        selectedID = visibleProcesses.first?.id
    }

    private func killSelected(force: Bool) {
        guard let process = selectedProcess else { return }
        requestKill(process, force: force)
    }

    /// 结束请求入口：需要确认就弹框，否则直接发信号
    private func requestKill(_ process: ProcessRecord, force: Bool) {
        let needsConfirm = KillConfirmPolicy.needsConfirmation(
            force: force, processName: process.name,
            confirmForceKill: KillProcessPreferences.confirmForceKill())
        guard needsConfirm else {
            service.kill(process, force: force)
            return
        }
        pendingKill = (process, force)
        pendingConfirm = ConfirmRequest(
            id: "kill.\(process.id).\(force)",
            title: force ? "强制结束「\(process.name)」？" : "结束「\(process.name)」？",
            message: KillConfirmPolicy.message(force: force, processName: process.name),
            confirmTitle: force ? "强制结束" : "结束")
    }

    private func performPendingKill() {
        defer { pendingKill = nil }
        guard let pendingKill else { return }
        service.kill(pendingKill.process, force: pendingKill.force)
    }
}
