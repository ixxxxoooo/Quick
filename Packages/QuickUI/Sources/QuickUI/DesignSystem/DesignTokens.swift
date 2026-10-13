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
        /// 1pt 的贴边间距（图标与外框之间的缝）
        public static let hairline: CGFloat = 1
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
        /// 超级面板圆角（对齐 Fasty，**不跟** `panelScale`）
        public static let superPanel: CGFloat = 16
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
        /// 设置侧栏彩色图标色块圆角（略紧，适配 18pt 色块）
        ///
        /// 设置窗口不跟 `panelScale`，与 `Size.settingsIconTile` 同为绝对点值。
        public static let settingsIconTile: CGFloat = 5
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
        /// ⌘K 操作菜单宽度
        public static let actionMenuWidth = scaled(220)
        /// 操作菜单行首图标槽位宽度
        public static let menuIconSlot = scaled(20)
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
        /// 设置行尾部输入控件（步进器、选择器）的标准宽度
        ///
        /// 尾部控件不定宽时，行与行之间会对不齐；太宽又会把标题挤掉。
        /// **不随 `panelScale` 缩放**：设置窗口尺寸固定，缩放它只会让控件忽宽忽窄。
        public static let settingsControl: CGFloat = 120
        /// 设置行尾部较宽的控件（多位数步进器、长文案选择器）
        ///
        /// 与 `settingsControl` 同一族，只为「120 装不下」的准备。不要为单个页面现造宽度。
        public static let settingsControlWide: CGFloat = 140
        /// 设置行尾部数字读数的宽度（滑块右侧的 `36` / `44` 那类）
        public static let settingsReadout: CGFloat = 36
        /// 编辑器 / 输入区的标准最小宽度（插件工作面板里的文本框）
        public static let editorMinWidth: CGFloat = 200
        /// 分段控件（`pickerStyle(.segmented)`）的标准宽度
        public static let segmentedControl: CGFloat = 140
        /// 拖拽授权面板的初始宽度（吸附前 / 量不到系统设置窗口时的兜底）
        ///
        /// **吸附后不用它定宽**：宽度跟随系统设置右侧内容区（`PermissionSnapGeometry.width`），
        /// 这样面板才和设置列表等宽对齐。不跟主面板缩放。
        public static let permissionPanelWidth: CGFloat = 460
        /// 系统设置左侧栏宽度，用来把授权面板和右侧列表对齐
        public static let systemSettingsSidebar: CGFloat = 230
        /// 主面板允许拖到的最矮高度
        public static let panelMinHeight: CGFloat = panelHeight * 0.6
        /// 主面板允许拖到的最窄宽度
        public static let panelMinWidth: CGFloat = panelWidth * 0.6
        /// JSON 树每一层的缩进宽度
        public static let jsonTreeIndent = scaled(14)
        /// JSON 树的行高
        public static let jsonTreeRowHeight = scaled(22)
        /// 代码编辑器（`CodeEditorView`）的固定行高
        ///
        /// 关闭软换行后，左右两个编辑器靠同一条行高按行号对齐；行号槽也按它定位。
        public static let codeEditorLineHeight = scaled(20)
        /// 代码编辑器行号槽宽度
        public static let codeEditorGutter = scaled(44)
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
        /// 半像素细线（卡片描边）
        public static let hairlineThin: CGFloat = 0.5
        /// 设置页行首图标
        public static let settingsRowIcon: CGFloat = 20
        /// 设置页里的三档输入框宽度
        public static let settingsFieldSmall: CGFloat = 160
        public static let settingsFieldMedium: CGFloat = 220
        public static let settingsFieldLarge: CGFloat = 260
        /// 发光投影的半径与偏移
        public static let glowShadowRadius: CGFloat = 6
        public static let glowShadowOffsetY: CGFloat = 2
        /// 弹出层投影：半径与纵向偏移
        public static let popoverShadowRadius: CGFloat = 8
        public static let popoverShadowOffsetY: CGFloat = 4
        /// 插件视图里的方形图标按钮 / 控件高度
        public static let controlSquare: CGFloat = 28
        /// 插件列表里的 Provider 图标
        public static let providerIcon: CGFloat = 32
        /// 插件头部大图标底块与其中的图形字号
        public static let heroTile: CGFloat = 40
        public static let heroGlyph: CGFloat = 20
        /// Diff 面板最小宽度
        public static let diffPaneMinWidth: CGFloat = 240
        /// 翻译：输入框高度范围、语言标签宽度、历史面板尺寸
        public static let translatorEditorMinHeight: CGFloat = 88
        public static let translatorEditorMaxHeight: CGFloat = 160
        public static let translatorLabelWidth: CGFloat = 34
        public static let translatorHistoryWidth: CGFloat = 420
        public static let translatorHistoryHeight: CGFloat = 480
        /// Hash：输入框高度与算法名列宽
        public static let hashInputHeight: CGFloat = 100
        public static let hashLabelWidth: CGFloat = 55
        /// UUID：选项控件宽度与序号列宽
        public static let uuidOptionWidth: CGFloat = 130
        /// 结束进程列表右侧指标（CPU % / 内存）的列宽，容纳 `1024.5 MB`
        public static let processMetricWidth: CGFloat = scaled(84)
        /// UUID 版本分段控件宽度
        public static let uuidVersionPickerWidth: CGFloat = 90
        /// HMAC 密钥输入框宽度
        public static let hmacKeyFieldWidth: CGFloat = 220
        public static let indexColumnWidth: CGFloat = 20
        /// 截图设置里的预览框
        public static let screenshotPreview = CGSize(width: 120, height: 80)
        /// 超级面板设置：数值读数列宽、说明文案最大宽度
        public static let superPanelReadout: CGFloat = 56
        public static let superPanelNoteMaxWidth: CGFloat = 320
        /// 设置页：窄列、宽字段、对话框宽度
        public static let settingsColumnNarrow: CGFloat = 80
        public static let settingsFieldWide: CGFloat = 200
        public static let settingsGlyphColumn: CGFloat = 24
        public static let settingsDialogWidth: CGFloat = 420
        public static let settingsRowGlyph: CGFloat = 18
        /// 快捷键录制框内的小图标 / 圆角
        public static let recorderGlyph: CGFloat = 18
        public static let recorderHeight: CGFloat = 24
        public static let recorderKeyRadius: CGFloat = 4
        /// 空状态 / 英雄位图标尺寸
        public static let emptyStateIcon = scaled(32)
        /// 月历单元格的高度
        public static let calendarCellHeight = scaled(42)
        /// 月历左侧面板宽度
        public static let calendarPanelWidth = scaled(320)
        /// 月历周数列宽度
        public static let calendarWeekColumn = scaled(26)
        /// 事件 / 日期小圆点直径
        public static let calendarDot = scaled(6)
        /// 日期信息卡左侧大号日期的槽位宽度
        public static let calendarHeroColumn = scaled(72)
        /// 空状态占位区的最小高度（滚动容器里没有 `maxHeight: .infinity` 可用）
        public static let emptyStateMinHeight = scaled(120)
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
        /// 系统监控面板左侧导航宽度（对齐 Raycast System Monitor 双栏比例）
        public static let monitorSidebar = scaled(220)
        /// 设置窗口侧边栏图标的槽位宽度
        ///
        /// 与 `Typography.sidebarIcon` 配套。槽位宽度统一是「这一页读起来整齐」的关键 ——
        /// 每行各自 `Image` 会让标题的起始位置逐行漂移。
        public static let sidebarIconSlot = scaled(18)
        /// 设置侧栏彩色图标色块边长（对齐 Raycast Preferences：约 18pt，不跟面板缩放）
        public static let settingsIconTile: CGFloat = 18
        /// 色块内 SF Symbol 字号（略小于色块，四周留白）
        public static let settingsIconGlyph: CGFloat = 10
        /// 色块与标题之间的水平间距（Raycast 侧栏约 10–12pt）
        public static let settingsSidebarIconGap: CGFloat = 10
        /// 侧栏行上下内边距（比系统默认略松，避免挤成一团）
        public static let settingsSidebarRowVertical: CGFloat = 3
        /// 侧栏行左右内边距
        public static let settingsSidebarRowHorizontal: CGFloat = 8

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
        /// 分离窗口标题栏带插件内搜索框时的高度
        ///
        /// 搜索框本身有 `headerHeight` 高，标题栏要比普通标题栏（`detachedTitleBarHeight`）
        /// 再加一档内边距才放得下、且上下留出同样的呼吸空间。
        public static let detachedSearchTitleBarHeight = headerHeight + headerPadding
        /// 分离窗口标题栏里插件内搜索框的最大宽度
        ///
        /// 搜索框不与窗口等宽：右侧剩下的空白留给标题栏拖拽区，窗口才不会「除了按钮全是输入框」。
        public static let detachedSearchFieldMaxWidth = scaled(360)

        // MARK: 超级面板

        /// 超级面板固定宽度（对齐 Fasty 390pt，**不跟** `panelScale`）
        public static let superPanelWidth: CGFloat = 390
        /// 超级面板最矮高度（仅一行提示时）
        public static let superPanelMinHeight: CGFloat = 120
        /// 超级面板最高高度（超出则内容区内部滚动）
        public static let superPanelMaxHeight: CGFloat = 620
        /// 超级面板初始高度（内容量出来前的占位）
        public static let superPanelInitialHeight: CGFloat = 320

        // MARK: AI 聚合标签栏

        /// AI 聚合窗口的标签栏高度
        public static let aiTabBarHeight: CGFloat = 36
        /// 标签栏在标题栏中的左侧起始偏移（避让红绿灯 + 呼吸空间）
        public static let aiTitleBarTabLeading: CGFloat = 80
        /// 标题栏内标签项高度（适配标准标题栏约 28pt）
        public static let aiTitleBarTabHeight: CGFloat = 24
        /// AI 标签项水平内边距
        public static let aiTabItemPaddingH: CGFloat = 8
        /// AI 标签项图标尺寸
        public static let aiTabIconSize: CGFloat = 13
        /// AI 标签项间距
        public static let aiTabItemSpacing: CGFloat = 4
        /// AI 标签栏关闭按钮尺寸
        public static let aiTabCloseSize: CGFloat = 12

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

    // MARK: - 不透明度（语义）

    public enum Opacity {
        /// 破坏性按钮的底色浓度
        public static let destructiveFill: Double = 0.16
        /// 分隔线的淡化程度（系统 `Divider` 在玻璃上偏重，统一压淡）
        public static let divider: Double = 0.3
        /// 强调色 / 进度色的浅色底（徽标、选中块、图标底）
        public static let tint: Double = 0.12
        /// 强调色的较重底色（拖拽高亮等需要更醒目的场景）
        public static let tintStrong: Double = 0.2
        /// 弹出层投影的浓度
        public static let popoverShadow: Double = 0.15
        /// 次要文字再淡一档
        public static let dimmed: Double = 0.7
        /// 卡片底色的淡化版（嵌在卡片里的次级区块）
        public static let cardFillDim: Double = 0.35
        /// 控件底色的淡化版
        public static let controlSurfaceDim: Double = 0.4
        /// 选中行（强调色底）上的次要文字
        public static let onAccentSecondary: Double = 0.8
        /// 强调色描边
        public static let accentStroke: Double = 0.5
        /// Diff 行底色
        public static let diffBand: Double = 0.15
        /// 发光投影
        public static let glow: Double = 0.3
        /// 录制快捷键里键帽的底色
        public static let keyCapFill: Double = 0.08
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
        /// 行内提示的淡入淡出
        public static let feedbackFade: TimeInterval = 0.2
        /// 行内提示停留时长
        public static let feedbackHold: TimeInterval = 1.8
        /// 刷新图标转一圈
        public static let spin: TimeInterval = 0.8
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
        /// 列表行里 SF Symbol 图标的字体
        public static let rowSymbol = Font.system(size: scaled(13), weight: .medium)
        /// 插件头部按钮图标
        public static let headerButtonSemibold = Font.system(size: 14, weight: .semibold)
        public static let headerButtonMedium = Font.system(size: 14, weight: .medium)
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
        /// 设置侧栏行标题（Regular 13pt，对齐 Raycast Preferences，不跟面板缩放）
        public static let settingsSidebarLabel = Font.system(size: 13, weight: .regular)
        /// 设置侧栏色块内字形（Medium，比 Semibold 更细，接近 Raycast 白符号）
        public static let settingsIconGlyphFont = Font.system(
            size: Size.settingsIconGlyph, weight: .medium
        )
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
        /// 日期信息卡里的大号日期
        public static let calendarHeroDay = Font.system(size: scaled(44), weight: .semibold)
        /// 月历格子右上角的「休 / 班」角标
        public static let calendarBadge = Font.system(size: scaled(9), weight: .semibold)
        /// HUD 提示的语义图标字体
        public static let hudIcon = Font.system(size: scaled(14), weight: .semibold)
        /// 底栏按钮字体
        public static let bar = scaledStyle(.callout, weight: .medium)
        /// 代码字体
        public static let code = Font.system(size: nsPointSize(.callout), design: .monospaced)
        /// 代码字体的 AppKit 版本（自绘 `NSTextView` / 行号槽用）
        public static var codeNSFont: NSFont {
            NSFont.monospacedSystemFont(ofSize: nsPointSize(.callout), weight: .regular)
        }
        /// 计算器输入 / 结果字号
        ///
        /// 比 `code` 大一档：计算器的数字是**面板主体**，不是行内代码，用 callout 太小。
        public static let calculatorSize = scaled(20)
        /// 计算器输入 / 结果字体
        public static let calculator = Font.system(
            size: calculatorSize, weight: .regular, design: .monospaced)
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
        ///
        /// 开启「增强对比度」时系统会换成高对比外观（`accessibilityHighContrast*`），
        /// 这里据此把不透明度整体抬高 —— 半透明的描边、分隔线、选中底色在默认下很淡，
        /// 对低视力用户几乎看不见。见 `ContrastBoost`。
        public static func ramp(dark: Double, light: Double) -> Color {
            Color(
                nsColor: NSColor(name: nil) { appearance in
                    resolveRamp(dark: dark, light: light, appearance: appearance)
                })
        }

        /// `ramp` 在某个外观下的取值（单独拎出来，测试可以直接喂外观与系统开关）
        ///
        /// 高对比只认系统「增强对比度」开关。**不能靠外观名判断**：`bestMatch` 与 `NSAppearance.name`
        /// 都会把高对比变体归并回基础外观（实测 `.accessibilityHighContrastAqua.name == .aqua`），永远认不出来。
        static func resolveRamp(
            dark: Double, light: Double, appearance: NSAppearance,
            systemIncreaseContrast: Bool = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        ) -> NSColor {
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let alpha = ContrastBoost.alpha(isDark ? dark : light, highContrast: systemIncreaseContrast)
            return .srgbInk(isDark ? 1 : 0, alpha: alpha)
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
        /// 结果行 SF Symbol 图标的底块（比选中高亮淡，免得与选中态混淆）
        public static let iconTile = ramp(dark: 0.08, light: 0.06)

        /// 设置侧栏选中高亮（中性浅灰，对齐 Raycast；不用系统强调蓝）
        public static let settingsSidebarSelection = ramp(dark: 0.16, light: 0.08)

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
        /// 压在强调色填充上的前景（选中日期的数字）
        public static let onAccent = Color.white

        /// 设置侧栏图标色块配色（对齐系统设置多彩瓷砖，深浅模式各一套）
        public enum SettingsIcon {
            public static let blue = adaptive(
                dark: NSColor(srgbRed: 64 / 255, green: 156 / 255, blue: 255 / 255, alpha: 1),
                light: NSColor(srgbRed: 0 / 255, green: 122 / 255, blue: 255 / 255, alpha: 1)
            )
            public static let indigo = adaptive(
                dark: NSColor(srgbRed: 110 / 255, green: 130 / 255, blue: 255 / 255, alpha: 1),
                light: NSColor(srgbRed: 88 / 255, green: 86 / 255, blue: 214 / 255, alpha: 1)
            )
            public static let purple = adaptive(
                dark: NSColor(srgbRed: 191 / 255, green: 128 / 255, blue: 255 / 255, alpha: 1),
                light: NSColor(srgbRed: 175 / 255, green: 82 / 255, blue: 222 / 255, alpha: 1)
            )
            public static let pink = adaptive(
                dark: NSColor(srgbRed: 255 / 255, green: 110 / 255, blue: 170 / 255, alpha: 1),
                light: NSColor(srgbRed: 255 / 255, green: 45 / 255, blue: 85 / 255, alpha: 1)
            )
            public static let red = adaptive(
                dark: NSColor(srgbRed: 255 / 255, green: 105 / 255, blue: 97 / 255, alpha: 1),
                light: NSColor(srgbRed: 255 / 255, green: 59 / 255, blue: 48 / 255, alpha: 1)
            )
            public static let orange = adaptive(
                dark: NSColor(srgbRed: 255 / 255, green: 169 / 255, blue: 76 / 255, alpha: 1),
                light: NSColor(srgbRed: 255 / 255, green: 149 / 255, blue: 0 / 255, alpha: 1)
            )
            public static let yellow = adaptive(
                dark: NSColor(srgbRed: 255 / 255, green: 214 / 255, blue: 70 / 255, alpha: 1),
                light: NSColor(srgbRed: 255 / 255, green: 204 / 255, blue: 0 / 255, alpha: 1)
            )
            public static let green = adaptive(
                dark: NSColor(srgbRed: 70 / 255, green: 215 / 255, blue: 130 / 255, alpha: 1),
                light: NSColor(srgbRed: 52 / 255, green: 199 / 255, blue: 89 / 255, alpha: 1)
            )
            public static let mint = adaptive(
                dark: NSColor(srgbRed: 80 / 255, green: 230 / 255, blue: 200 / 255, alpha: 1),
                light: NSColor(srgbRed: 0 / 255, green: 199 / 255, blue: 190 / 255, alpha: 1)
            )
            public static let teal = adaptive(
                dark: NSColor(srgbRed: 80 / 255, green: 210 / 255, blue: 220 / 255, alpha: 1),
                light: NSColor(srgbRed: 48 / 255, green: 176 / 255, blue: 199 / 255, alpha: 1)
            )
            public static let cyan = adaptive(
                dark: NSColor(srgbRed: 90 / 255, green: 200 / 255, blue: 250 / 255, alpha: 1),
                light: NSColor(srgbRed: 50 / 255, green: 173 / 255, blue: 230 / 255, alpha: 1)
            )
            public static let gray = adaptive(
                dark: NSColor(srgbRed: 152 / 255, green: 162 / 255, blue: 179 / 255, alpha: 1),
                light: NSColor(srgbRed: 142 / 255, green: 142 / 255, blue: 147 / 255, alpha: 1)
            )
            public static let brown = adaptive(
                dark: NSColor(srgbRed: 196 / 255, green: 154 / 255, blue: 108 / 255, alpha: 1),
                light: NSColor(srgbRed: 162 / 255, green: 132 / 255, blue: 94 / 255, alpha: 1)
            )
        }

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

        // MARK: AI 聚合标签栏

        /// AI 标签栏背景
        public static let aiTabBarBackground = adaptive(
            dark: NSColor(srgbRed: 32 / 255, green: 32 / 255, blue: 36 / 255, alpha: 1),
            light: NSColor(srgbRed: 240 / 255, green: 240 / 255, blue: 244 / 255, alpha: 1)
        )

        /// AI 标签项选中底色（标题栏内需要足够柔和）
        public static let aiTabSelected = adaptive(
            dark: .srgbInk(1, alpha: 0.10),
            light: .srgbInk(0, alpha: 0.08)
        )

        /// AI 标签项悬停底色
        public static let aiTabHover = adaptive(
            dark: .srgbInk(1, alpha: 0.05),
            light: .srgbInk(0, alpha: 0.04)
        )

        /// AI 标签项文字选中色
        public static let aiTabSelectedText = adaptive(
            dark: .srgbInk(1, alpha: 0.90),
            light: .srgbInk(0, alpha: 0.85)
        )

        /// AI 标签项文字非选中色
        public static let aiTabText = adaptive(
            dark: .srgbInk(1, alpha: 0.50),
            light: .srgbInk(0, alpha: 0.45)
        )

        /// AI 标签栏分隔线
        public static let aiTabSeparator = adaptive(
            dark: .srgbInk(1, alpha: 0.08),
            light: .srgbInk(0, alpha: 0.06)
        )

        // MARK: 悬浮胶囊

        /// 胶囊底色（近不透明，让它在任意网页/内容上都读得清）
        public static let capsuleFill = adaptive(
            dark: NSColor(srgbRed: 28 / 255, green: 28 / 255, blue: 32 / 255, alpha: 0.78),
            light: .srgbInk(1, alpha: 0.82)
        )

        /// 拖动中的胶囊底色（完全不透明）
        ///
        /// 拖动时把实时材质收起来，由这一层单独撑住外观：材质每移动一帧都要重新采样它背后的
        /// 内容，而这里背后常常是一整块 `WKWebView`（内容在别的进程里），采样代价直接变成
        /// 拖动时的掉帧。不透明之后合成器连背后都不用看，拖起来才跟手。
        /// 色相与 `capsuleFill` 相同，只把 alpha 补满 —— 松手换回材质时几乎看不出接缝。
        public static let capsuleFillDragging = adaptive(
            dark: NSColor(srgbRed: 28 / 255, green: 28 / 255, blue: 32 / 255, alpha: 1),
            light: .srgbInk(1, alpha: 1)
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
