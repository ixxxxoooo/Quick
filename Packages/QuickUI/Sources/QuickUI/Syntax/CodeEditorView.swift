// CodeEditorView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import SwiftUI

/// 带语法高亮、行号、逐行底色的**可编辑**代码编辑器
///
/// SwiftUI 的 `TextEditor` 做不到这些：属性不可控、行高不可控、没有行号槽，
/// 而且它在无边框非激活面板里打字会踩 AppKit 的智能替换路径。这里直接用原生 `NSTextView`：
///
/// - **打字时重新上色只改属性、不换字符**：光标、选区、输入法合成都不受影响
/// - `lineStates` 给某些行加红 / 绿底（文本对比用）
/// - `NSRulerView` 画行号
/// - **关闭软换行 + 固定行高**：左右两个编辑器因此能按行号严格对齐
public struct CodeEditorView: NSViewRepresentable {

    /// 一行的底色
    public enum LineState: Sendable, Equatable {
        case none
        case added
        case removed
    }

    @Binding public var text: String

    /// 语法高亮用的语言
    public let language: CodeLanguage

    /// 逐行状态，下标即行号（不足按 `.none` 处理）
    public let lineStates: [LineState]

    /// 固定行高（同一对编辑器必须一致）
    public let lineHeight: CGFloat

    /// 是否显示行号
    public let showsLineNumbers: Bool

    /// 垂直滚动同步（一对编辑器共用同一实例）
    public let scrollSync: EditorScrollSync?

    /// 在同步里扮演的角色
    public let syncRole: EditorScrollSync.Role

    public init(
        text: Binding<String>,
        language: CodeLanguage,
        lineStates: [LineState] = [],
        lineHeight: CGFloat = DesignTokens.Size.codeEditorLineHeight,
        showsLineNumbers: Bool = true,
        scrollSync: EditorScrollSync? = nil,
        syncRole: EditorScrollSync.Role = .leading
    ) {
        self._text = text
        self.language = language
        self.lineStates = lineStates
        self.lineHeight = lineHeight
        self.showsLineNumbers = showsLineNumbers
        self.scrollSync = scrollSync
        self.syncRole = syncRole
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        // 不软换行：长行走横向滚动，左右两栏才不会因为某一行折行而整体错位
        scrollView.hasHorizontalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(
            width: DesignTokens.Spacing.sm, height: DesignTokens.Spacing.xs)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        // 关掉会改写输入 / 依赖拼写服务的功能（非激活面板里它们还会引发越界异常）
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false

        textView.string = text
        context.coordinator.textView = textView
        context.coordinator.applyHighlight(force: true)

        if showsLineNumbers {
            let ruler = LineNumberRulerView(textView: textView, lineHeight: lineHeight)
            scrollView.verticalRulerView = ruler
            scrollView.hasVerticalRuler = true
            scrollView.rulersVisible = true
            context.coordinator.ruler = ruler
        }

        scrollSync?.attach(scrollView, role: syncRole)
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self

        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            context.coordinator.applyHighlight(force: true)
        } else {
            context.coordinator.applyHighlight(force: false)
        }
        scrollSync?.attach(scrollView, role: syncRole)
    }

    public static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        MainActor.assumeIsolated {
            coordinator.parent.scrollSync?.detach()
        }
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {

        var parent: CodeEditorView
        weak var textView: NSTextView?
        weak var ruler: LineNumberRulerView?

        /// 上次上色时的语言 / 逐行状态，用来跳过无谓的重排
        private var appliedLanguage: CodeLanguage?
        private var appliedStates: [CodeEditorView.LineState] = []

        init(_ parent: CodeEditorView) {
            self.parent = parent
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            applyHighlight(force: true)
        }

        /// 重新上色。`force` 为假时，语言与逐行状态都没变就直接返回
        func applyHighlight(force: Bool) {
            guard let textView, let storage = textView.textStorage else { return }
            let language = parent.language
            let states = parent.lineStates
            guard force || language != appliedLanguage || states != appliedStates else { return }
            appliedLanguage = language
            appliedStates = states

            let text = textView.string
            let fullRange = NSRange(location: 0, length: storage.length)
            let font = DesignTokens.Typography.codeNSFont
            let baseColor = NSColor(DesignTokens.Colors.textPrimary)

            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = parent.lineHeight
            paragraph.maximumLineHeight = parent.lineHeight
            paragraph.lineBreakMode = .byClipping

            let baseAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: baseColor,
                .paragraphStyle: paragraph
            ]

            let selectedRanges = textView.selectedRanges
            storage.beginEditing()
            // 只重置属性，不碰字符：光标与选区原地不动
            storage.setAttributes(baseAttributes, range: fullRange)

            for token in language.tokens(in: text) {
                let range = NSRange(token.range, in: text)
                guard range.location != NSNotFound, range.length > 0 else { continue }
                storage.addAttribute(
                    .foregroundColor,
                    value: NSColor(SyntaxHighlighter.color(for: token.kind)),
                    range: range
                )
            }

            applyLineBackgrounds(storage: storage, text: text, states: states)
            storage.endEditing()

            textView.typingAttributes = baseAttributes
            textView.selectedRanges = selectedRanges
            ruler?.needsDisplay = true
        }

        /// 给差异行加底色。范围包含行尾换行，让底色延续到该行文字末尾
        /// （关闭软换行后不会铺满整个视口宽度，这是接受的取舍）
        private func applyLineBackgrounds(
            storage: NSTextStorage, text: String, states: [CodeEditorView.LineState]
        ) {
            guard !states.isEmpty else { return }
            let nsText = text as NSString
            let total = nsText.length
            var location = 0

            for (index, line) in text.components(separatedBy: "\n").enumerated() {
                let length = (line as NSString).length
                let end = min(location + length + 1, total)
                let range = NSRange(location: location, length: max(0, end - location))
                if range.length > 0, let color = Self.background(for: state(states, index)) {
                    storage.addAttribute(.backgroundColor, value: color, range: range)
                }
                location += length + 1
                if location > total { break }
            }
        }

        private func state(_ states: [CodeEditorView.LineState], _ index: Int) -> CodeEditorView.LineState {
            index < states.count ? states[index] : .none
        }

        private static func background(for state: CodeEditorView.LineState) -> NSColor? {
            switch state {
            case .none: nil
            case .added: NSColor(DesignTokens.Colors.success).withAlphaComponent(0.12)
            case .removed: NSColor(DesignTokens.Colors.destructive).withAlphaComponent(0.12)
            }
        }
    }
}

