// SettingsTileIcon.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 设置侧栏 / 行首的彩色色块图标
///
/// 对齐 macOS「系统设置」与 Raycast Preferences：小圆角色块 + 白色 SF Symbol。
/// 本仓库禁止第三方图标库，视觉升级靠精选 SF Symbols + 色块渲染完成。
struct SettingsTileIcon: View {

    /// 色块语义色
    enum Tint: Sendable {
        case blue, indigo, purple, pink, red, orange, yellow, green, mint, teal, cyan, gray, brown

        var color: Color {
            switch self {
            case .blue: DesignTokens.Colors.SettingsIcon.blue
            case .indigo: DesignTokens.Colors.SettingsIcon.indigo
            case .purple: DesignTokens.Colors.SettingsIcon.purple
            case .pink: DesignTokens.Colors.SettingsIcon.pink
            case .red: DesignTokens.Colors.SettingsIcon.red
            case .orange: DesignTokens.Colors.SettingsIcon.orange
            case .yellow: DesignTokens.Colors.SettingsIcon.yellow
            case .green: DesignTokens.Colors.SettingsIcon.green
            case .mint: DesignTokens.Colors.SettingsIcon.mint
            case .teal: DesignTokens.Colors.SettingsIcon.teal
            case .cyan: DesignTokens.Colors.SettingsIcon.cyan
            case .gray: DesignTokens.Colors.SettingsIcon.gray
            case .brown: DesignTokens.Colors.SettingsIcon.brown
            }
        }
    }

    let systemImage: String
    var tint: Tint = .blue
    var isEnabled: Bool = true

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: DesignTokens.Size.settingsIconGlyph, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.white)
            .frame(
                width: DesignTokens.Size.settingsIconTile,
                height: DesignTokens.Size.settingsIconTile
            )
            .background {
                RoundedRectangle(
                    cornerRadius: DesignTokens.Radius.settingsIconTile, style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [
                            tint.color,
                            tint.color.opacity(0.78)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .opacity(isEnabled ? 1 : 0.45)
            .accessibilityHidden(true)
    }
}
