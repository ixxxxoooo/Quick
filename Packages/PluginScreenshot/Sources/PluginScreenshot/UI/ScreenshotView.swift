// ScreenshotView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 截图插件视图
struct ScreenshotView: View {

    let capture: ScreenCapture

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xxl) {
            Image(systemName: "camera.viewfinder")
                .font(DesignTokens.Typography.emptyStateIcon)
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            Text("截图工具")
                .font(DesignTokens.Typography.panelTitle)

            HStack(spacing: DesignTokens.Spacing.xl) {
                screenshotButton("区域截图", icon: "rectangle.dashed") {
                    Task { await capture.captureArea() }
                }
                screenshotButton("全屏截图", icon: "rectangle.on.rectangle") {
                    Task { await capture.captureFullScreen() }
                }
                screenshotButton("延时截图 (3s)", icon: "timer") {
                    Task { await capture.captureWithDelay(3) }
                }
            }

            if let path = capture.lastCapturePath {
                Text("最近截图: \(path)")
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            Text(capture.savesToDesktop ? "截图将保存到桌面" : "截图将复制到剪贴板")
                .font(DesignTokens.Typography.keyCap)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .padding(DesignTokens.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func screenshotButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                Text(label)
                    .font(DesignTokens.Typography.keyCap)
            }
            .frame(width: 120, height: 80)
            .background(DesignTokens.Colors.cardFill)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
        }
        .buttonStyle(.plain)
    }
}
