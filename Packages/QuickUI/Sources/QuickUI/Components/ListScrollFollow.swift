// ListScrollFollow.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 列表的滚动跟随：选中项移动时该滚到哪里
///
/// **只有选中项碰到视口边缘才滚动，中间一个像素都不滚。**
///
/// 把选中项一直摆在视口中央（`anchor: .center`）看着更"整齐"，实际是每按一下方向键
/// 整块列表都在动：眼睛要一直追着移动的目标，长按方向键时列表持续滑动、动画被反复打断，
/// 糊成一片。边缘跟随的手感是「选中框在列表里走，走到边上列表才跟上」——
/// 静止的部分保持静止，移动的部分才移动。
///
/// 抽成纯函数是因为它出错的地方全在两端：第 0 项滚到看不见、最后一项被底栏压住一角。
/// 这两处靠手点很难每次都试到，而断言一行就够。
public enum ListScrollFollow {

    /// 选中第 `index` 项时该滚到哪个锚点
    ///
    /// - Parameters:
    ///   - index: 新的选中下标（调用方保证合法，越界时行为与「中间项」相同）
    ///   - count: 列表长度
    /// - Returns: 两端返回明确的 `.top` / `.bottom`；中间返回 `nil`，
    ///   即交给 SwiftUI 做**最小幅度**滚动 —— 已经看得见就一点不滚。
    public static func anchor(for index: Int, count: Int) -> UnitPoint? {
        // 两端给明确锚点，而不是也交给"最小幅度"：面板的 header 与底栏是 `safeAreaInset`
        // 挂在滚动内容上的，最小幅度只保证"进入可视区"，不保证"整个露在两条栏位之间"。
        if index == 0 { return .top }
        if index == count - 1 { return .bottom }
        return nil
    }

    // MARK: - 边缘标记

    /// 列表顶端标记的 ID
    public static let topID = "quick.list.edge.top"
    /// 列表底端标记的 ID
    public static let bottomID = "quick.list.edge.bottom"

    /// 滚动目标
    public enum Target<ID: Hashable>: Equatable {
        /// 内容的最顶端（连同顶部内边距一起露出来）
        case top
        /// 内容的最底端（连同底部内边距一起露出来）
        case bottom
        /// 中间项：交给 SwiftUI 做最小幅度滚动
        case item(ID)
    }

    /// 选中第 `index` 项时该滚到哪里
    ///
    /// **两端必须滚到「内容的端点」而不是「第一项 / 最后一项」。** 列表带内边距时，
    /// `scrollTo(firstItem, anchor: .top)` 会把第一行贴到视口顶沿，内边距被滚出可视区，
    /// 整个列表就比没滚动时往上缩了一个内边距 —— 同一个页面，结果少（装得下，没法滚）
    /// 和结果多（能滚）时第一行的位置差了一截，输入时看起来就是「列表往下跳了一下」。
    public static func target<ID: Hashable>(for index: Int, count: Int, itemID: ID) -> Target<ID> {
        guard let edge = anchor(for: index, count: count) else { return .item(itemID) }
        return edge == .top ? .top : .bottom
    }
}

/// 放在可滚动内容的最前面，充当「滚到顶」的锚点
///
/// 必须放在**带内边距的容器之外**，滚到它才会把内边距一起露出来。
public struct ListTopMarker: View {
    public init() {}
    public var body: some View {
        Color.clear.frame(height: 0).id(ListScrollFollow.topID)
    }
}

/// 放在可滚动内容的最后面，充当「滚到底」的锚点（规则同 `ListTopMarker`）
public struct ListBottomMarker: View {
    public init() {}
    public var body: some View {
        Color.clear.frame(height: 0).id(ListScrollFollow.bottomID)
    }
}

extension ScrollViewProxy {

    /// 键盘移动选中项后的滚动跟随（两端滚到内容端点，中间最小幅度）
    @MainActor
    public func follow<ID: Hashable>(index: Int, count: Int, itemID: ID) {
        switch ListScrollFollow.target(for: index, count: count, itemID: itemID) {
        case .top: scrollTo(ListScrollFollow.topID, anchor: .top)
        case .bottom: scrollTo(ListScrollFollow.bottomID, anchor: .bottom)
        case .item(let id): scrollTo(id, anchor: nil)
        }
    }

    /// 换了一批内容之后回到顶部
    @MainActor
    public func scrollToTopEdge() {
        scrollTo(ListScrollFollow.topID, anchor: .top)
    }
}
