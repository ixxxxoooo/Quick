// FloatingCapsuleView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit

/// 悬浮胶囊上的一个功能按钮
///
/// 描述而已，不含行为 —— 谁提供窗口就把谁的动作插进来。
@MainActor
public struct CapsuleAction {

    /// 按钮的语气，决定悬停与激活时的配色
    public enum Kind {
        /// 普通按钮：悬停给一层淡底色
        case standard
        /// 危险按钮（关闭）：悬停时底色与图标转红
        case destructive
        /// 开关按钮（置顶）：开启后保持高亮
        case toggle
    }

    /// 胶囊内唯一标识，用于回写开关状态
    public let id: String

    /// SF Symbol 名称
    public let symbol: String

    /// 悬停提示
    public let tooltip: String

    /// 语气
    public let kind: Kind

    /// 点击回调
    public let handler: () -> Void

    public init(
        id: String,
        symbol: String,
        tooltip: String,
        kind: Kind = .standard,
        handler: @escaping () -> Void
    ) {
        self.id = id
        self.symbol = symbol
        self.tooltip = tooltip
        self.kind = kind
        self.handler = handler
    }
}

/// 独立窗口内的悬浮操作胶囊
///
/// 参考 Fasty 的 `capsuleInjectionScript`：叠在窗口内容之上、可拖到任意角落、
/// 默认收起只留抓手和展开箭头。窗口级别的控制（关闭 / 刷新 / 置顶）都收在这里，
/// 所以分离窗口既不需要系统红绿灯，也不需要在内容里再切一条工具栏。
///
/// 位置按 `positionKey` 持久化到 `UserDefaults`，下次打开同一个窗口回到原处。
///
/// 交互约定：
/// - 收起时整条胶囊可拖（展开箭头除外，它要保持可点）
/// - 展开后只能抓抓手拖，按钮区域留给按钮
/// - 位移小于阈值当作点击，避免手抖把胶囊挪走
public final class FloatingCapsuleView: NSView {

    // MARK: - 配置

    private let positionKey: String
    private let actions: [CapsuleAction]

    // MARK: - 状态

    private var isCollapsed = true
    private var isDragging = false
    private var dragOrigin: NSPoint = .zero
    private var frameOrigin: NSPoint = .zero

    // MARK: - 子视图

    private let backdrop = NSVisualEffectView()
    private let tintLayer = NSView()
    private let contentStack = NSStackView()
    private let actionsStack = NSStackView()
    private let gripView = CapsuleGripView()
    private var buttons: [String: CapsuleButtonView] = [:]
    private var toggleButton: CapsuleButtonView!

    /// 位置存储键前缀
    private static let positionKeyPrefix = "quick.capsule.pos."

    public init(positionKey: String, actions: [CapsuleAction]) {
        self.positionKey = Self.positionKeyPrefix + positionKey
        self.actions = actions
        super.init(frame: .zero)
        setupBackdrop()
        setupContent()
        applyCollapsedState(animated: false)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    // MARK: - 构建

    private func setupBackdrop() {
        wantsLayer = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor(DesignTokens.Colors.capsuleStroke).cgColor
        shadow = NSShadow()
        shadow?.shadowColor = NSColor.black.withAlphaComponent(0.18)
        shadow?.shadowBlurRadius = DesignTokens.Size.Capsule.shadowRadius
        shadow?.shadowOffset = NSSize(width: 0, height: -DesignTokens.Size.Capsule.shadowOffsetY)

        backdrop.material = .hudWindow
        backdrop.blendingMode = .withinWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.masksToBounds = true
        addSubview(backdrop)

        tintLayer.wantsLayer = true
        tintLayer.layer?.backgroundColor = NSColor(DesignTokens.Colors.capsuleFill).cgColor
        addSubview(tintLayer)
    }

    private func setupContent() {
        gripView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            gripView.widthAnchor.constraint(equalToConstant: DesignTokens.Size.Capsule.gripWidth),
            gripView.heightAnchor.constraint(equalToConstant: DesignTokens.Size.Capsule.gripHeight)
        ])

        actionsStack.orientation = .horizontal
        actionsStack.alignment = .centerY
        actionsStack.spacing = DesignTokens.Size.Capsule.itemSpacing
        actionsStack.translatesAutoresizingMaskIntoConstraints = false

        for action in actions {
            // 分组线：把窗口级操作（关闭）与功能操作分开，和 Fasty 的分隔线同一个位置
            if action.kind == .destructive, actionsStack.arrangedSubviews.isEmpty == false {
                actionsStack.addArrangedSubview(makeDivider())
            }
            let button = CapsuleButtonView(action: action)
            buttons[action.id] = button
            actionsStack.addArrangedSubview(button)
        }

