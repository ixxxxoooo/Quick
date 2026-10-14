// CalendarLayoutMetrics.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import CoreGraphics
import Foundation

/// 日历内容区尺寸 → 布局决策
///
/// 窗口被拖大拖小时，日历的内容要跟着变：窄了收成单栏、矮了收起农历小字与假期摘要、
/// 高了就让格子变高。**纯函数，所有设计数值由 `Limits` 注入**（视图层用 `DesignTokens` 构造），
/// 这样分档与夹取可以脱离界面单测，Model 层也不用认识设计令牌。
struct CalendarLayoutMetrics: Equatable, Sendable {

    /// 布局所需的全部数值
    struct Limits: Equatable, Sendable {
        /// 宽度小于它时收成单栏
        var compactBelowWidth: CGFloat
        /// 双栏时月历占内容宽度的比例，再夹在 min…max 之间
        var monthColumnFraction: CGFloat
        var monthColumnMin: CGFloat
        var monthColumnMax: CGFloat
        /// 月历格高度的下限与上限
        var cellMinHeight: CGFloat
        var cellMaxHeight: CGFloat
        /// 格子低于 / 窄于它时不再放农历小字
        var lunarMinCellHeight: CGFloat
        var lunarMinCellWidth: CGFloat
        /// 格子窄于它时不放周数列
        var weekNumberMinCellWidth: CGFloat
        /// 月历之外占用的高度：上下内边距 + 星期表头 + 间距
        var gridChromeHeight: CGFloat
        /// 假期摘要条占用的高度
        var summaryHeight: CGFloat
        /// 放下摘要后格高仍不低于它，才保留摘要
        var summaryMinCellHeight: CGFloat
        var rowSpacing: CGFloat
        /// 月历左右各一份内边距
        var horizontalPadding: CGFloat
        var weekNumberColumn: CGFloat
        /// 周视图 7 列并排所需的最小总宽；不够就改成纵向列表
        var weekColumnsMinWidth: CGFloat
    }

    enum Columns: Equatable, Sendable {
        /// 月历在上、详情在下，整体纵向滚动
        case single
        /// 左月历、右详情
        case double
    }

    let columns: Columns
    /// 双栏时月历栏的宽度；单栏时等于内容宽度
    let monthColumnWidth: CGFloat
    let cellHeight: CGFloat
    let showsLunar: Bool
    let showsWeekNumberColumn: Bool
    let showsSummary: Bool
    /// 双栏下连最小格高都放不下：月历栏自己滚动，不裁剪
    let scrollsMonth: Bool
    /// 周视图改成纵向的「一天一段」
    let weekIsVertical: Bool

    /// 计算布局
    /// - Parameters:
    ///   - size: 内容区（工具栏以下）的可用尺寸
    ///   - rows: 当月网格行数（4–6）
    ///   - wantsWeekNumber: 用户在设置里打开了周数列
    ///   - wantsSummary: 用户打开了节假日显示（摘要条才有内容）
    static func make(
        size: CGSize, rows: Int, wantsWeekNumber: Bool, wantsSummary: Bool, limits: Limits
    ) -> CalendarLayoutMetrics {
        let width = max(size.width, 0)
        let height = max(size.height, 0)
        let rowCount = max(rows, 1)

        let columns: Columns = width < limits.compactBelowWidth ? .single : .double
        let monthWidth: CGFloat =
            columns == .single
            ? width
            : min(max(width * limits.monthColumnFraction, limits.monthColumnMin), limits.monthColumnMax)

        // 周数列要不要，取决于去掉它之后格子是否还够宽
        let gridWidth = max(monthWidth - limits.horizontalPadding * 2, 0)
        let cellWidthWithoutWeek = max((gridWidth - limits.rowSpacing * 6) / 7, 0)
        let showsWeek = wantsWeekNumber && cellWidthWithoutWeek >= limits.weekNumberMinCellWidth
        let weekColumn = showsWeek ? limits.weekNumberColumn + limits.rowSpacing : 0
        let cellWidth = max((gridWidth - weekColumn - limits.rowSpacing * 6) / 7, 0)

        let spacingTotal = limits.rowSpacing * CGFloat(rowCount - 1)
        var showsSummary = wantsSummary
        var scrolls = false
        let cell: CGFloat

        switch columns {
        case .single:
            // 单栏整体滚动，格高只跟宽度走（接近正方形），不依赖窗口高度
            cell = min(max(cellWidth * 0.9, limits.cellMinHeight), limits.cellMaxHeight)
        case .double:
            func raw(withSummary: Bool) -> CGFloat {
                let available = height - limits.gridChromeHeight - (withSummary ? limits.summaryHeight : 0)
                return (available - spacingTotal) / CGFloat(rowCount)
            }
            var unclamped = raw(withSummary: showsSummary)
            // 为了放摘要把格子压得太扁不值得：先保格子
            if showsSummary && unclamped < limits.summaryMinCellHeight {
                showsSummary = false
                unclamped = raw(withSummary: false)
            }
            scrolls = unclamped < limits.cellMinHeight
            cell = min(max(unclamped, limits.cellMinHeight), limits.cellMaxHeight)
        }

        return CalendarLayoutMetrics(
            columns: columns,
            monthColumnWidth: monthWidth,
            cellHeight: cell,
            showsLunar: cell >= limits.lunarMinCellHeight && cellWidth >= limits.lunarMinCellWidth,
            showsWeekNumberColumn: showsWeek,
            showsSummary: showsSummary,
            scrollsMonth: scrolls,
            weekIsVertical: width < limits.weekColumnsMinWidth)
    }
}
