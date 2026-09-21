// PaletteQuery.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 面板搜索框里的文本
///
/// ## 为什么要单独一个对象，而不是视图里的 `@State`
///
/// 搜索文本必须能被**面板外面**改写：自动粘贴要把剪贴板内容填进来，自动清空要把它抹掉，
/// `show(query:)` 要预填。而 `PaletteRootView` 的 `@State` 只在视图首次出现时读一次
/// `initialQuery` —— 面板是复用同一个 `NSHostingView` 的，所以「打开时传入的查询」
/// 曾经完全到不了输入框（一个真实的 bug）。
///
/// 这个对象是协调器与视图之间**唯一**的查询状态：协调器写、视图读，两边不会各持一份。
///
/// 它只持有纯状态、不持有窗口，所以被 SwiftUI 观察是安全的 —— 会与 AttributeGraph
/// 形成重建死循环的是持有 `NSPanel` 的协调器本身（见 `PaletteCoordinator` 顶部说明）。
@Observable
public final class PaletteQuery {

    /// 输入框里的文本
    public var text: String = "" {
        didSet {
            guard text != oldValue else { return }
            lastEditedAt = Date()
        }
    }

    /// 最后一次改动的时刻
    ///
    /// 由这个对象自己记：文本只有这一个所有者，谁改的（用户输入、自动粘贴、预填）
    /// 都会被算作一次改动，不需要调用方记得去盖时间戳。
    public private(set) var lastEditedAt: Date?

    public init() {}
}
