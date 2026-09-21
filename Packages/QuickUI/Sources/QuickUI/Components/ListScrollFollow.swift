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
}
