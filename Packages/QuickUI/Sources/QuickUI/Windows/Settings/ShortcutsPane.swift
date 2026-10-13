// ShortcutsPane.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import SwiftUI

/// 全局快捷键
///
/// 上面是面板自己的系统键，只有「打开 / 隐藏面板」可以改，清空后退回 ⌥Space。
/// 下面是用户添加的命令绑定：左边录按键，右边选命令。没有添加过就空着，不把全部命令铺开。
struct ShortcutsPane: View {

    let dataSource: any CommandSettingsDataSource

    @State private var bindings: [SettingsCommandBinding] = []
    @State private var drafts: [DraftBinding] = []
    @State private var conflictNote: String?
    @State private var paletteKeycaps: [String] = []

    var body: some View {
        Form {
            Section {
                rebindableRow
                fixedRow("打开设置", keycaps: ["⌘", ","])
                fixedRow("关闭 / 返回", keycaps: ["Esc"])
                fixedRow("分离插件窗口", keycaps: ["⌘", "D"])
            } header: {
                Text("系统")
            } footer: {
                Text("录制时全局快捷键会暂时停用，避免误触发。Esc、方向键、回车、⌘W 和 ⌘, 是面板内部的键，不能改。")
            }

            Section {
                if bindings.isEmpty && drafts.isEmpty {
                    Text("暂无绑定。例：⌥B + 「百度搜索」→ 选中文字后一键搜索。")
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .padding(.vertical, DesignTokens.Spacing.xs)
                }
                ForEach(bindings) { row in
                    boundRow(row)
                }
                ForEach(drafts) { draft in
                    draftRow(draft)
                }
            } header: {
                HStack {
                    Text("插件绑定")
                    Spacer()
                    Button {
                        drafts.append(DraftBinding())
                    } label: {
                        Label("添加", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("添加一条新的快捷键绑定")
                }
            } footer: {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text("快捷键 + 关键字。输入关键字时支持模糊搜索，从候选列表中选择功能。")
                    if let conflictNote {
                        Text(conflictNote)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
    }

    /// 唤出主面板，清空会写回默认的 ⌥Space
    private var rebindableRow: some View {
        HStack {
            Text("打开 / 隐藏面板")
                .font(DesignTokens.Typography.rowTitle)
            Spacer()
            ShortcutRecorder(
                keycaps: paletteKeycaps,
                onRecord: { keyCode, modifiers in
                    let applied = dataSource.setCommandShortcut(
                        keyCode: keyCode,
                        carbonModifiers: modifiers,
                        for: CommandID.togglePalette
                    )
                    conflictNote = applied ? nil : "这个组合键已经绑给别的命令，没有改动。"
                    reload()
                },
                onClear: {
                    dataSource.clearCommandShortcut(for: CommandID.togglePalette)
                    conflictNote = nil
                    reload()
                }
            )
            .help("录制唤出面板的全局快捷键")
        }
    }

    /// 写死的面板键，只展示，不录制
    private func fixedRow(_ title: String, keycaps: [String]) -> some View {
        HStack {
            Text(title)
                .font(DesignTokens.Typography.rowTitle)
            Spacer()
            Text(keycaps.joined())
                .font(DesignTokens.Typography.keyCap)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .frame(height: DesignTokens.Size.barButtonHeight)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                        .fill(DesignTokens.Colors.controlSurface)
                )
        }
    }

    /// 已经保存的一条绑定
    private func boundRow(_ row: SettingsCommandBinding) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            ShortcutRecorder(
                keycaps: row.keycaps,
                onRecord: { keyCode, modifiers in
                    apply(keyCode: keyCode, modifiers: modifiers, commandID: row.id)
                },
                onClear: {
                    dataSource.clearCommandShortcut(for: row.id)
                    conflictNote = nil
                    reload()
                }
            )
            .help("录制快捷键")
            FuzzyKeywordField(
                text: row.wakeKeyword,
                placeholder: "输入关键字搜索命令",
                dataSource: dataSource
            ) { keyword in
                conflictNote = dataSource.retargetShortcut(from: row.id, keyword: keyword)
                reload()
            }
            removeButton {
                dataSource.clearCommandShortcut(for: row.id)
                conflictNote = nil
                reload()
            }
        }
    }

    /// 还没写进偏好的一行
    private func draftRow(_ draft: DraftBinding) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            ShortcutRecorder(
                keycaps: draft.keycaps,
                onRecord: { keyCode, modifiers in
                    let caps = dataSource.shortcutKeycaps(keyCode: keyCode, carbonModifiers: modifiers)
                    updateDraft(draft.id) { item in
                        item.keyCode = keyCode
                        item.carbonModifiers = modifiers
                        item.keycaps = caps
                    }
                    commitDraft(id: draft.id)
                },
                onClear: {
                    updateDraft(draft.id) { item in
                        item.keyCode = nil
                        item.carbonModifiers = nil
                        item.keycaps = nil
                    }
                }
            )
            .help("录制快捷键")
            FuzzyKeywordField(
                text: draft.keyword,
                placeholder: "输入关键字搜索命令",
                dataSource: dataSource
            ) { keyword in
                updateDraft(draft.id) { item in
                    item.keyword = keyword
                }
                commitDraft(id: draft.id)
            }
            removeButton {
                drafts.removeAll { $0.id == draft.id }
            }
        }
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(DesignTokens.Typography.compactIcon)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .buttonStyle(.plain)
        .help("移除这条绑定")
    }

