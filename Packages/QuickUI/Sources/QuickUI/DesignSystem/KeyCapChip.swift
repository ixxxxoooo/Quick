// KeyCapChip.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 单个快捷键帽
///
/// 用来展示一个键位，例如底栏的 `↵` / `esc`，或列表行右侧的提示。
/// 数值全部来自 `DesignTokens`，不要在调用处再套 `.frame`。
public struct KeyCapChip: View {

    /// 帽的样式
    public enum Style {
        /// 实底填充 —— 底栏等「亮」的位置
        case filled
        /// 描边 —— 列表行等「轻」的位置
        case outline
    }

    /// 帽的尺寸档位
    ///
    /// 只有两档，避免出现第三个几乎一样的大小。
    public enum Scale {
        /// 紧凑（`Size.compactKeyCap`），用于底栏密集提示
        case compact
        /// 标准（`Size.keyCap`），用于列表行
        case standard

        var side: CGFloat {
            switch self {
            case .compact: DesignTokens.Size.compactKeyCap
            case .standard: DesignTokens.Size.keyCap
            }
        }

        var font: Font {
            switch self {
            case .compact: DesignTokens.Typography.compactKeyCap
            case .standard: DesignTokens.Typography.keyCap
            }
        }
    }

    public let text: String
    public var style: Style
    public var scale: Scale

    /// "↵" 在不同字体里的基线位置偏高，需要单独往下压一点点。
    private static let returnGlyphDrop: CGFloat = 1.1

    /// 初始化快捷键帽
    /// - Parameters:
    ///   - text: 键位文本，如 `↵`、`esc`、`⌘K`
    ///   - style: 样式，默认实底
    ///   - scale: 尺寸档位，默认标准
    public init(text: String, style: Style = .filled, scale: Scale = .standard) {
        self.text = text
        self.style = style
        self.scale = scale
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.keyCap, style: .continuous)

        Text(text)
            .font(scale.font)
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .offset(y: text == "↵" ? Self.returnGlyphDrop : 0)
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .frame(minWidth: scale.side, minHeight: scale.side)
            .background {
                switch style {
                case .filled:
                    shape.fill(DesignTokens.Colors.controlSurface)
                case .outline:
                    shape.strokeBorder(
                        DesignTokens.Colors.border,
                        lineWidth: DesignTokens.Size.hairline
                    )
                }
            }
    }
}
