// WindowMover.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import ApplicationServices
import QuickCore

/// 窗口移动器
///
/// 使用 Accessibility API 移动和调整前台窗口。
/// 需要辅助功能权限。
@MainActor
final class WindowMover {

    private let log = QuickLog.module("windowmanager")

    /// 应用布局到前台窗口
    /// - Parameter layout: 窗口布局
    func apply(_ layout: WindowLayout) {
        guard AXIsProcessTrusted() else {
            // 常见原因：未在「系统设置 → 隐私与安全性 → 辅助功能」中勾选 Quick。
            log.error("缺少辅助功能权限，窗口布局未应用")
            return
        }

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let r = layout.rect

        let newFrame = CGRect(
            x: screenFrame.origin.x + screenFrame.width * r.x,
            y: screenFrame.origin.y + screenFrame.height * (1.0 - r.y - r.h),  // AppKit 坐标系
            width: screenFrame.width * r.w,
            height: screenFrame.height * r.h
        )

        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        var focusedWindow: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        guard let window = focusedWindow else { return }

        let windowElement = window as! AXUIElement

        // 设置位置
        var position = CGPoint(x: newFrame.origin.x, y: screenFrame.maxY - newFrame.maxY)
        if let posValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(windowElement, kAXPositionAttribute as CFString, posValue)
        }

        // 设置大小
        var size = CGSize(width: newFrame.width, height: newFrame.height)
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(windowElement, kAXSizeAttribute as CFString, sizeValue)
        }
    }
}
