// SuperPanelToastView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 面板顶部的短暂反馈胶囊（复制成功等）
struct SuperPanelToastView: View {

    let message: String

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "checkmark")
                .font(DesignTokens.Typography.compactIcon)
            Text(message)
                .font(DesignTokens.Typography.compactKeyCap)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(
            Capsule().fill(DesignTokens.Colors.success)
        )
        .shadow(color: DesignTokens.Colors.success.opacity(0.3), radius: 6, y: 2)
    }
}
