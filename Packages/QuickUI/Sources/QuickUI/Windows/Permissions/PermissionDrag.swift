// PermissionDrag.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import SwiftUI

/// 拖进系统设置列表的权限
enum PermissionDragTarget: String {
    case accessibility
    case screenCapture

    var title: String {
        switch self {
        case .accessibility: "辅助功能"
        case .screenCapture: "屏幕录制"
        }
    }

    var hint: String {
        switch self {
        case .accessibility: "把下面的卡片拖进「辅助功能」列表，然后打开开关。"
        case .screenCapture: "把下面的卡片拖进「屏幕录制」列表，然后打开开关。"
        }
    }

    var settingsURL: URL? {
        switch self {
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .screenCapture:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        }
    }
}

/// 系统设置窗口的位置。用窗口列表反查，不申请辅助功能
enum SystemSettingsAnchor {
    private static let bundleIdentifier = "com.apple.systempreferences"
    /// 窄于这个宽度的是 sheet，不当成主窗口
    private static let minimumWidth: CGFloat = 400

    struct Target {
        let appKitFrame: CGRect
        let windowNumber: CGWindowID
        let level: Int
    }

    static func target() -> Target? {
        guard
            let pid =
                NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleIdentifier)
                .first(where: { !$0.isTerminated })?
                .processIdentifier
        else { return nil }

        guard
            let window = onScreenWindows()
                .first(where: { $0.ownerPID == pid && $0.frame.width >= minimumWidth })
        else { return nil }

        return Target(
            appKitFrame: appKitFrame(fromCG: window.frame),
            windowNumber: window.windowID,
            level: window.layer
        )
    }

    @discardableResult
    static func activate() -> Bool {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { !$0.isTerminated }?
            .activate() ?? false
    }

    static func appKitFrame(fromCG rect: CGRect) -> CGRect {
        let height =
            NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
            ?? NSScreen.main?.frame.height
            ?? 0
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    private struct ListedWindow {
        let windowID: CGWindowID
        let ownerPID: pid_t
        let layer: Int
        let frame: CGRect
    }

    private static func onScreenWindows() -> [ListedWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let selfPID = getpid()
        return raw.compactMap { entry in
            let layer = entry[kCGWindowLayer as String] as? Int ?? -1
            let alpha = entry[kCGWindowAlpha as String] as? Double ?? 0
            let ownerPID = entry[kCGWindowOwnerPID as String] as? Int32 ?? -1
            guard layer >= 0, layer <= 25, alpha > 0.01, ownerPID != selfPID else { return nil }
            guard let bounds = entry[kCGWindowBounds as String] as? [String: NSNumber] else { return nil }
            let frame = CGRect(
                x: bounds["X"]?.doubleValue ?? 0,
                y: bounds["Y"]?.doubleValue ?? 0,
                width: bounds["Width"]?.doubleValue ?? 0,
                height: bounds["Height"]?.doubleValue ?? 0
            )
            guard frame.width >= DesignTokens.Size.emptyStateIcon,
                frame.height >= DesignTokens.Size.emptyStateIcon
            else {
                return nil
            }
            return ListedWindow(
                windowID: entry[kCGWindowNumber as String] as? CGWindowID ?? 0,
                ownerPID: ownerPID,
                layer: layer,
                frame: frame
            )
        }
    }
}

/// 把面板贴到系统设置右侧内容区的正下方
enum PermissionSnapGeometry {

    /// 面板宽度：跟系统设置右侧内容区一样宽，再按屏幕收一收
    ///
    /// 内容区宽度 = 设置窗口宽度 − 侧边栏（`systemSettingsSidebar`）。以前这里还夹了一个
    /// `permissionPanelWidth` 的固定上限，导致面板比内容区窄一截、和系统设置的列表对不齐；
    /// 现在直接跟随内容区宽度（屏幕装不下时才收窄）。
    static func width(settings: CGRect, screen: CGRect) -> CGFloat {
        let sidebar = DesignTokens.Size.systemSettingsSidebar
        let inset = DesignTokens.Spacing.lg
        let contentWidth = max(0, settings.width - sidebar)
        return max(0, min(contentWidth, screen.width - inset * 2))
    }

