// DesignTokens.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuartzCore
import SwiftUI

/// 全局设计令牌系统
///
/// 参考 Tinycast Theme.swift，定义统一的颜色、间距、圆角、动画、字体令牌。
/// 所有 UI 组件统一引用此处的值，确保视觉一致性。
public enum DesignTokens {

    // MARK: - 间距

    public enum Spacing {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 6
        public static let md: CGFloat = 8
        public static let lg: CGFloat = 10
        public static let xl: CGFloat = 12
        public static let xxl: CGFloat = 20
        /// 分组标题下方间距
        public static let sectionHeaderBottom: CGFloat = 4
        /// 分组之间的间距
        public static let sectionSpacing: CGFloat = 12
    }

    // MARK: - 圆角

    public enum Radius {
        /// 面板圆角
        public static let panel: CGFloat = 26
        /// 列表行圆角
        public static let row: CGFloat = 10
        /// 菜单圆角
        public static let menu: CGFloat = 6
        /// 菜单面板圆角
        public static let menuPanel: CGFloat = 16
        /// 对话框圆角
        public static let dialog: CGFloat = 20
        /// 缩略图圆角
        public static let thumbnail: CGFloat = 6
        /// 卡片圆角
        public static let card: CGFloat = 10
        /// 快捷键帽圆角
        public static let keyCap: CGFloat = 6
        /// 控件按钮圆角
        public static let barControl: CGFloat = 8
    }

    // MARK: - 尺寸

    public enum Size {
        /// 面板默认宽度
        public static let panelWidth: CGFloat = 750
        /// 面板默认高度
        public static let panelHeight: CGFloat = 475
        /// 搜索栏高度
        public static let headerHeight: CGFloat = 44
        /// 搜索栏图标槽位宽度
        public static let headerIconSlot: CGFloat = 22
        /// 搜索栏上方内边距
        public static let headerPadding: CGFloat = 10
        /// 底栏高度
        public static let bottomBarHeight: CGFloat = 52
        /// 底栏按钮高度
        public static let barButtonHeight: CGFloat = 28
        /// 列表行图标尺寸
        public static let rowIcon: CGFloat = 24
        /// 快捷键帽尺寸
        public static let keyCap: CGFloat = 18
        /// HUD 最大宽度
        public static let hudMaxWidth: CGFloat = 420
        /// HUD 距屏幕底部距离
        public static let hudEdgeOffset: CGFloat = 48
        /// 对话框宽度
        public static let dialogWidth: CGFloat = 420
        /// 对话框图标尺寸
        public static let dialogIcon: CGFloat = 32
        /// 面板顶部占屏幕可见高度的比例
        public static let paletteTopMarginFraction: CGFloat = 0.18
        /// 设置窗口尺寸
        public static let settingsWindow = CGSize(width: 900, height: 700)
    }

    // MARK: - 动画时长

    public enum Duration {
        /// HUD 消息显示时长
        public static let messageHUD: TimeInterval = 2.4
        /// 面板进入动画
        public static let enter: TimeInterval = 0.18
        /// 面板退出动画
        public static let exit: TimeInterval = 0.12
        /// 悬停提示淡入淡出
        public static let tooltip: TimeInterval = 0.15
        /// 悬停高亮
        public static let hover: TimeInterval = 0.12
        /// 复制反馈
        public static let copyFeedback: TimeInterval = 1.2
    }

    // MARK: - 字体

    public enum Typography {
        /// 搜索框字体大小
        public static let searchFieldSize: CGFloat = 20
        /// 搜索框字体
        public static let searchField = Font.system(size: searchFieldSize, weight: .regular)
        /// 搜索栏图标字体
        public static let headerIcon = Font.system(size: 18, weight: .medium)
        /// 列表行标题
        public static let rowTitle = Font.body
        /// 列表行右侧文本
        public static let rowTrailing = Font.callout
        /// 分组标题
        public static let sectionHeader = Font.subheadline.weight(.medium)
        /// 面板标题
        public static let panelTitle = Font.headline
        /// 快捷键帽字体
        public static let keyCap = Font.caption
        /// 底栏按钮字体
        public static let bar = Font.callout.weight(.medium)
        /// 代码字体
        public static let code = Font.system(.callout, design: .monospaced)
        /// 行内代码
        public static let inlineCode = Font.body.monospaced()
    }

    // MARK: - 颜色

    public enum Colors {

        /// 自适应颜色（深色/浅色模式分别指定）
        public static func adaptive(dark: NSColor, light: NSColor) -> Color {
            Color(nsColor: NSColor(name: nil) {
                $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            })
        }

        /// 透明度渐变（深色用白墨、浅色用黑墨）
        public static func ramp(dark: Double, light: Double) -> Color {
            adaptive(
                dark: .srgbInk(1, alpha: dark),
                light: .srgbInk(0, alpha: light)
            )
        }

        /// 面板背景遮罩
        public static let panelScrim = adaptive(
            dark: .srgbInk(0, alpha: 0.40),
            light: .srgbInk(1, alpha: 0.55)
        )

        /// 选中行背景
        public static let selection = ramp(dark: 0.10, light: 0.09)

        /// 悬停行背景
        public static let rowHover = ramp(dark: 0.05, light: 0.045)

        /// 分隔线
        public static let separator = ramp(dark: 0.10, light: 0.12)

        /// 控件表面（快捷键帽等）
        public static let controlSurface = ramp(dark: 0.10, light: 0.08)

        /// 边框
        public static let border = ramp(dark: 0.20, light: 0.18)

        /// 主文本
        public static let textPrimary = ramp(dark: 1.0, light: 1.0)

        /// 次要文本
        public static let textSecondary = ramp(dark: 0.60, light: 0.60)

        /// 第三级文本
        public static let textTertiary = ramp(dark: 0.40, light: 0.42)

        /// 卡片填充
        public static let cardFill = ramp(dark: 0.05, light: 0.04)

        /// 卡片边框
        public static let cardStroke = ramp(dark: 0.10, light: 0.10)

        /// 毛玻璃霜面
        public static let glassFrost = adaptive(
            dark: .srgbInk(1, alpha: 0.05),
            light: .srgbInk(1, alpha: 0.25)
        )

        /// 危险操作色
        public static let destructive = Color.red

        /// 成功色
        public static let success = Color.green

        /// 进度色
        public static let progress = Color.blue
    }
}

// MARK: - NSColor 辅助扩展

public extension NSColor {

    /// 创建单通道灰色（0 = 黑，1 = 白）
    /// - Parameters:
    ///   - ink: 灰度值（0.0 ~ 1.0）
    ///   - alpha: 不透明度
    /// - Returns: NSColor
    static func srgbInk(_ ink: CGFloat, alpha: CGFloat) -> NSColor {
        NSColor(srgbRed: ink, green: ink, blue: ink, alpha: alpha)
    }
}

public extension NSAppearance {

    /// 判断当前外观是否为深色模式
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

// MARK: - View 扩展

public extension View {

    /// 毛玻璃控件表面效果
    func frosted(in shape: some Shape) -> some View {
        self
            .glassEffect(.regular.interactive().tint(DesignTokens.Colors.glassFrost), in: shape)
            .tint(.clear)
    }
}
