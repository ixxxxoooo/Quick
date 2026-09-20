// CalculatorModule.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 计算器模块
///
/// 在搜索框中直接输入数学表达式即可计算。
/// 支持基础四则运算、括号、百分比、单位换算和货币转换。
@MainActor
public final class CalculatorModule: QuickModule {

    public static let id = "calculator"
    public static let name = "计算器"
    public static let icon = "plus.forwardslash.minus"

    public var isEnabled = true

    /// 计算引擎
    private let engine = CalcEngine()

    public init() {}

    // MARK: - QuickModule 协议

    public func searchItems(query: String) async -> [SearchableItem] {
        guard let result = engine.evaluate(query) else { return [] }

        return [
            SearchableItem(
                id: "calc.result",
                moduleID: Self.id,
                title: result.formatted,
                subtitle: query,
                icon: "equal.circle.fill",
                relevance: 0.95, // 计算结果优先级高
                shortcutHint: "⏎ 复制",
                action: {
                    EventBus.shared.post(CopyToClipboardEvent(text: result.formatted))
                }
            )
        ]
    }

    public func makeView() -> AnyView {
        AnyView(CalculatorView(engine: engine))
    }
}
