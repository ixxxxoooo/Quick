// SuperPanelNavigation.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 超级面板的「直达键」：数字 1–9，再接字母 a–z
///
/// 动作 / 工具 / 最近使用都用同一套键位，用户不用记「这一页是数字还是字母」。
/// 纯逻辑：不依赖 AppKit，窗口层只负责把按键字符交给它。
public enum SuperPanelKeys {

    /// 键位表：下标即条目序号
    public static let labels: [Character] = Array("123456789abcdefghijklmnopqrstuvwxyz")

    /// 序号对应的键位标签（大写字母显示，更像键帽）；超出键位表返回 nil
    public static func label(at index: Int) -> String? {
        guard labels.indices.contains(index) else { return nil }
        return String(labels[index]).uppercased()
    }

    /// 按键字符对应的条目序号；不在键位表或超出 `count` 返回 nil
    public static func index(forKey character: Character, count: Int) -> Int? {
        let lowered = Character(character.lowercased())
        guard let index = labels.firstIndex(of: lowered), index < count else { return nil }
        return index
    }
}

/// 动作列表的整理：去重、把兜底搜索放最后、限制数量
public enum SuperPanelActionPlanner {

    /// 一次最多展示的动作数：9 个数字键 + 3 个字母键，再多也没人会去数
    public static let maxVisible = 12

    /// 兜底动作的 id（永远排在最后）
    public static let fallbackID = "sp.search-web"

    /// 整理动作顺序：保留先出现的同 id 项，兜底搜索沉底，裁到上限
    ///
    /// 兜底项被裁掉会让用户失去「总能搜一下」的出口，所以裁剪时优先保住它。
    @MainActor
    public static func plan(_ actions: [SuperPanelAction], limit: Int = maxVisible) -> [SuperPanelAction] {
        var seen = Set<String>()
        var primary: [SuperPanelAction] = []
        var fallback: SuperPanelAction?
        for action in actions where seen.insert(action.id).inserted {
            if action.id == fallbackID {
                fallback = action
            } else {
                primary.append(action)
            }
        }
        guard limit > 0 else { return [] }
        if let fallback {
            return Array(primary.prefix(limit - 1)) + [fallback]
        }
        return Array(primary.prefix(limit))
    }
}

/// 列表里的上下移动：到头后回绕（对齐主面板的列表手感）
public enum SuperPanelListNavigator {

    /// 新的选中序号；`count == 0` 时返回 0
    public static func move(from current: Int, delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let clamped = min(max(current, 0), count - 1)
        let next = (clamped + delta) % count
        return next < 0 ? next + count : next
    }
}

/// 工作台的统一导航：「常用工具」是 N 列网格，其后跟着「最近使用」竖列表
///
/// 选中序号跨两段连续编号：`0..<toolCount` 是工具，`toolCount..<total` 是最近使用。
public enum SuperPanelDockNavigator {

    public enum Direction: Sendable {
        case up, down, left, right
    }

    /// 从 `index` 往 `direction` 走一步；走不动返回 nil（调用方可借此切换标签）
    public static func move(
        from index: Int,
        _ direction: Direction,
        toolCount: Int,
        recentCount: Int,
        columns: Int
    ) -> Int? {
        let total = toolCount + recentCount
        guard total > 0, columns > 0, (0..<total).contains(index) else { return nil }

        if index >= toolCount {
            // 最近使用段：只有上下
            switch direction {
            case .up:
                if index > toolCount { return index - 1 }
                return toolCount > 0 ? toolCount - 1 : nil
            case .down:
                return index + 1 < total ? index + 1 : nil
            case .left, .right:
                return nil
            }
        }

        let column = index % columns
        switch direction {
        case .left:
            return column > 0 ? index - 1 : nil
        case .right:
            return column < columns - 1 && index + 1 < toolCount ? index + 1 : nil
        case .up:
            return index - columns >= 0 ? index - columns : nil
        case .down:
            if index + columns < toolCount { return index + columns }
            // 下一行存在但不满：落到最后一个工具上，比原地不动更符合直觉
            let hasNextRow = index / columns < (toolCount - 1) / columns
            if hasNextRow { return toolCount - 1 }
            return recentCount > 0 ? toolCount : nil
        }
    }
}

/// 面板高度的计算（把「钳到区间」从控制器里拿出来，便于单测）
public enum SuperPanelHeightPolicy {

    /// 把内容自然高度夹进 `[min, max]`；内容高度未知（≤ 0）返回 nil，表示别动窗口
    public static func resolve(contentHeight: CGFloat, minHeight: CGFloat, maxHeight: CGFloat) -> CGFloat? {
        guard contentHeight > 0 else { return nil }
        return min(max(contentHeight, minHeight), maxHeight)
    }
}
