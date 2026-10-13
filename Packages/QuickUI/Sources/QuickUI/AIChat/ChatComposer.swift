// ChatComposer.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import SwiftUI

/// 对话输入框
///
/// 为什么不用 SwiftUI `TextEditor`：它没有「回车发送、Shift/Option+回车换行」这种聊天输入的
/// 标准行为，也不能随内容自动增高到上限再滚动，更没有占位文字。
/// 所以这里用 `NSTextView`，行为都在 `doCommandBy` 里收口。
///
/// **输入法**：拼音输入过程中的回车是「确认候选」，由输入法在 `doCommandBy` 之前消化，
/// 不会走到发送；这里额外用 `hasMarkedText()` 兜底。
struct ChatComposer: NSViewRepresentable {

    @Binding var text: String
    @Binding var height: CGFloat
    let placeholder: String
    /// 变化一次就抢一次焦点
    let focusToken: Int
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // 显式用 TextKit 1：下面要读 layoutManager 量内容高度，
        // 读它会把 TextKit 2 的文本视图悄悄降级，不如一开始就明确
        let textView = ComposerTextView(usingTextLayoutManager: false)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = DesignTokens.nsFont(.body)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        // 聊天里常贴代码：自动替换引号 / 破折号会悄悄改坏内容
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.placeholder = placeholder
        textView.setAccessibilityLabel("消息输入框")

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ComposerTextView else { return }
        context.coordinator.parent = self

        // 输入法组字中不能覆盖文本，否则候选会被打断
        if textView.string != text, !textView.hasMarkedText() {
            textView.string = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        textView.placeholder = placeholder
        context.coordinator.refreshHeight(of: textView)

        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            Task { @MainActor [weak textView] in
                guard let textView, let window = textView.window else { return }
                window.makeFirstResponder(textView)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatComposer
        var lastFocusToken: Int

        init(_ parent: ChatComposer) {
            self.parent = parent
            self.lastFocusToken = parent.focusToken - 1
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            refreshHeight(of: textView)
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                // 组字中的回车属于输入法
                if textView.hasMarkedText() { return false }
                let modifiers = NSApp.currentEvent?.modifierFlags ?? []
                if modifiers.contains(.shift) || modifiers.contains(.option) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    parent.onSubmit()
                }
                return true
            case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
                // Tab 在对话里没有意义；放行的话会往消息里插入制表符
                return true
            default:
                return false
            }
        }

        /// 量出内容高度并回写给 SwiftUI（夹在最小 / 最大高度之间）
        func refreshHeight(of textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                let container = textView.textContainer
            else { return }
            layoutManager.ensureLayout(for: container)
            let content = layoutManager.usedRect(for: container).height
            let clamped = min(
                max(content, DesignTokens.Size.aiChatComposerMinHeight),
                DesignTokens.Size.aiChatComposerMaxHeight)
            guard abs(parent.height - clamped) > 0.5 else { return }
            // 不能在视图更新过程中直接改 @State
            let binding = parent.$height
            Task { @MainActor in binding.wrappedValue = clamped }
        }
    }
}

/// 带占位文字的文本视图
final class ComposerTextView: NSTextView {

    var placeholder = "" {
        didSet { if oldValue != placeholder { needsDisplay = true } }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText(), !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? DesignTokens.nsFont(.body),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        (placeholder as NSString).draw(at: .zero, withAttributes: attributes)
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }
}
