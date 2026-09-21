// ClipboardListNavigation.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

/// 剪贴板列表里「按一下上下键之后选中哪一项」
///
/// 抽成纯函数，因为出错的地方在边界与**越界**上，而这两处正是最该被直接断言的：
/// 列表比下标短的时候（面板开着删掉一条、历史被裁剪），旧写法每次算出来的新下标都仍在
/// 界外，表现就是连着按几下「一点不动」。
enum ClipboardListNavigation {

    /// 上下移动一格
    ///
    /// 到两端就停住，不回绕 —— 与面板搜索结果列表（`PaletteSelection.move`）保持一致。
    ///
    /// - Parameters:
    ///   - index: 当前下标（可能已经越界）
    ///   - direction: `-1` 上移，`+1` 下移
    ///   - count: 列表长度
    /// - Returns: 新的下标；列表为空时返回 0
    static func step(from index: Int, direction: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        // 先把「可能越界的当前下标」夹回范围内，再移动：否则越界状态下按一下会原地不动
        let current = clamp(index, count: count)
        return min(max(current + direction, 0), count - 1)
    }

    /// 把下标夹回 `0..<count`
    ///
    /// - Parameters:
    ///   - index: 待夹取的下标
    ///   - count: 列表长度
    /// - Returns: 合法下标；列表为空时返回 0
    static func clamp(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }
}
