// SettingsTileIcon.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 设置侧栏 / 行首的彩色色块图标
///
/// 对齐 Raycast Preferences：约 18pt 圆角色块 + Medium 白色 SF Symbol，
/// 顶部略亮的扁平渐变。本仓库禁止第三方图标库，视觉靠色块与精选符号完成。
public struct SettingsTileIcon: View {

    /// 色块语义色
    public enum Tint: Sendable {
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

    /// 构造一个彩色方块图标
    /// - Parameters:
    ///   - systemImage: SF Symbol 名称
    ///   - tint: 色块档位
    ///   - isEnabled: 关掉时降不透明度
    public init(systemImage: String, tint: Tint = .blue, isEnabled: Bool = true) {
        self.systemImage = systemImage
        self.tint = tint
        self.isEnabled = isEnabled
    }

    public var body: some View {
        Image(systemName: systemImage)
            .font(DesignTokens.Typography.settingsIconGlyphFont)
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
                            tint.color.opacity(0.96),
                            tint.color
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
