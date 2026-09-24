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
                }
            } footer: {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text("快捷键 + 关键字。关键字就是功能本身，例如「剪贴板」「锁定屏幕」。一个插件可以有多条关键字，分别唤醒不同功能。")
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
            KeywordField(text: row.wakeKeyword, placeholder: "输入关键字") { keyword in
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
            KeywordField(text: draft.keyword, placeholder: "输入关键字") { keyword in
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

/// 右侧的关键字输入框。关键字就是要唤醒的功能
///
/// **这里用 `NSTextField` 而不是 SwiftUI 的 `TextField`。** 在 `Form` 里，`TextField` 的
/// 第一个参数会被当成**标签**真的画出来（一段 static text 贴左边），可编辑区只剩右边一截：
/// 表现就是「左边点不动、光标总在后面」，而且那段标签不随输入消失；`prompt:` 也治不好
/// 内容被排到尾部的问题（`.multilineTextAlignment(.leading)` 对单行 macOS 字段无效）。
/// 这个输入框要的是「内容居左、占位符在框内、点任意处都能聚焦、光标落最前」，直接下沉到
/// AppKit 最省事。
private struct KeywordField: View {

    let text: String
    let placeholder: String
    let onSubmit: (String) -> Void

    @State private var draft: String
    @State private var isEditing = false

    init(text: String, placeholder: String, onSubmit: @escaping (String) -> Void) {
        self.text = text
        self.placeholder = placeholder
        self.onSubmit = onSubmit
        _draft = State(initialValue: text)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)

        KeywordTextField(text: $draft, isEditing: $isEditing, placeholder: placeholder, onSubmit: onSubmit)
            .frame(height: 24)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 与左边的快捷键录制框同一套外观：`cardFill` 底 + `cardStroke` 边。
            .background(shape.fill(DesignTokens.Colors.cardFill))
            // 聚焦反馈：边框变强调色。系统聚焦圈被关掉了，不给这个的话点上去和没点
            // 几乎看不出区别（见 ShortcutRecorder 的录制态同款处理）。
            .overlay(
                shape.strokeBorder(
                    isEditing ? Color.accentColor : DesignTokens.Colors.cardStroke, lineWidth: 1)
            )
            .clipShape(shape)
            .animation(.easeOut(duration: DesignTokens.Duration.hover), value: isEditing)
            .onChange(of: text) { _, newValue in
                if !isEditing { draft = newValue }
            }
    }
}

/// 点哪都把插入点放回开头
///
/// `controlTextDidBeginEditing` 只赶上 Tab / 编程聚焦；鼠标点击是在它之后才按点击位置
/// 落插入点的，所以得在 `mouseDown` 之后再纠正一次。
private final class CaretHomeTextField: NSTextField {

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard let editor = currentEditor() else { return }
        editor.selectedRange = NSRange(location: 0, length: 0)
    }
}

/// AppKit 背书的单行输入：内容居左、占位符在字段内、聚焦时光标归位到最前
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

        /// 聚焦即把光标放到最前：无论点哪儿都从开头输入，而不是落在点击处
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

        /// 失焦时提交（切到别的行也不丢输入）
        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
            isEditing.wrappedValue = false
            onSubmit(field.stringValue)
        }

        /// 回车：结束编辑，提交交给 `controlTextDidEndEditing`
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
