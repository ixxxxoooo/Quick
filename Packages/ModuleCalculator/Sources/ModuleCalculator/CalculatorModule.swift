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
    public static let triggerWords = ["计算", "calculator", "calc", "算", "="]

    public var isEnabled = true

    private let log = QuickLog.module(CalculatorModule.id)

    /// 计算引擎
    private let engine = CalcEngine()

    public init() {}

    // MARK: - QuickModule 协议

    public func searchItems(query: String) async -> [SearchableItem] {
        guard let result = engine.evaluate(query) else { return [] }

        return [
            SearchableItem(
                id: "calculator.result",
                moduleID: Self.id,
                title: result.formatted,
                subtitle: query,
                icon: "equal",
                relevance: 0.95,  // 计算结果优先级高
                shortcutHint: "⏎ 复制",
                action: {
                    EventBus.shared.post(CopyToClipboardEvent(text: result.formatted))
                    EventBus.shared.post(HidePaletteEvent())
                    EventBus.shared.post(ShowHUDEvent(message: "已复制: \(result.formatted)", tone: .success))
                }
            )
        ]
    }

    public func makeView() -> AnyView {
        AnyView(CalculatorView(engine: engine))
    }

    public func activate() {
        log.notice("模块已激活")
    }

    public func deactivate() {
        log.notice("模块已停用")
    }
}
