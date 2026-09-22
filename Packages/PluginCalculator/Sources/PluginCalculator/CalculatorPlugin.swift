// CalculatorPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 计算器插件
///
/// 在搜索框中直接输入数学表达式即可计算。
/// 支持基础四则运算、括号、百分比、单位换算和货币转换。
@MainActor
public final class CalculatorPlugin: QuickPlugin {

    public static let id = "calculator"
    public static let name = "计算器"
    public static let icon = "plus.forwardslash.minus"
    public static let description = "在主搜索框中直接输入数学表达式即可快速求值，支持四则运算、函数计算、千分位显示与自动复制结果。"
    public static let triggerWords = ["计算", "calculator", "calc", "算", "="]

    public var isEnabled = true

    private let log = QuickLog.plugin(CalculatorPlugin.id)

    /// 计算引擎
    private let engine = CalcEngine()

    public init() {}

    // MARK: - QuickPlugin 协议

    public func accepts(query: String) -> Bool {
        engine.looksLikeExpression(query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func dynamicSearch(query: String) async -> [SearchableItem] {
        guard !Task.isCancelled else { return [] }
        return await searchItems(query: query)
    }

    public func searchItems(query: String) async -> [SearchableItem] {
        // 每次搜索都重新读设置：用户可能在面板开着的时候刚把小数位数改掉
        let options = CalcPreferences.displayOptions()
        guard let result = engine.evaluate(query, options: options) else { return [] }

        // 复制开关决定回车提示写什么，也在构造结果项的这一刻读
        let autoCopy = CalcPreferences.autoCopy()

        return [
            SearchableItem(
                id: "calculator.result",
                pluginID: Self.id,
                title: result.formatted,
                subtitle: query,
                icon: "equal",
                relevance: 0.95,  // 计算结果优先级高
                shortcutHint: autoCopy ? "⏎ 复制" : "⏎ 完成",
                action: {
                    // 再读一次：从给出结果到按下回车之间，设置页可能已经改过这个开关
                    if CalcPreferences.autoCopy() {
                        EventBus.shared.post(CopyToClipboardEvent(text: result.formatted))
                        EventBus.shared.post(HidePaletteEvent())
                        EventBus.shared.post(
                            ShowHUDEvent(message: "已复制: \(result.formatted)", tone: .success))
                    } else {
                        // 关掉自动复制后回车仍然要能关掉面板（那是「确认」本身），
                        // 但不能再报「已复制」——那会是一句谎话
                        EventBus.shared.post(HidePaletteEvent())
                        EventBus.shared.post(ShowHUDEvent(message: result.formatted, tone: .info))
                    }
                }
            )
        ]
    }

    /// 面板工作状态：主面板与分离窗口共享同一实例，分离时内容不丢
    private let buffer = TextBuffer()

    public func makeView() -> AnyView {
        AnyView(CalculatorView(engine: engine, buffer: buffer))
    }

    public func activate() {
        log.notice("插件已激活")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
