// DesignTokens.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuartzCore
import SwiftUI

/// 全局设计令牌系统
///
/// 参考 Tinycast Theme.swift，定义统一的颜色、间距、圆角、动画、字体令牌。
/// 所有 UI 组件统一引用此处的值，确保视觉一致性。
///
/// 数值分两层：**基础值**（1.0 档，即 Tinycast 的原始令牌）与
/// **实际值**（基础值 × `panelScale`）。改尺寸只动 `panelScale` 一处。
public enum DesignTokens {

    // MARK: - 缩放

    /// 面板几何的整体缩放
    ///
    /// - `1.0` = 基础令牌：面板 750×475，圆角 26
    /// - `1.1` = **当前采用**：面板 825×523，圆角 29
    ///
    /// 为什么是 1.1：设计基准截图实测 1650×1046 物理像素，而 macOS 截图是 2x，
    /// 所以逻辑尺寸是 825×523 —— 恰好是基础值在两个维度上各乘 1.1，
    /// 对应 Tinycast 用户可选的「Large」档（它提供 Default 1.0 / Large 1.1 / Larger 1.2）。
    /// 换句话说：设计基准不是默认档，这里跟着基准走。
    ///
    /// 只缩放**面板与它的浮动兄弟**（HUD、对话框）。设置窗口这类系统窗口不缩放，
    /// 与 Tinycast 的做法一致。想换档只改这一个数字。
    public static let panelScale: CGFloat = 1.1

    /// 按 `panelScale` 取整缩放
    ///
    /// 取整是必需的：小数会让行高、快捷键帽的边角落到半像素上，边缘发虚。
    static func scaled(_ value: CGFloat) -> CGFloat {
        panelScale == 1 ? value : (value * panelScale).rounded()
    }

    // MARK: - 间距

    public enum Spacing {
        public static let xxs = scaled(2)
        public static let xs = scaled(4)
        public static let sm = scaled(6)
        public static let md = scaled(8)
        public static let lg = scaled(10)
        public static let xl = scaled(12)
        public static let xxl = scaled(20)
        /// 分组标题下方间距
        public static let sectionHeaderBottom = scaled(4)
        /// 分组之间的间距
        public static let sectionSpacing = scaled(12)
    }

    // MARK: - 圆角

    public enum Radius {
        /// 面板圆角
        public static let panel = scaled(26)
        /// 列表行圆角
        public static let row = scaled(10)
        /// 菜单圆角
        public static let menu = scaled(6)
        /// 菜单面板圆角
        public static let menuPanel = scaled(16)
        /// 对话框圆角
        public static let dialog = scaled(20)
        /// 缩略图圆角
        public static let thumbnail = scaled(6)
        /// 卡片圆角
        public static let card = scaled(10)
        /// 快捷键帽圆角
        public static let keyCap = scaled(6)
        /// 控件按钮圆角
        public static let barControl = scaled(8)
    }

    // MARK: - 尺寸

    public enum Size {
        /// 面板默认宽度
        public static let panelWidth = scaled(750)
        /// 面板默认高度
        public static let panelHeight = scaled(475)
        /// 搜索栏高度
        public static let headerHeight = scaled(44)
        /// 搜索栏图标槽位宽度
        public static let headerIconSlot = scaled(22)
        /// 搜索栏上方内边距
        public static let headerPadding = scaled(10)
        /// 底栏高度
        public static let bottomBarHeight = scaled(52)
        /// 底栏按钮高度
        public static let barButtonHeight = scaled(28)
        /// 列表行图标尺寸
        public static let rowIcon = scaled(24)
        /// 快捷键帽尺寸
        public static let keyCap = scaled(18)
        /// 紧凑快捷键帽尺寸（底栏密集提示用）
        public static let compactKeyCap = scaled(15)
        /// 一像素细线（分隔线、卡片描边）
        ///
        /// **不随 `panelScale` 缩放**：它是物理像素级的东西，放大只会变成一条粗边。
        public static let hairline: CGFloat = 1
        /// 空状态 / 英雄位图标尺寸
        public static let emptyStateIcon = scaled(32)
        /// 列表顶部 / 底部渐隐带的高度
        ///
        /// 内容从 header 与底栏下面穿过，靠这条渐隐带淡出，而不是被硬切。
        public static let edgeFadeHeight = scaled(22)
        /// HUD 最大宽度
        public static let hudMaxWidth = scaled(420)
        /// HUD 距屏幕底部距离
        public static let hudEdgeOffset = scaled(48)
        /// 对话框宽度
        public static let dialogWidth = scaled(420)
        /// 对话框图标尺寸
        public static let dialogIcon = scaled(32)
        /// 面板顶部占屏幕可见高度的比例
        ///
        /// **不缩放**：它是比例，不是长度。
        public static let paletteTopMarginFraction: CGFloat = 0.18
        /// 设置窗口尺寸（系统窗口，不随面板缩放）
        ///
        /// 比参考实现的 900×700 小：那是为 22 个分栏定的，我们只有 4 个。
        /// 窗口尺寸该由内容决定，不该照抄。
        public static let settingsWindow = CGSize(width: 820, height: 560)
    }

    // MARK: - 阴影

