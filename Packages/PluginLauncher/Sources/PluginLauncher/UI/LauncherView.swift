// LauncherView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 启动器主视图
///
/// 显示应用搜索结果和收藏应用。
/// 作为面板的默认模式视图。
struct LauncherView: View {

    let plugin: LauncherPlugin

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Text("应用启动器")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .padding(.top, DesignTokens.Spacing.md)

            Text("在搜索框中输入应用名称即可快速启动")
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