    /// 面板落点：水平贴住内容区左缘，垂直贴在设置窗口正下方
    static func frame(
        settings: CGRect, screen: CGRect, panelWidth: CGFloat, panelHeight: CGFloat
    ) -> CGRect {
        let sidebar = DesignTokens.Size.systemSettingsSidebar
        let inset = DesignTokens.Spacing.lg
        let width = panelWidth
        let height = panelHeight
        var origin = CGPoint(x: settings.minX + sidebar, y: settings.minY - height)
        origin.x = max(screen.minX + inset, min(origin.x, screen.maxX - width - inset))
        origin.y = max(screen.minY + inset, min(origin.y, screen.maxY - height - inset))
        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }
}

/// 贴在系统设置下面、并跟它同一层级的授权面板
@MainActor
final class PermissionSnapPanel: NSPanel {
    private let hostingView: NSHostingView<AnyView>
    private let sizingView: NSHostingView<AnyView>
    private var settingsWindowNumber: CGWindowID?
    private static let draggingAlpha: CGFloat = 0.72

    init(content: some View) {
        let view = AnyView(content)
        hostingView = NSHostingView(rootView: view)
        sizingView = NSHostingView(rootView: view)
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: DesignTokens.Size.permissionPanelWidth,
                height: DesignTokens.Size.permissionPanelMinHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .normal
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        // 让宿主视图真去合成透明度：圆角裁掉的那部分要透出去，窗口阴影才会是圆角
        hostingView.wantsLayer = true
        hostingView.sizingOptions = []
        contentView = hostingView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// 拖卡片时鼠标穿透，松手才能落进下面的系统设置列表
    func setDraggingPassthrough(_ dragging: Bool) {
        ignoresMouseEvents = dragging
        alphaValue = dragging ? Self.draggingAlpha : 1
        guard let number = settingsWindowNumber else {
            dragging ? orderBack(nil) : orderFrontRegardless()
            return
        }
        order(dragging ? .below : .above, relativeTo: Int(number))
    }

    func snap(to target: SystemSettingsAnchor.Target) {
        level = NSWindow.Level(rawValue: target.level)
        settingsWindowNumber = target.windowNumber
        let screen =
            NSScreen.screens.first { $0.frame.intersects(target.appKitFrame) }?.visibleFrame
            ?? target.appKitFrame
        // 先按内容区定宽，再按这个宽度量高度（宽度会影响文字换行与卡片高度）
        let width = PermissionSnapGeometry.width(settings: target.appKitFrame, screen: screen)
        let height = measuredHeight(for: width)
        setFrame(
            PermissionSnapGeometry.frame(
                settings: target.appKitFrame, screen: screen, panelWidth: width, panelHeight: height),
            display: false
        )
        order(.above, relativeTo: Int(target.windowNumber))
    }

    private func measuredHeight(for width: CGFloat) -> CGFloat {
        sizingView.setFrameSize(NSSize(width: width, height: DesignTokens.Size.settingsWindow.height))
        sizingView.layoutSubtreeIfNeeded()
        return max(DesignTokens.Size.permissionPanelMinHeight, sizingView.fittingSize.height)
    }
}

/// 打开系统设置，并把卡片吸在设置窗口下面
@MainActor
final class PermissionDragController {
    static let shared = PermissionDragController()

    private var panel: PermissionSnapPanel?
    private var timer: Timer?
    private var isDraggingApp = false
    private var misses = 0
    private let missLimit = 8

    private init() {}

    func present(_ target: PermissionDragTarget) {
        close()
        if let url = target.settingsURL {
            NSWorkspace.shared.open(url)
        }
        SystemSettingsAnchor.activate()
        let appURL = Bundle.main.bundleURL
        panel = PermissionSnapPanel(
            content: PermissionDragSheet(
                target: target, appURL: appURL,
                onClose: { [weak self] in
                    self?.close()
                },
                onDragStateChange: { [weak self] dragging in
                    self?.isDraggingApp = dragging
                    self?.panel?.setDraggingPassthrough(dragging)
                })
        )
        panel?.orderFrontRegardless()
        startTracking()
    }

    func close() {
        timer?.invalidate()
        timer = nil
        panel?.close()
        panel = nil
        misses = 0
        isDraggingApp = false
    }