    private func apply(keyCode: Int, modifiers: Int, commandID: String) {
        let applied = dataSource.setCommandShortcut(
            keyCode: keyCode, carbonModifiers: modifiers, for: commandID)
        conflictNote = applied ? nil : "这个组合键已经绑给别的命令，没有改动。"
        reload()
    }

    private func commitDraft(id: UUID) {
        guard let draft = drafts.first(where: { $0.id == id }) else { return }
        let keyword = draft.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let keyCode = draft.keyCode, let modifiers = draft.carbonModifiers, !keyword.isEmpty else {
            return
        }
        guard let resolved = dataSource.resolveKeyword(keyword) else {
            conflictNote = "没有唯一对上的关键字。写插件声明的唤醒词，或功能标题。"
            return
        }
        commit(keyCode: keyCode, modifiers: modifiers, commandID: resolved.id, draftID: id)
    }

    private func commit(keyCode: Int, modifiers: Int, commandID: String, draftID: UUID) {
        let applied = dataSource.setCommandShortcut(
            keyCode: keyCode, carbonModifiers: modifiers, for: commandID)
        if applied {
            drafts.removeAll { $0.id == draftID }
            conflictNote = nil
        } else {
            conflictNote = "这个组合键已经绑给别的命令，没有改动。"
        }
        reload()
    }

    private func updateDraft(_ id: UUID, _ change: (inout DraftBinding) -> Void) {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        change(&drafts[index])
    }

    private func reload() {
        bindings = dataSource.boundCommandBindings()
        paletteKeycaps = dataSource.togglePaletteKeycaps
    }
}

/// 还没落盘的一行绑定
private struct DraftBinding: Identifiable {
    let id = UUID()
    var keyCode: Int?
    var carbonModifiers: Int?
    var keycaps: [String]?
    var keyword = ""
}

/// 支持模糊搜索下拉候选的关键字输入框
///
/// 输入时实时模糊匹配可用命令，显示下拉列表供选择
struct FuzzyKeywordField: View {

    let text: String
    let placeholder: String
    let dataSource: any CommandSettingsDataSource
    let onSubmit: (String) -> Void

    @State private var draft: String
    @State private var isEditing = false
    @State private var suggestions: [SettingsCommandBinding] = []
    @State private var showSuggestions = false

    init(text: String, placeholder: String, dataSource: any CommandSettingsDataSource, onSubmit: @escaping (String) -> Void) {
        self.text = text
        self.placeholder = placeholder
        self.dataSource = dataSource
        self.onSubmit = onSubmit
        _draft = State(initialValue: text)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)