        toggleButton = CapsuleButtonView(
            action: CapsuleAction(
                id: "toggle",
                symbol: "chevron.left",
                tooltip: "展开工具栏"
            ) { [weak self] in
                self?.toggleCollapsed()
            })

        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.spacing = DesignTokens.Size.Capsule.itemSpacing
        contentStack.addArrangedSubview(gripView)
        contentStack.addArrangedSubview(actionsStack)
        contentStack.addArrangedSubview(toggleButton)
        addSubview(contentStack)
    }

    private func makeDivider() -> NSView {
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(DesignTokens.Colors.capsuleStroke).cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            divider.widthAnchor.constraint(equalToConstant: DesignTokens.Size.Capsule.dividerWidth),
            divider.heightAnchor.constraint(equalToConstant: DesignTokens.Size.Capsule.dividerHeight)
        ])
        return divider
    }

    // MARK: - 布局

    /// 胶囊的自然尺寸（随展开状态变化）
    private var naturalSize: NSSize {
        let padding = DesignTokens.Size.Capsule.padding
        let height = DesignTokens.Size.Capsule.buttonSize + padding * 2
        let width = contentStack.fittingSize.width + padding * 2
        return NSSize(width: width, height: height)
    }

    public override func layout() {
        super.layout()
        let radius = bounds.height / 2
        layer?.cornerRadius = radius
        backdrop.frame = bounds
        backdrop.layer?.cornerRadius = radius
        backdrop.maskImage = Self.capsuleMask(size: bounds.size)
        tintLayer.frame = bounds
        tintLayer.layer?.cornerRadius = radius

        let padding = DesignTokens.Size.Capsule.padding
        contentStack.frame = NSRect(
            x: padding,
            y: padding,
            width: max(0, bounds.width - padding * 2),
            height: max(0, bounds.height - padding * 2)
        )
    }

    /// 全圆角遮罩（`border-radius: 9999px`）
    private static func capsuleMask(size: NSSize) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setFill()
        NSBezierPath(
            roundedRect: NSRect(origin: .zero, size: size),
            xRadius: size.height / 2,
            yRadius: size.height / 2
        ).fill()
        image.unlockFocus()
        return image
    }

    // MARK: - 对外

    /// 放进父视图：恢复上次的位置，或默认停在右上角
    public func positionInSuperview() {
        guard let superview else { return }
        let padding = DesignTokens.Size.Capsule.edgeInset

        let origin: NSPoint
        if let saved = UserDefaults.standard.dictionary(forKey: positionKey),
            let x = saved["x"] as? CGFloat, let y = saved["y"] as? CGFloat
        {
            origin = NSPoint(x: x, y: y)
        } else {
            origin = NSPoint(
                x: superview.bounds.width - frame.width - padding,
                y: superview.bounds.height - frame.height - padding
            )
        }
        // 两个分支都要夹：窗口比胶囊还小时，默认落点会算成负坐标而整块跑出窗外
        frame.origin = clampedOrigin(origin, in: superview.bounds.size)
    }

    /// 回写开关型按钮的状态（置顶）
    public func setToggle(_ actionID: String, isOn: Bool, tooltip: String? = nil) {
        guard let button = buttons[actionID] else { return }
        button.setOn(isOn, tooltip: tooltip)
    }

    // MARK: - 收起 / 展开

    private func toggleCollapsed() {
        isCollapsed.toggle()
        applyCollapsedState(animated: true)
    }

    private func applyCollapsedState(animated: Bool) {
        actionsStack.isHidden = isCollapsed
        toggleButton.updateGlyph(symbol: isCollapsed ? "chevron.left" : "chevron.right")
        toggleButton.toolTip = isCollapsed ? "展开工具栏" : "收起工具栏"

        let target = naturalSize
        var newFrame = frame
        newFrame.size = target
        if let superview {
            newFrame.origin = clampedOrigin(newFrame.origin, in: superview.bounds.size, size: target)
        }

        guard animated else {
            frame = newFrame
            layoutSubtreeIfNeeded()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = DesignTokens.Size.Capsule.animationDuration
            context.allowsImplicitAnimation = true
            self.animator().frame = newFrame
        }
        needsLayout = true
    }

    // MARK: - 拖拽

    public override func mouseDown(with event: NSEvent) {
        dragOrigin = convert(event.locationInWindow, from: nil)
        frameOrigin = frame.origin
        isDragging = false
    }

    public override func mouseDragged(with event: NSEvent) {
        // 展开状态下只能抓抓手拖：否则按住按钮划一下就会把胶囊带走
        if !isCollapsed, hitTest(dragOrigin) !== gripView { return }

        let current = convert(event.locationInWindow, from: nil)
        let dx = current.x - dragOrigin.x
        let dy = current.y - dragOrigin.y

        let threshold = DesignTokens.Size.Capsule.dragThreshold
        if !isDragging, abs(dx) > threshold || abs(dy) > threshold {
            isDragging = true
            alphaValue = 0.92
        }
        guard isDragging, let superview else { return }

        move(
            to: NSPoint(x: frameOrigin.x + dx, y: frameOrigin.y + dy),
            in: superview.bounds.size
        )
    }

    public override func mouseUp(with _: NSEvent) {
        guard isDragging else { return }
        alphaValue = 1
        persistPosition()
        isDragging = false
    }

    /// 把胶囊移到父视图坐标系里的某个原点，落点夹在父视图内
    ///
    /// 抽出来是为了能被测试直接驱动：拖拽的真实入口是 `NSEvent`，
    /// 而这段夹取逻辑才是会写坏位置的部分。
    func move(to origin: NSPoint, in container: NSSize) {
        frame.origin = clampedOrigin(origin, in: container)
    }

    /// 把当前位置写进 `UserDefaults`
    func persistPosition() {
        UserDefaults.standard.set(
            ["x": frame.origin.x, "y": frame.origin.y],
            forKey: positionKey
        )
    }

    /// 把原点夹进父视图，四周留出 `edgeInset`
    ///
    /// 优先保证左下不出界：窗口小到装不下整个胶囊时，宁可右边被裁掉一点，
    /// 也不能让它整块跑到窗外 —— 那就再也点不到了。
    private func clampedOrigin(_ origin: NSPoint, in container: NSSize, size: NSSize? = nil) -> NSPoint {
        let padding = DesignTokens.Size.Capsule.edgeInset
        let size = size ?? frame.size

        let minX = min(padding, max(0, container.width - size.width))
        let maxX = max(minX, container.width - size.width - padding)
        let minY = min(padding, max(0, container.height - size.height))
        let maxY = max(minY, container.height - size.height - padding)

        return NSPoint(
            x: min(max(minX, origin.x), maxX),
            y: min(max(minY, origin.y), maxY)
        )
    }

    // MARK: - 外观

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        tintLayer.layer?.backgroundColor = NSColor(DesignTokens.Colors.capsuleFill).cgColor
        layer?.borderColor = NSColor(DesignTokens.Colors.capsuleStroke).cgColor
        contentStack.subviews.forEach { $0.needsDisplay = true }
    }
}

