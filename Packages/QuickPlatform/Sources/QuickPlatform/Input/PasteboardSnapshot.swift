// PasteboardSnapshot.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit

/// 剪贴板全类型快照
///
/// 逐个 item、逐个 type 存 data，而不是只存 string：用户剪贴板里可能是图片或文件，
/// 只备份文本会在恢复时把它们静默清掉。恢复时用 `NSPasteboardItem` 原样重建再 `writeObjects`。
///
/// 延迟承诺的 type（比如拖进来的文件引用）读 `data(forType:)` 可能返回 nil，
/// 这类 type 只能跳过 —— 备份能做到的上限就是「读得到什么存什么」。
public struct PasteboardSnapshot: Sendable {

    /// 每个 pasteboard item 的「类型 → 数据」
    private let items: [[NSPasteboard.PasteboardType: Data]]

    /// 抓取剪贴板当前全部 item 的全部类型数据
    public static func capture(_ board: NSPasteboard) -> PasteboardSnapshot {
        let items = (board.pasteboardItems ?? []).map { item -> [NSPasteboard.PasteboardType: Data] in
            var types: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    types[type] = data
                }
            }
            return types
        }
        return PasteboardSnapshot(items: items)
    }

    /// 与 `capture(_:)` 相同，兼容旧调用方
    public static func capture(from board: NSPasteboard) -> PasteboardSnapshot {
        capture(board)
    }

    /// 把快照写回剪贴板（清空后重建 item）
    public func restore(onto board: NSPasteboard) {
        board.clearContents()
        let restored = items.map { types -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in types {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restored.isEmpty {
            board.writeObjects(restored)
        }
    }
}