    private func startTracking() {
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    private func tick() {
        guard let target = SystemSettingsAnchor.target() else {
            misses += 1
            if misses >= missLimit { close() }
            return
        }
        misses = 0
        if !isDraggingApp {
            panel?.snap(to: target)
        }
        if !isDraggingApp, let panel, panel.ignoresMouseEvents {
            panel.setDraggingPassthrough(false)
        }
    }
}

/// 拖拽授权面板上的说明和卡片
private struct PermissionDragSheet: View {
    let target: PermissionDragTarget
    let appURL: URL
    let onClose: () -> Void
    let onDragStateChange: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            HStack {
                Text("拖拽授权 · \(target.title)")
                    .font(DesignTokens.Typography.rowTitle)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(DesignTokens.Typography.compactIcon)
                }
                .buttonStyle(.plain)
            }
            AppBundleDragCard(url: appURL, onDragStateChange: onDragStateChange)
            Text(target.hint)
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text("列表里如果已经有一行旧的 Quick，先删掉再拖进去。授权后回到这里点「重新检测」。")
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .padding(DesignTokens.Spacing.xl)
        // 宽度不再写死：由宿主窗口按系统设置内容区定宽，这里只负责铺满
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PaletteBackground())
        // 面板是无边框窗口，必须自己裁圆角 —— 否则 vibrancy 会铺满矩形四角，
        // 窗口阴影（取自 alpha 通道）也跟着变方。主面板/分离窗口同款做法。
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.panel, style: .continuous))
    }
}

/// 把本 App 的 .app 当文件拖出去。系统设置的隐私列表接受这种拖入
struct AppBundleDragCard: NSViewRepresentable {
    let url: URL
    var onDragStateChange: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> AppBundleDragSourceView {
        let view = AppBundleDragSourceView(url: url)
        view.onDragStateChange = onDragStateChange
        return view
    }

    func updateNSView(_ nsView: AppBundleDragSourceView, context: Context) {
        nsView.update(url: url)
        nsView.onDragStateChange = onDragStateChange
    }
}

final class AppBundleDragSourceView: NSView, NSDraggingSource {
    private var url: URL
    private let hostingView: NSHostingView<AnyView>
    private var mouseDownPoint: NSPoint?
    private var hasBegunDragging = false
    var onDragStateChange: (Bool) -> Void = { _ in }

    init(url: URL) {
        self.url = url
        hostingView = NSHostingView(rootView: AnyView(AppBundleDragCardContent(url: url)))
        super.init(frame: .zero)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(url: URL) {
        self.url = url
        hostingView.rootView = AnyView(AppBundleDragCardContent(url: url))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        return bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: DesignTokens.Size.headerHeight)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        hasBegunDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !hasBegunDragging, let mouseDownPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        guard hypot(current.x - mouseDownPoint.x, current.y - mouseDownPoint.y) > DesignTokens.Spacing.xs
        else { return }
        hasBegunDragging = true
        onDragStateChange(true)
        beginAppDrag(with: event)
    }

    func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
    ) {
        mouseDownPoint = nil
        hasBegunDragging = false
        onDragStateChange(false)
    }

    private func beginAppDrag(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: AppBundlePasteboardWriter(url: url))
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let side = DesignTokens.Size.emptyStateIcon
        icon.size = NSSize(width: side, height: side)
        let point = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(
            NSRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side),
            contents: icon
        )
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }
}

private final class AppBundlePasteboardWriter: NSObject, NSPasteboardWriting {
    private let url: URL
    init(url: URL) { self.url = url }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.fileURL, .URL, NSPasteboard.PasteboardType("NSFilenamesPboardType"), .string]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case .fileURL, .URL:
            return url.absoluteString
        case NSPasteboard.PasteboardType("NSFilenamesPboardType"):
            return [url.path]
        case .string:
            return url.path
        default:
            return nil
        }
    }
}

private struct AppBundleDragCardContent: View {
    let url: URL

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: DesignTokens.Size.emptyStateIcon, height: DesignTokens.Size.emptyStateIcon)
            Text(FileManager.default.displayName(atPath: url.path))
                .font(DesignTokens.Typography.rowTitle)
                .lineLimit(1)
            Spacer()
            Text("拖到列表里")
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .frame(height: DesignTokens.Size.headerHeight)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .fill(DesignTokens.Colors.controlSurface)
        )
        .allowsHitTesting(false)
    }
}