    // 面板与 HUD 的投影没有令牌，因为**它们不是自绘的**：
    // 由 AppKit 的窗口阴影提供（`NSPanel.hasShadow`）。窗口阴影绘制在窗口之外，
    // 形状取自窗口的 alpha 通道，所以圆角就是圆角。若改成 SwiftUI `.shadow`，
    // 阴影会被窗口边界裁切，在圆角外侧留下不透明的方形暗块。
    // 详见 PaletteBackground 的说明。

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
        /// 列表滚动定位
        ///
        /// 比悬停更快：选中项移动时用户已经知道目标在哪，动画只是消除跳变。
        public static let scrollReveal: TimeInterval = 0.10
        /// 复制反馈
        public static let copyFeedback: TimeInterval = 1.2
    }

    // MARK: - 字体

    public enum Typography {
        /// 搜索框字体大小
        public static let searchFieldSize = scaled(20)
        /// 搜索框字体
        public static let searchField = Font.system(size: searchFieldSize, weight: .regular)
        /// 搜索栏图标字体
        public static let headerIcon = Font.system(size: scaled(18), weight: .medium)
        /// 列表行标题
        public static let rowTitle = scaledStyle(.body)
        /// 列表行右侧文本
        public static let rowTrailing = scaledStyle(.callout)
        /// 分组标题
        public static let sectionHeader = scaledStyle(.subheadline, weight: .medium)
        /// 面板标题
        public static let panelTitle = scaledStyle(.headline)
        /// 快捷键帽字体
        public static let keyCap = scaledStyle(.caption1)
        /// 紧凑快捷键帽字体
        public static let compactKeyCap = scaledStyle(.caption2)
        /// 列表行 / 底栏图标字体（固定尺寸，图标需要与 rowIcon 槽位对齐）
        public static let iconGlyph = Font.system(size: scaled(16), weight: .medium)
        /// 空状态图标字体
        public static let emptyStateIcon = Font.system(size: scaled(32), weight: .light)
        /// HUD 提示的语义图标字体
        public static let hudIcon = Font.system(size: scaled(14), weight: .semibold)
        /// 底栏按钮字体
        public static let bar = scaledStyle(.callout, weight: .medium)
        /// 代码字体
        public static let code = Font.system(size: nsPointSize(.callout), design: .monospaced)
        /// 行内代码
        public static let inlineCode = scaledStyle(.body).monospaced()
    }

    /// 按 `panelScale` 缩放一个系统文本样式
    ///
    /// 系统文本样式不能直接乘系数 —— 只能取出它的点大小，用同一个字体描述符重建。
    /// 这样 `.headline` 保持粗体、`.caption2` 保持中等字重，只是整体变大；
    /// 若改成 `.system(size:)` 现造，字重会全部丢失。
    ///
    /// - Parameters:
    ///   - style: 系统文本样式
    ///   - weight: 需要覆盖的字重；不传则保留样式自带的字重
    /// - Returns: 缩放后的字体
    static func scaledStyle(_ style: NSFont.TextStyle, weight: Font.Weight? = nil) -> Font {
        let font = Font(nsFont(style))
        return weight.map(font.weight) ?? font
    }

    /// 取某个系统文本样式缩放后的 `NSFont`
    static func nsFont(_ style: NSFont.TextStyle) -> NSFont {
        let base = NSFont.preferredFont(forTextStyle: style)
        guard panelScale != 1 else { return base }
        return NSFont(descriptor: base.fontDescriptor, size: scaled(base.pointSize)) ?? base
    }

    /// 取某个系统文本样式缩放后的点大小
    static func nsPointSize(_ style: NSFont.TextStyle) -> CGFloat {
        nsFont(style).pointSize
    }

    // MARK: - 颜色

    public enum Colors {

        /// 自适应颜色（深色/浅色模式分别指定）
        public static func adaptive(dark: NSColor, light: NSColor) -> Color {
            Color(
                nsColor: NSColor(name: nil) {
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

        /// 面板顶部边缘高光
        ///
        /// 无边框面板在浅色壁纸上如果没有这层高光，边界会糊掉。
        /// 用渐变而不是单色，是为了让顶部亮、底部弱，读起来像有厚度。
        public static let panelEdgeHighlight = adaptive(
            dark: .srgbInk(1, alpha: 0.16),
            light: .srgbInk(1, alpha: 0.22)
        )

        /// 面板边缘渐变（配合 panelEdgeHighlight 使用）
        public static var panelEdgeGradient: LinearGradient {
            LinearGradient(
                colors: [
                    panelEdgeHighlight,
                    panelEdgeHighlight.opacity(0.35),
                    panelEdgeHighlight.opacity(0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        /// 选中行背景
        public static let selection = ramp(dark: 0.10, light: 0.09)

        /// 悬停行背景
        public static let rowHover = ramp(dark: 0.05, light: 0.045)

        /// 分隔线
        public static let separator = ramp(dark: 0.10, light: 0.12)

        /// 一像素结构细线（面板内的区分隔线）
        ///
        /// 比 `separator` 更淡：它是结构边界，不该和内容抢注意力。
        public static let hairline = ramp(dark: 0.08, light: 0.10)

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

        /// 注意色（可恢复的问题、降级提示）
        public static let warning = Color.orange

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