        VStack(alignment: .leading, spacing: 0) {
            KeywordTextField(text: $draft, isEditing: $isEditing, placeholder: placeholder, onSubmit: { value in
                showSuggestions = false
                onSubmit(value)
            })
            .frame(height: DesignTokens.Size.settingsGlyphColumn)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(DesignTokens.Colors.cardFill))
            .overlay(
                shape.strokeBorder(
                    isEditing ? Color.accentColor : DesignTokens.Colors.cardStroke, lineWidth: DesignTokens.Size.hairline)
            )
            .clipShape(shape)
            .animation(.easeOut(duration: DesignTokens.Duration.hover), value: isEditing)
            .onChange(of: text) { _, newValue in
                if !isEditing { draft = newValue }
            }
            .onChange(of: draft) { _, newValue in
                if isEditing {
                    suggestions = dataSource.fuzzyMatchCommands(newValue)
                    showSuggestions = !suggestions.isEmpty && !newValue.isEmpty
                }
            }
            .onChange(of: isEditing) { _, editing in
                if editing {
                    suggestions = dataSource.fuzzyMatchCommands(draft)
                    showSuggestions = !suggestions.isEmpty && !draft.isEmpty
                } else {
                    showSuggestions = false
                }
            }

            if showSuggestions {
                suggestionsList
            }
        }
    }

    private var suggestionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions) { suggestion in
                Button {
                    draft = suggestion.wakeKeyword
                    showSuggestions = false
                    onSubmit(suggestion.wakeKeyword)
                } label: {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Image(systemName: suggestion.icon)
                            .font(DesignTokens.Typography.inlineIcon)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .frame(width: DesignTokens.Size.settingsRowGlyph)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(suggestion.title)
                                .font(DesignTokens.Typography.rowTitle)
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                                .lineLimit(1)
                            if let subtitle = suggestion.subtitle {
                                Text(subtitle)
                                    .font(DesignTokens.Typography.compactKeyCap)
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(suggestion.pluginName)
                            .font(DesignTokens.Typography.compactKeyCap)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("选择「\(suggestion.title)」")
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                .fill(DesignTokens.Colors.cardFill)
                .shadow(color: .black.opacity(DesignTokens.Opacity.popoverShadow), radius: DesignTokens.Size.popoverShadowRadius, y: DesignTokens.Size.popoverShadowOffsetY)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                .strokeBorder(DesignTokens.Colors.cardStroke, lineWidth: DesignTokens.Size.hairlineThin)
        )
        .padding(.top, DesignTokens.Spacing.xxs)
    }
}

/// 点哪都把插入点放回开头
private final class CaretHomeTextField: NSTextField {

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard let editor = currentEditor() else { return }
        editor.selectedRange = NSRange(location: 0, length: 0)
    }
}

/// AppKit 背书的单行输入
private struct KeywordTextField: NSViewRepresentable {

    @Binding var text: String
    @Binding var isEditing: Bool
    let placeholder: String
    let onSubmit: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = CaretHomeTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .left
        field.font = .preferredFont(forTextStyle: .body)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.placeholderString = placeholder
        field.stringValue = text
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isEditing = $isEditing
        context.coordinator.onSubmit = onSubmit
        nsView.alignment = .left
        nsView.placeholderString = placeholder
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {

        var text: Binding<String>
        var isEditing: Binding<Bool>
        var onSubmit: (String) -> Void

        init(_ parent: KeywordTextField) {
            text = parent.$text
            isEditing = parent.$isEditing
            onSubmit = parent.onSubmit
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            isEditing.wrappedValue = true
            if let editor = field.currentEditor() {
                editor.selectedRange = NSRange(location: 0, length: 0)
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
            isEditing.wrappedValue = false
            onSubmit(field.stringValue)
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            control.window?.makeFirstResponder(nil)
            return true
        }
    }
}
