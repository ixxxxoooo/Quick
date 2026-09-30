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

    /// 是否开启自动换行
    public let wrapLines: Bool

    /// 空内容时的占位提示
    public let placeholder: String

    /// 出现时是否自动取得第一响应者焦点
    public let autoFocus: Bool

    /// 用户在编辑器内执行粘贴（⌘V / 右键粘贴）后的回调
    public let onPaste: (() -> Void)?

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
        wrapLines: Bool = false,
        placeholder: String = "",
        autoFocus: Bool = false,
        onPaste: (() -> Void)? = nil,
        scrollSync: EditorScrollSync? = nil,
        syncRole: EditorScrollSync.Role = .leading
    ) {
        self._text = text
        self.language = language
        self.lineStates = lineStates
        self.lineHeight = lineHeight
        self.showsLineNumbers = showsLineNumbers
        self.wrapLines = wrapLines
        self.placeholder = placeholder
        self.autoFocus = autoFocus
        self.onPaste = onPaste
        self.scrollSync = scrollSync
        self.syncRole = syncRole
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.clipsToBounds = true
        scrollView.contentView.clipsToBounds = true

        // 显式构建 TextKit 1 栈（NSTextStorage → NSLayoutManager → NSTextContainer），
        // 避免 NSTextView 默认以 TextKit 2 启动后在行号绘制访问 layoutManager 时触发运行期降级导致图层分裂。
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(
            containerSize: NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        layoutManager.addTextContainer(textContainer)

        let textView = CodeEditorTextView(frame: .zero, textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(
            width: DesignTokens.Spacing.sm, height: DesignTokens.Spacing.xs)
        textView.isVerticallyResizable = true

        textView.placeholderString = placeholder
        textView.autoFocus = autoFocus
        let coordinator = context.coordinator
        textView.onPaste = { [weak coordinator] in
            coordinator?.handlePaste()
        }

        // 关掉会改写输入 / 依赖拼写服务的功能（非激活面板里它们还会引发越界异常）
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false

        scrollView.documentView = textView

        if showsLineNumbers {
            let ruler = LineNumberRulerView(
                textView: textView, lineHeight: lineHeight, wrapLines: wrapLines)
            scrollView.verticalRulerView = ruler
            scrollView.hasVerticalRuler = true
            scrollView.rulersVisible = true
            context.coordinator.ruler = ruler
            context.coordinator.observeClipView(scrollView.contentView)
        }

        Self.configureWrapping(textView: textView, wrapLines: wrapLines, in: scrollView)

        textView.string = text
        context.coordinator.textView = textView
        context.coordinator.applyHighlight(force: true)

        scrollSync?.attach(scrollView, role: syncRole)
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let previousWrapLines = context.coordinator.parent.wrapLines
        context.coordinator.parent = self

        guard let textView = scrollView.documentView as? NSTextView else { return }

        if let editorTextView = textView as? CodeEditorTextView {
            if editorTextView.placeholderString != placeholder {
                editorTextView.placeholderString = placeholder
                editorTextView.needsDisplay = true
            }
            editorTextView.autoFocus = autoFocus
        }

        if previousWrapLines != wrapLines {
            Self.configureWrapping(textView: textView, wrapLines: wrapLines, in: scrollView)
            context.coordinator.ruler?.wrapLines = wrapLines
            context.coordinator.applyHighlight(force: true)
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            textView.needsLayout = true
            textView.needsDisplay = true
            context.coordinator.ruler?.needsDisplay = true
        }

        if textView.string != text {
            textView.string = text
            Self.configureWrapping(textView: textView, wrapLines: wrapLines, in: scrollView)
            context.coordinator.applyHighlight(force: true)
            textView.needsDisplay = true
            context.coordinator.ruler?.needsDisplay = true
        } else if previousWrapLines == wrapLines {
            context.coordinator.applyHighlight(force: false)
        }
        scrollSync?.attach(scrollView, role: syncRole)
    }

    /// 配置换行与横向滚动行为
    static func configureWrapping(
        textView: NSTextView, wrapLines: Bool, in scrollView: NSScrollView
    ) {
        scrollView.hasHorizontalScroller = !wrapLines
        let clipWidth = max(scrollView.contentSize.width, 100)
        if wrapLines {
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.frame.size.width = clipWidth
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = NSSize(
                width: clipWidth,
                height: CGFloat.greatestFiniteMagnitude
            )
        } else {
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = []
            textView.maxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(
                width: 10_000_000,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
    }

    public static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        MainActor.assumeIsolated {
            coordinator.detachClipObserver()
            coordinator.parent.scrollSync?.detach()
        }
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {

        var parent: CodeEditorView
        weak var textView: NSTextView?
        weak var ruler: LineNumberRulerView?
        private var clipBoundsObserver: NSObjectProtocol?

        /// 上次上色时的语言 / 逐行状态 / 换行设置，用来跳过无谓的重排
        private var appliedLanguage: CodeLanguage?
        private var appliedStates: [CodeEditorView.LineState] = []
        private var appliedWrapLines: Bool?

        init(_ parent: CodeEditorView) {
            self.parent = parent
        }

        func observeClipView(_ clipView: NSClipView) {
            detachClipObserver()
            clipView.postsBoundsChangedNotifications = true
            clipView.postsFrameChangedNotifications = true
            clipBoundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.ruler?.needsDisplay = true
                }
            }
        }

        func detachClipObserver() {
            if let clipBoundsObserver {
                NotificationCenter.default.removeObserver(clipBoundsObserver)
                self.clipBoundsObserver = nil
            }
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            applyHighlight(force: true)
            textView.needsDisplay = true
        }

        /// 处理编辑器内粘贴事件：调用外部回调，并同步可能被原地改写后的文本
        func handlePaste() {
            parent.onPaste?()
            if let textView, textView.string != parent.text {
                textView.string = parent.text
                if let scrollView = textView.enclosingScrollView {
                    CodeEditorView.configureWrapping(
                        textView: textView, wrapLines: parent.wrapLines, in: scrollView)
                }
                applyHighlight(force: true)
                textView.needsDisplay = true
                ruler?.needsDisplay = true
            }
        }

        /// 重新上色。`force` 为假时，语言与逐行状态都没变就直接返回
        func applyHighlight(force: Bool) {
            guard let textView, let storage = textView.textStorage else { return }
            let language = parent.language
            let states = parent.lineStates
            let wrapLines = parent.wrapLines
            guard force || language != appliedLanguage || states != appliedStates
                || wrapLines != appliedWrapLines
            else { return }
            appliedLanguage = language
            appliedStates = states
            appliedWrapLines = wrapLines

            let text = textView.string
            let fullRange = NSRange(location: 0, length: storage.length)
            let font = DesignTokens.Typography.codeNSFont
            let baseColor = NSColor(DesignTokens.Colors.textPrimary)

            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = parent.lineHeight
            paragraph.maximumLineHeight = parent.lineHeight
            paragraph.lineBreakMode = wrapLines ? .byCharWrapping : .byClipping

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

// MARK: - 自定义 NSTextView（粘贴回调 + 占位提示 + 自动聚焦 + 换行宽度同步）

final class CodeEditorTextView: NSTextView {

    var onPaste: (() -> Void)?
    var placeholderString: String = ""
    var autoFocus: Bool = false
    private var didAutoFocus = false
    private var isHandlingPaste = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard autoFocus, !didAutoFocus, let window else { return }
        didAutoFocus = true
        Task { @MainActor [weak self, weak window] in
            guard let self, let window else { return }
            window.makeFirstResponder(self)
        }
    }

    override func layout() {
        if textContainer?.widthTracksTextView == true,
            let clipWidth = enclosingScrollView?.contentSize.width,
            clipWidth > 0,
            abs(frame.width - clipWidth) > 0.5
        {
            setFrameSize(NSSize(width: clipWidth, height: frame.height))
            textContainer?.containerSize = NSSize(
                width: clipWidth,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
        super.layout()
    }

    override func paste(_ sender: Any?) {
        if isHandlingPaste {
            super.paste(sender)
            return
        }
        isHandlingPaste = true
        super.paste(sender)
        isHandlingPaste = false
        onPaste?()
    }

    override func pasteAsPlainText(_ sender: Any?) {
        if isHandlingPaste {
            super.pasteAsPlainText(sender)
            return
        }
        isHandlingPaste = true
        super.pasteAsPlainText(sender)
        isHandlingPaste = false
        onPaste?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderString.isEmpty else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = DesignTokens.Size.codeEditorLineHeight
        paragraph.maximumLineHeight = DesignTokens.Size.codeEditorLineHeight
        let attributes: [NSAttributedString.Key: Any] = [
            .font: DesignTokens.Typography.codeNSFont,
            .foregroundColor: NSColor(DesignTokens.Colors.textTertiary),
            .paragraphStyle: paragraph
        ]
        let inset = textContainerInset
        let padding = textContainer?.lineFragmentPadding ?? 5
        let point = NSPoint(x: inset.width + padding, y: inset.height)
        (placeholderString as NSString).draw(at: point, withAttributes: attributes)
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
    var wrapLines: Bool

    init(textView: NSTextView, lineHeight: CGFloat, wrapLines: Bool = false) {
        self.textView = textView
        self.lineHeight = lineHeight
        self.wrapLines = wrapLines
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = DesignTokens.Size.codeEditorGutter
        clipsToBounds = true
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override var requiredThickness: CGFloat { DesignTokens.Size.codeEditorGutter }

    /// 自定义绘制：不调用 `super.draw(_:)`，因为 `NSRulerView` 默认以非翻转坐标画边框竖线，
    /// 在 `isFlipped = true` 时会导致竖线向上偏移超出 `NSScrollView` 捅穿顶部工具栏。
    override func draw(_ dirtyRect: NSRect) {
        drawHashMarksAndLabels(in: dirtyRect)

        let hairline = DesignTokens.Size.hairline
        let separatorRect = NSRect(
            x: bounds.maxX - hairline,
            y: bounds.minY,
            width: hairline,
            height: bounds.height
        )
        NSColor(DesignTokens.Colors.separator).setFill()
        separatorRect.fill()
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView else { return }

        let font = NSFont.monospacedDigitSystemFont(
            ofSize: max(9, DesignTokens.Typography.codeNSFont.pointSize - 3), weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(DesignTokens.Colors.textTertiary)
        ]

        let inset = textView.textContainerInset.height

        if !wrapLines {
            let lineCount = max(1, textView.string.components(separatedBy: "\n").count)
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
        } else {
            guard let layoutManager = textView.layoutManager,
                let textContainer = textView.textContainer
            else { return }
            let nsString = textView.string as NSString
            let stringLength = nsString.length

            if stringLength == 0 {
                let point = convert(NSPoint(x: 0, y: inset), from: textView)
                let label = "1" as NSString
                let size = label.size(withAttributes: attributes)
                label.draw(
                    at: NSPoint(
                        x: ruleThickness - size.width - DesignTokens.Spacing.sm,
                        y: point.y + (lineHeight - size.height) / 2
                    ),
                    withAttributes: attributes
                )
                return
            }

            let visibleRect = textView.visibleRect
            let visibleGlyphRange = layoutManager.glyphRange(
                forBoundingRect: visibleRect, in: textContainer)
            let visibleCharRange = layoutManager.characterRange(
                forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

            // 计算 visibleCharRange 起始处的行号与字符位置
            var lineNum = 1
            var pos = 0
            let targetPos = min(visibleCharRange.location, stringLength)

            while pos < targetPos {
                var lineStart = 0
                var lineEnd = 0
                var contentsEnd = 0
                nsString.getLineStart(
                    &lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                    for: NSRange(location: pos, length: 0))
                if lineEnd <= pos { break }
                pos = lineEnd
                if pos <= targetPos {
                    lineNum += 1
                }
            }

            let maxCharPos = min(NSMaxRange(visibleCharRange), stringLength)
            while pos < stringLength && pos <= maxCharPos {
                var lineStart = 0
                var lineEnd = 0
                var contentsEnd = 0
                nsString.getLineStart(
                    &lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                    for: NSRange(location: pos, length: 0))

                let glyphIndex = layoutManager.glyphIndexForCharacter(at: pos)
                let lineFragmentRect = layoutManager.lineFragmentRect(
                    forGlyphAt: glyphIndex, effectiveRange: nil)
                let y = lineFragmentRect.origin.y + inset
                let point = convert(NSPoint(x: 0, y: y), from: textView)

                let label = "\(lineNum)" as NSString
                let size = label.size(withAttributes: attributes)
                label.draw(
                    at: NSPoint(
                        x: ruleThickness - size.width - DesignTokens.Spacing.sm,
                        y: point.y + (lineHeight - size.height) / 2
                    ),
                    withAttributes: attributes
                )

                lineNum += 1
                if lineEnd <= pos { break }
                pos = lineEnd
            }

            if layoutManager.extraLineFragmentRect.height > 0 {
                let y = layoutManager.extraLineFragmentRect.origin.y + inset
                let point = convert(NSPoint(x: 0, y: y), from: textView)
                let label = "\(lineNum)" as NSString
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
}
