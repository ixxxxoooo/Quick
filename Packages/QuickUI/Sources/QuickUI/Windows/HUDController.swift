// HUDController.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import SwiftUI

/// 轻量 HUD 消息控制器
///
/// 在屏幕底部显示短暂的操作反馈消息（如"已复制"、"操作成功"）。
/// 参考 Tinycast 的 MessageHUDController。
@MainActor
public final class HUDController {

    /// 当前显示的 HUD 窗口
    private var hudWindow: NSPanel?

    /// 自动消失任务
    ///
    /// 用 `Task` 而不是 `Timer`：取消是即时的，所以连续两次 `show()` 时，
    /// 上一个 HUD 的延时不会把新 HUD 提前关掉。
    private var dismissTask: Task<Void, Never>?

    private let log = QuickLog.ui

    public init() {}

    /// 显示 HUD 消息
    /// - Parameters:
    ///   - message: 消息内容
    ///   - tone: 消息语气
    ///   - duration: 显示时长（秒）
    public func show(
        message: String,
        tone: HUDTone = .success,
        duration: TimeInterval = DesignTokens.Duration.messageHUD
    ) {
        dismiss()

        let hudView = HUDMessageView(message: message, tone: tone)
        let hosting = NSHostingView(rootView: hudView)
        // 尺寸**向上**取整，不能直接用 `fittingSize`。
        //
        // fittingSize 是小数（例如「已复制」量出来是 110.5×40.5），而窗口 frame 会落到整数上，
        // 少掉的这半个点正好让末字排不下 —— SwiftUI 的截断是整段的：不会只丢掉一个字，
        // 而是直接退成「已…」。表现就是提示框里只剩一个字加省略号，右边还空着一大块。
        let fitting = hosting.fittingSize
        let size = NSSize(width: ceil(fitting.width), height: ceil(fitting.height))
        hosting.setFrameSize(size)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting

        // 定位到主屏幕底部居中
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - size.width / 2
            let y = screenFrame.minY + DesignTokens.Size.hudEdgeOffset
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            log.warning("找不到主屏幕，HUD 位置未调整")
        }

        panel.alphaValue = 0
        panel.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = DesignTokens.Duration.enter
            panel.animator().alphaValue = 1
        }

        hudWindow = panel
        log.debug(
            "HUD 已显示，tone=\(tone.logName, privacy: .public)，停留 \(duration, format: .fixed(precision: 1)) s")

        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    /// 立即关闭 HUD
    public func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil

        guard let panel = hudWindow else { return }
        hudWindow = nil

        NSAnimationContext.runAnimationGroup { context in
            context.duration = DesignTokens.Duration.exit
            panel.animator().alphaValue = 0
        } completionHandler: {
            // 完成回调不在主 actor 上，收窗口必须显式跳回去。
            Task { @MainActor in
                panel.orderOut(nil)
            }
        }
    }
}

// MARK: - HUDTone 日志名

extension HUDTone {
    /// 日志里用的稳定短名（英文，便于过滤）
    fileprivate var logName: String {
        switch self {
        case .success: "success"
        case .info: "info"
        case .warning: "warning"
        case .danger: "danger"
        }
    }
}

// MARK: - HUD 消息视图

/// HUD 消息的 SwiftUI 视图
struct HUDMessageView: View {
    let message: String
    let tone: HUDTone

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: toneIcon)
                .foregroundStyle(toneColor)
                .font(DesignTokens.Typography.hudIcon)

            Text(message)
                .font(DesignTokens.Typography.bar)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl)
        .padding(.vertical, DesignTokens.Spacing.lg)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
        }
        .clipShape(Capsule())
        .frame(maxWidth: DesignTokens.Size.hudMaxWidth)
        // 永远按自己的理想尺寸绘制，不跟着窗口收缩。
        //
        // 窗口的宽高是用 `fittingSize` 定出来的，而它的小数部分最后会落到整数上；差的这不到
        // 一个点足以让末字排不下，而 SwiftUI 的截断是整段的 —— 不会只丢一个字，会直接退成
        // 「已…」。定尺寸时向上取整是第一条防线（见 `HUDController.show`），这里是第二条：
        // 真差一点时宁可让胶囊边缘被裁掉半像素，也不要把文案截掉。
        .fixedSize()
    }

    private var toneIcon: String {
        switch tone {
        case .success: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .danger: "exclamationmark.circle.fill"
        }
    }

    private var toneColor: Color {
        switch tone {
        case .success: DesignTokens.Colors.success
        case .info: DesignTokens.Colors.progress
        case .warning: DesignTokens.Colors.warning
        case .danger: DesignTokens.Colors.destructive
        }
    }
}
