// CalcInputView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickUI
import SwiftUI

/// 计算器的多行输入框（`NSTextView` 封装）
///
/// **为什么不用 `TextEditor`：**
/// - 计算器要把每行结果右侧对齐到对应输入行，编辑器和结果行必须共用**同一条固定行高**。
///   `TextEditor` 的内部行高与文字容器内边距都不可控，对齐只能靠猜数字，
///   面板一缩放或系统字号一变就散。
/// - `TextEditor` 在无边框非激活面板里打字会走 AppKit 的智能替换（双空格等）路径，
///   偶发 `NSRangeException` 崩溃。这里把智能替换、拼写检查全部关掉。
struct CalcInputView: NSViewRepresentable {

    /// 输入文本（与 `CalculatorView` 共享）
    @Binding var text: String

    /// 所有行共用的固定行高，必须与结果列一致
    let lineHeight: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay

        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textColor = NSColor(DesignTokens.Colors.textPrimary)
        textView.insertionPointColor = NSColor(DesignTokens.Colors.textPrimary)
        textView.textContainerInset = NSSize(
            width: DesignTokens.Spacing.md,
            height: DesignTokens.Spacing.xs
        )

        // 关掉所有会自动改写输入、依赖拼写服务的功能：表达式输入框不需要它们，
        // 而它们在非激活面板里会踩到 AppKit 的越界异常
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false

        textView.string = text
        applyLineHeight(to: textView)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        // 只在外部真的改了文本时才回写，避免打字过程中打断光标与选区
        guard textView.string != text else { return }
        textView.string = text
        applyLineHeight(to: textView)
    }

    /// 给每一行套上同一条固定行高，并与结果列对齐
    private func applyLineHeight(to textView: NSTextView) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight

        let attributes: [NSAttributedString.Key: Any] = [
            .font: DesignTokens.Typography.calculatorNSFont,
            .foregroundColor: NSColor(DesignTokens.Colors.textPrimary),
            .paragraphStyle: paragraph
        ]
        textView.font = DesignTokens.Typography.calculatorNSFont
        textView.typingAttributes = attributes
        textView.defaultParagraphStyle = paragraph

        if let storage = textView.textStorage, storage.length > 0 {
            storage.addAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: CalcInputView

        init(_ parent: CalcInputView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