// MARK: - 行号槽

/// 编辑器左侧的行号槽
///
/// 关闭软换行 + 固定行高之后，第 i 行（0 起）的顶部就在 `inset + i * lineHeight` ——
/// 行号直接按这个公式定位，不需要去问 TextKit 要行矩形。
final class LineNumberRulerView: NSRulerView {

    private weak var textView: NSTextView?
    private let lineHeight: CGFloat

    init(textView: NSTextView, lineHeight: CGFloat) {
        self.textView = textView
        self.lineHeight = lineHeight
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = DesignTokens.Size.codeEditorGutter
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override var requiredThickness: CGFloat { DesignTokens.Size.codeEditorGutter }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView else { return }

        let font = NSFont.monospacedDigitSystemFont(
            ofSize: max(9, DesignTokens.Typography.codeNSFont.pointSize - 3), weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(DesignTokens.Colors.textTertiary)
        ]

        let lineCount = max(1, textView.string.components(separatedBy: "\n").count)
        let inset = textView.textContainerInset.height
        let visible = textView.visibleRect
        let firstLine = max(0, Int((visible.minY - inset) / lineHeight))
        let lastLine = min(lineCount - 1, Int((visible.maxY - inset) / lineHeight))
        guard firstLine <= lastLine else { return }

        for index in firstLine...lastLine {
            let y = inset + CGFloat(index) * lineHeight
            let point = convert(NSPoint(x: 0, y: y), from: textView)
            let label = "\(index + 1)" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(
                at: NSPoint(
                    x: ruleThickness - size.width - DesignTokens.Spacing.sm,
                    y: point.y + (lineHeight - size.height) / 2
                ),
                withAttributes: attributes
            )
        }
    }
}
