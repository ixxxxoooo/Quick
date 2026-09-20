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

    /// 自动消失定时器
    private var dismissTimer: Timer?

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
        hosting.setFrameSize(hosting.fittingSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
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
            let x = screenFrame.midX - hosting.fittingSize.width / 2
            let y = screenFrame.minY + DesignTokens.Size.hudEdgeOffset
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.alphaValue = 0
        panel.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = DesignTokens.Duration.enter
            panel.animator().alphaValue = 1
        }

        hudWindow = panel

        dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.dismiss()
            }
        }
    }

    /// 立即关闭 HUD
    public func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil

        guard let panel = hudWindow else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = DesignTokens.Duration.exit
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.hudWindow = nil
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
                .font(.system(size: 14, weight: .semibold))

            Text(message)
                .font(DesignTokens.Typography.bar)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl)
        .padding(.vertical, DesignTokens.Spacing.lg)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
        }
        .clipShape(Capsule())
        .frame(maxWidth: DesignTokens.Size.hudMaxWidth)
    }

    private var toneIcon: String {
        switch tone {
        case .success: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .danger: "xmark.circle.fill"
        }
    }

    private var toneColor: Color {
        switch tone {
        case .success: DesignTokens.Colors.success
        case .info: DesignTokens.Colors.progress
        case .warning: .orange
        case .danger: DesignTokens.Colors.destructive
        }
    }
}
