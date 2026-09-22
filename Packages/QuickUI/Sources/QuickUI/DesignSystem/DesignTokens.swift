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
        /// 窗口控制按钮尺寸（分离窗口标题栏右上角的置顶 / 关闭）
        ///
        /// 比 `barButtonHeight` 小一档：标题栏本身只有 `detachedTitleBarHeight` 高，
        /// 按钮占满它就把整条栏位撑满了，两个方块比标题还抢眼。
        public static let windowControlButton = scaled(22)
        /// 列表行图标尺寸
        public static let rowIcon = scaled(24)
        /// 快捷键帽尺寸
        public static let keyCap = scaled(18)
        /// 紧凑快捷键帽尺寸（底栏密集提示用）
        public static let compactKeyCap = scaled(15)
        /// 设置项别名框与快捷键录制框标准宽度（参考 Tinycast）
        public static let shortcutRecorder: CGFloat = 120
        /// 拖拽授权面板宽度。贴在系统设置右侧内容区下面，不跟主面板缩放
        public static let permissionPanelWidth: CGFloat = 460
        /// 系统设置左侧栏宽度，用来把授权面板和右侧列表对齐
        public static let systemSettingsSidebar: CGFloat = 230
        /// 主面板允许拖到的最矮高度
        public static let panelMinHeight: CGFloat = panelHeight * 0.6
        /// 主面板允许拖到的最窄宽度
        public static let panelMinWidth: CGFloat = panelWidth * 0.6
        /// 主面板四边用来拖拽改变大小的热区厚度
        public static let resizeMargin = scaled(6)
        /// JSON 树每一层的缩进宽度
        public static let jsonTreeIndent = scaled(14)
        /// JSON 树的行高
        public static let jsonTreeRowHeight = scaled(22)
        /// 剪贴板图片缩略图的高度（比文本行图标大，直接当预览看）
        public static let clipboardThumbHeight = scaled(72)
        /// 剪贴板图片缩略图的最大宽度（宽图按比例缩，不撑破行）
        public static let clipboardThumbMaxWidth = scaled(180)
        /// 剪贴板来源应用图标尺寸
        public static let clipboardSourceIcon = scaled(14)
        /// 剪贴板行右侧收藏按钮的点击区尺寸
        public static let clipboardFavoriteButton = scaled(22)
        /// 引导页步骤圆点
        public static let onboardingDot = scaled(7)
        /// 引导页宽度。系统窗口，不跟主面板缩放
        public static let onboardingWidth: CGFloat = 520
        /// 引导页第一次布局前的高度，内容量完之后窗口会再收一收
        public static let onboardingMinHeight: CGFloat = 420
        /// 引导页顶部图标
        public static let onboardingHero = scaled(60)
        /// 拖拽授权面板量不到内容时的保底高度
        public static let permissionPanelMinHeight: CGFloat = 168
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
        /// 设置窗口尺寸（系统窗口，不随面板缩放，参考 Tinycast 900x700）
        public static let settingsWindow = CGSize(width: 900, height: 700)
        /// 设置窗口侧边栏宽度
        public static let settingsSidebar: CGFloat = 215
        /// 设置窗口详情列最小宽度
        public static let settingsDetailMinimum: CGFloat = 420
        /// 设置搜索框高度
        public static let settingsSearchField: CGFloat = 28
        /// 设置窗口侧边栏图标的槽位宽度
        ///
        /// 与 `Typography.sidebarIcon` 配套。槽位宽度统一是「这一页读起来整齐」的关键 ——
        /// 每行各自 `Image` 会让标题的起始位置逐行漂移。
        public static let sidebarIconSlot = scaled(18)

        // MARK: 搜索结果行

        /// 结果行右侧「来自哪个插件」徽章的规格
        ///
        /// 取自 Fasty `SearchResults.css` 的 `.result-type`：11px 字、2×8 内边距、
        /// 4px 圆角、最宽 120px 后省略 —— 插件名再长也不能把标题挤没。
        public enum SourceBadge {
            public static let fontSize = scaled(11)
            public static let horizontalPadding = scaled(8)
            public static let verticalPadding = scaled(2)
            public static let radius = scaled(4)
            public static let maxWidth = scaled(120)
        }

        // MARK: 插件模式

        /// 插件模式头部高度（与搜索栏高度一致，保持视觉平衡）
        public static let pluginHeaderHeight = scaled(44)
        /// 插件模式头部返回按钮尺寸
        public static let pluginBackButton = scaled(28)
        /// 插件模式头部图标尺寸
        public static let pluginHeaderIcon = scaled(20)

        // MARK: 分离窗口

        /// 分离窗口默认宽度
        public static let detachedPanelDefaultWidth = scaled(750)
        /// 分离窗口默认高度
        public static let detachedPanelDefaultHeight = scaled(475)
        /// 分离窗口最小宽度
        public static let detachedPanelMinWidth: CGFloat = 400
        /// 分离窗口最小高度
        public static let detachedPanelMinHeight: CGFloat = 300
        /// 分离窗口标题栏高度
        public static let detachedTitleBarHeight = scaled(36)

        // MARK: 悬浮胶囊

        /// 悬浮胶囊的几何与间距
        ///
        /// 胶囊叠在窗口内容之上，是 **AI 网页窗口**唯一的常驻控件（关闭 / 刷新 / 置顶 / 外部打开）。
        /// 内容是一整块网页的窗口没有自己的边框，控制只能浮在上面；分离窗口有自己的标题栏，
        /// 控制就长在标题栏里，不用胶囊。
        /// 数值取自 Fasty 的 `capsuleInjectionScript`：22px 圆钮、2px 内边距、
        /// 全圆角（`border-radius: 9999px`）。
        public enum Capsule {
            /// 单个功能按钮尺寸
            public static let buttonSize = scaled(22)
            /// 按钮图标尺寸
            public static let iconSize = scaled(12)
            /// 抓手宽度
            public static let gripWidth = scaled(14)
            /// 抓手高度
            public static let gripHeight = scaled(22)
            /// 抓手圆点直径
            public static let gripDotSize = scaled(2)
            /// 抓手圆点间距
            public static let gripDotSpacing = scaled(4)
            /// 按钮之间的间隔
            public static let itemSpacing = scaled(2)
            /// 胶囊内边距
            public static let padding = scaled(2)
            /// 分组分隔线宽度（不缩放，物理像素级）
            public static let dividerWidth: CGFloat = 1
            /// 分组分隔线高度
            public static let dividerHeight = scaled(12)
            /// 胶囊距窗口边缘的默认内缩
            public static let edgeInset = scaled(10)
            /// 拖拽判定阈值：小于它就当成点击，避免手抖把胶囊挪走
            public static let dragThreshold = scaled(3)
            /// 展开 / 收起动画时长
            public static let animationDuration: TimeInterval = 0.18
            /// 投影模糊半径
            public static let shadowRadius = scaled(10)
            /// 投影垂直偏移
            public static let shadowOffsetY = scaled(2)
        }
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
        /// 窗口控制按钮的图标（分离窗口标题栏的置顶 / 关闭）
        ///
        /// 比 `iconGlyph` 小两档、比 `compactIcon` 大一点：它是窗口控制，不是列表行图标，
        /// 跟着 `windowControlButton` 那个 22pt 的方形槽位走。
        public static let windowControlIcon = Font.system(size: scaled(12), weight: .medium)
        /// 设置窗口侧边栏的列表图标
        ///
        /// 比 `iconGlyph` 小一档：侧边栏的文字是 `.body`，图标跟着文字走而不是跟着行图标走。
        public static let sidebarIcon = Font.system(size: scaled(13), weight: .regular)
        /// 与正文同排的行内图标（搜索框的放大镜、清除按钮、警告三角）
        ///
        /// 这些图标属于**旁边那行文字**，不属于「行图标」那一列，所以跟着正文字号走。
        /// 它们的尺寸必须显式指定：不给 `.font` 会继承容器字号，同一个面板里就会出现
        /// 「有的图标 16、有的 13」——这正是这一组令牌要消掉的问题。
        public static let inlineIcon = Font.system(size: scaled(13), weight: .regular)
        /// 小控件内部的图标（别名框、快捷键录制器的清除按钮）
        public static let compactIcon = Font.system(size: scaled(11), weight: .regular)
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

        // MARK: 语法高亮

        /// 语法高亮的配色
        ///
        /// 只在「代码编辑器」这一处用。深浅两套都取自同一组色相，保证在明暗模式下
        /// 都能互相区分（键 / 字符串 / 数字 / 关键字 / 注释五种要一眼分得开）。
        public enum Syntax {
            /// 对象的键、被引号括起来的标识符
            public static let key = adaptive(
                dark: NSColor(srgbRed: 130 / 255, green: 170 / 255, blue: 255 / 255, alpha: 1),
                light: NSColor(srgbRed: 0 / 255, green: 92 / 255, blue: 197 / 255, alpha: 1)
            )

            /// 字符串字面量
            public static let string = adaptive(
                dark: NSColor(srgbRed: 152 / 255, green: 195 / 255, blue: 121 / 255, alpha: 1),
                light: NSColor(srgbRed: 12 / 255, green: 125 / 255, blue: 60 / 255, alpha: 1)
            )

            /// 数字字面量
            public static let number = adaptive(
                dark: NSColor(srgbRed: 209 / 255, green: 154 / 255, blue: 102 / 255, alpha: 1),
                light: NSColor(srgbRed: 168 / 255, green: 76 / 255, blue: 0 / 255, alpha: 1)
            )

            /// 字面量常量（true / false / null）
            public static let literal = adaptive(
                dark: NSColor(srgbRed: 197 / 255, green: 134 / 255, blue: 192 / 255, alpha: 1),
                light: NSColor(srgbRed: 133 / 255, green: 0 / 255, blue: 122 / 255, alpha: 1)
            )

            /// 语言关键字
            public static let keyword = adaptive(
                dark: NSColor(srgbRed: 198 / 255, green: 120 / 255, blue: 221 / 255, alpha: 1),
                light: NSColor(srgbRed: 116 / 255, green: 0 / 255, blue: 158 / 255, alpha: 1)
            )

            /// 注释
            public static let comment = adaptive(
                dark: NSColor(srgbRed: 122 / 255, green: 134 / 255, blue: 148 / 255, alpha: 1),
                light: NSColor(srgbRed: 112 / 255, green: 124 / 255, blue: 137 / 255, alpha: 1)
            )
        }

        /// 结果行来源徽章的底色
        public static let sourceBadgeFill = ramp(dark: 0.10, light: 0.06)

        /// 结果行来源徽章的文字色
        public static let sourceBadgeText = ramp(dark: 0.45, light: 0.48)

        // MARK: 悬浮胶囊

        /// 胶囊底色（近不透明，让它在任意网页/内容上都读得清）
        public static let capsuleFill = adaptive(
            dark: NSColor(srgbRed: 28 / 255, green: 28 / 255, blue: 32 / 255, alpha: 0.78),
            light: .srgbInk(1, alpha: 0.82)
        )

        /// 胶囊描边
        public static let capsuleStroke = adaptive(
            dark: .srgbInk(1, alpha: 0.12),
            light: .srgbInk(0, alpha: 0.08)
        )

        /// 按钮悬停底色
        public static let capsuleHover = adaptive(
            dark: .srgbInk(1, alpha: 0.12),
            light: .srgbInk(0, alpha: 0.06)
        )

        /// 胶囊图标（未激活）
        public static let capsuleGlyph = adaptive(
            dark: .srgbInk(1, alpha: 0.62),
            light: .srgbInk(0, alpha: 0.55)
        )

        /// 胶囊图标（悬停、激活）
        public static let capsuleGlyphStrong = adaptive(
            dark: .srgbInk(1, alpha: 0.95),
            light: .srgbInk(0, alpha: 0.88)
        )

        /// 置顶等开关型按钮的激活底色
        public static let capsuleToggleFill = adaptive(
            dark: NSColor(srgbRed: 59 / 255, green: 130 / 255, blue: 246 / 255, alpha: 0.28),
            light: NSColor(srgbRed: 59 / 255, green: 130 / 255, blue: 246 / 255, alpha: 0.18)
        )

        /// 开关型按钮激活时的图标色
        public static let capsuleToggleGlyph = adaptive(
            dark: NSColor(srgbRed: 96 / 255, green: 165 / 255, blue: 250 / 255, alpha: 1),
            light: NSColor(srgbRed: 37 / 255, green: 99 / 255, blue: 235 / 255, alpha: 1)
        )

        /// 关闭按钮悬停时的底色与图标色
        public static let capsuleCloseFill = adaptive(
            dark: NSColor(srgbRed: 239 / 255, green: 68 / 255, blue: 68 / 255, alpha: 0.28),
            light: NSColor(srgbRed: 239 / 255, green: 68 / 255, blue: 68 / 255, alpha: 0.18)
        )

        public static let capsuleCloseGlyph = adaptive(
            dark: NSColor(srgbRed: 248 / 255, green: 113 / 255, blue: 113 / 255, alpha: 1),
            light: NSColor(srgbRed: 239 / 255, green: 68 / 255, blue: 68 / 255, alpha: 1)
        )
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