// MARK: - 抓手

/// 胶囊左端的拖拽抓手（两列三点）
private final class CapsuleGripView: NSView {

    override var isFlipped: Bool { false }

    override func draw(_: NSRect) {
        let dot = DesignTokens.Size.Capsule.gripDotSize
        let gap = DesignTokens.Size.Capsule.gripDotSpacing
        let centerX = bounds.midX
        let centerY = bounds.midY

        NSColor(DesignTokens.Colors.capsuleGlyph).setFill()
        for column in 0..<2 {
            for row in 0..<3 {
                let origin = NSPoint(
                    x: centerX - gap / 2 + CGFloat(column) * gap - dot / 2,
                    y: centerY - gap + CGFloat(row) * gap - dot / 2
                )
                NSBezierPath(ovalIn: NSRect(origin: origin, size: NSSize(width: dot, height: dot))).fill()
            }
        }
    }
}

// MARK: - 按钮

/// 胶囊里的圆钮：22×22、悬停底色、开关高亮
private final class CapsuleButtonView: NSButton {

    private let capsuleAction: CapsuleAction
    private var isHovered = false
    private var isOn = false

    init(action: CapsuleAction) {
        self.capsuleAction = action
        super.init(frame: .zero)

        image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: action.tooltip)
        imageScaling = .scaleProportionallyDown
        isBordered = false
        bezelStyle = .accessoryBarAction
        toolTip = action.tooltip
        target = self
        self.action = #selector(handleTap)
        wantsLayer = true

        let size = DesignTokens.Size.Capsule.buttonSize
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size)
        ])
        layer?.cornerRadius = size / 2
        refreshAppearance()
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { fatalError() }

    func setOn(_ on: Bool, tooltip: String?) {
        isOn = on
        if let tooltip { self.toolTip = tooltip }
        refreshAppearance()
    }

    /// 换图标（展开 / 收起箭头要翻转方向）
    func updateGlyph(symbol: String) {
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)
    }

    @objc private func handleTap() {
        capsuleAction.handler()
    }

    // MARK: - 悬停

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            ))
    }

    override func mouseEntered(with _: NSEvent) {
        isHovered = true
        refreshAppearance()
    }

    override func mouseExited(with _: NSEvent) {
        isHovered = false
        refreshAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    private func refreshAppearance() {
        var fill: NSColor?
        var glyph = NSColor(DesignTokens.Colors.capsuleGlyph)

        if capsuleAction.kind == .toggle, isOn {
            fill = NSColor(DesignTokens.Colors.capsuleToggleFill)
            glyph = NSColor(DesignTokens.Colors.capsuleToggleGlyph)
        } else if isHovered {
            if capsuleAction.kind == .destructive {
                fill = NSColor(DesignTokens.Colors.capsuleCloseFill)
                glyph = NSColor(DesignTokens.Colors.capsuleCloseGlyph)
            } else {
                fill = NSColor(DesignTokens.Colors.capsuleHover)
                glyph = NSColor(DesignTokens.Colors.capsuleGlyphStrong)
            }
        }

        layer?.backgroundColor = fill?.cgColor
        contentTintColor = glyph
    }
}
