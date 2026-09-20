// PaletteSelection.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 面板里被键盘驱动的选择状态
///
/// **为什么单独一个对象，而不是放在协调器上：** 协调器持有 `NSPanel`，
/// 一旦被 SwiftUI 观察就会与 AttributeGraph 形成重建死循环（见
/// `PaletteCoordinator` 顶部的说明）。这个对象不持有任何窗口，只被面板内的视图观察，
/// 所以安全。
///
/// **为什么需要它：** 上下键与回车必须在 AppKit 层（`PalettePanel.sendEvent`）拦截 ——
/// 面板打开时焦点在输入框里，field editor 会先把上下键拿去移动光标、
/// 把回车当成提交，挂在 SwiftUI 视图上的 `onKeyPress` 根本收不到。
/// 而 AppKit 层拦到按键之后，得有个地方安放「当前选中第几项」，那就是这里。
@MainActor
@Observable
public final class PaletteSelection {

    /// 当前结果条数（由视图写入）
    public var count = 0

    /// 当前选中下标（由视图与键盘共同读写）
    public var index = 0

    /// 执行第 `index` 项（由视图写入：只有视图知道每一项的动作）
    public var activate: ((Int) -> Void)?

    public init() {}

    /// 上下移动选中项
    ///
    /// 夹在边界内而不是环绕：面板里没有可见的滚动条，环绕会让人瞬间失去方位感。
    ///
    /// - Parameter delta: `-1` 上移、`+1` 下移
    /// - Returns: 是否消费了这次按键（没有结果时不该消费，否则输入框里的方向键也失效）
    public func move(_ delta: Int) -> Bool {
        guard count > 0 else { return false }
        index = min(max(index + delta, 0), count - 1)
        return true
    }

    /// 执行当前选中项
    /// - Returns: 是否消费了这次按键
    public func activateSelection() -> Bool {
        guard count > 0, index >= 0, index < count, let activate else { return false }
        activate(index)
        return true
    }

    /// 结果集变化时同步
    ///
    /// 下标归零：换了一批结果还停在原来的第 7 项是没有意义的。
    ///
    /// - Parameters:
    ///   - count: 新结果条数
    ///   - activate: 执行某一项的动作
    public func update(count: Int, activate: @escaping (Int) -> Void) {
        self.count = count
        self.activate = activate
        index = 0
    }
}
