// JSONFormatterView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// JSON 格式化面板
///
/// 单栏原地编辑：`格式化` / `压缩` / `反转义` 都把结果写回同一个编辑区，不再分左右两栏。
/// 顶部可切到**树视图**，把结构渲染成可折叠的节点，方便找某个字段。
struct JSONFormatterView: View {

    /// 代码视图 / 树视图
    enum Mode: String, CaseIterable {
        case code = "代码"
        case tree = "树"
    }

    /// 当前文本（唯一真相：代码视图编辑它，格式化也写回它）
    /// 输入文本归插件所有：主面板与分离窗口共享同一份，分离时内容自然带过去
    @Bindable var buffer: TextBuffer

    private var text: String {
        get { buffer.text }
        nonmutating set { buffer.text = newValue }
    }

    @State private var mode: Mode = .code

    /// 解析好的节点树；为空表示当前不是合法 JSON
    @State private var root: JSONNode?

    /// 树里被折叠的路径
    @State private var collapsed: Set<String> = []

    /// 树里选中行的路径
    @State private var selection: String?

    @State private var errorMessage: String?

    /// 缩进风格持久化：设置页里的「JSON 缩进」改的就是它
    @AppStorage(PluginSettingKey.JSONFormatter.indent) private var indent = 2

    /// 粘贴检测跳转时携带的初始文本
    @Environment(\.pluginContext) private var pluginContext

    /// 插件内搜索（树视图用它过滤字段）
    @Environment(PluginSearchQuery.self) private var search: PluginSearchQuery?

    private var searchText: String { search?.text ?? "" }

    /// 头部是否有真正的搜索框（分离窗口的兜底对象不算）
    private var hasHeaderSearch: Bool { search?.hasHeaderField == true }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider().opacity(0.3)

            content

            Divider().opacity(0.3)

            statusBar
        }
        .onAppear {
            loadInitialText()
            updateNavigationWants()
        }
        .onChange(of: mode) { _, _ in
            updateNavigationWants()
        }
        .onChange(of: text) { _, newValue in
            // 自动反转义：只在「当前不是合法 JSON、反转义后是」时才改写，避免和正常编辑打架
            let normalized = JSONFormatterLogic.autoUnescape(newValue)
            if normalized != newValue {
                text = normalized
                return
            }
            refresh()
        }
        .onChange(of: root) { _, newRoot in
            collapsed = newRoot.map(JSONTreeLayout.defaultCollapsed) ?? []
            selection = nil
        }
        // 在代码视图里开始搜索字段时自动切到树视图，否则搜索词无处可去
        .onChange(of: searchText) { _, newValue in
            if !newValue.isEmpty { mode = .tree }
        }
    }

    /// 只有树视图吃方向键与回车；代码视图要把它留给编辑器的光标与换行
    private func updateNavigationWants() {
        search?.wantsNavigation = hasHeaderSearch && mode == .tree
    }

    // MARK: - 内容区

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .code:
            TextEditor(text: $buffer.text)
                .font(DesignTokens.Typography.code)
                .scrollContentBackground(.hidden)
                .padding(DesignTokens.Spacing.sm)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .tree:
            if let root {
                JSONTreeView(
                    root: root,
                    query: searchText,
                    collapsed: $collapsed,
                    selection: $selection
                )
            } else {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "curlybraces")
                .font(DesignTokens.Typography.emptyStateIcon)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text("还不是合法的 JSON")
                .font(DesignTokens.Typography.rowTitle)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text("切到「代码」粘贴内容，或先点一下「反转义」")
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 工具栏

    private var toolbar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Button {
                format()
            } label: {
                Label("格式化", systemImage: "text.alignleft")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
                minimize()
            } label: {
                Label("压缩", systemImage: "arrow.down.right.and.arrow.up.left")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                unescape()
            } label: {
                Label("反转义", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("把 \\n、\\\"、\\uXXXX 等转义还原成正常内容")

            Button {
                EventBus.shared.post(CopyToClipboardEvent(text: text))
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                clear()
            } label: {
                Label("清空", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            if mode == .tree {
                Button {
                    collapsed = []
                } label: {
                    Label("展开全部", systemImage: "chevron.down.square")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("展开全部")

                Button {
                    if let root { collapsed = JSONTreeLayout.allCollapsed(root) }
                } label: {
                    Label("折叠全部", systemImage: "chevron.right.square")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("折叠全部")
            }

            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.rawValue) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 120)

            // 分段控件自带标签时会被挤成竖排的窄条（曾经的样式缺陷），
            // 所以标签自己写，控件只负责选择
            Text("缩进")
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Picker("", selection: $indent) {
                Text("2 空格").tag(2)
                Text("4 空格").tag(4)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 130)
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    // MARK: - 状态栏

    private var statusBar: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            if let root {
                Text("\(root.nodeCount) 个节点")
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            if !text.isEmpty {
                Text(JSONFormatterLogic.byteSize(text))
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            if let error = errorMessage {
                Text(error)
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.destructive)
            } else if root != nil {
                Text("有效 JSON")
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.success)
            }
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.xs)
    }

    // MARK: - 动作

    /// 从导航上下文读取初始输入（粘贴检测自动跳转场景），顺手反转义并格式化一次
    ///
    /// **带了初始文本就覆盖编辑器内容。** 缓冲区是插件级的、会跨次保留；若只在「空」时加载，
    /// 新粘贴进来的内容会被上一次的旧内容挡住。
    ///
    /// 只在「刚进来」时格式化：编辑中的每次按键都重排会把光标顶走，所以之后要用户自己点按钮。
    private func loadInitialText() {
        guard let query = pluginContext["query"], !query.isEmpty else {
            refresh()
            return
        }
        var initial = JSONFormatterLogic.autoUnescape(query)
        if let formatted = try? JSONFormatterLogic.prettyPrint(initial, indent: indent) {
            initial = formatted.text
        }
        text = initial
        refresh()
    }

    /// 重新解析当前文本并刷新错误 / 节点数 / 树
    private func refresh() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            root = nil
            errorMessage = nil
            return
        }
        do {
            root = try JSONFormatterLogic.parseTree(text)
            errorMessage = nil
        } catch {
            root = nil
            errorMessage = "无效的 JSON"
        }
    }

    private func format() {
        guard let result = try? JSONFormatterLogic.prettyPrint(text, indent: indent) else {
            errorMessage = "无效的 JSON"
            return
        }
        errorMessage = nil
        text = result.text
    }

    private func minimize() {
        guard let compact = try? JSONFormatterLogic.minify(text) else {
            errorMessage = "无效的 JSON"
            return
        }
        errorMessage = nil
        text = compact
    }

    private func unescape() {
        guard let decoded = try? JSONFormatterLogic.unescape(text) else {
            errorMessage = "无法反转义"
            return
        }
        errorMessage = nil
        text = decoded
    }

    private func clear() {
        text = ""
        root = nil
        collapsed = []
        selection = nil
        errorMessage = nil
    }
}
