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
///
/// 每次提交的算式都会落进「计算稿纸」（持久化历史），面板视图里可以看到逐条记录。
@MainActor
public final class CalculatorPlugin: QuickPlugin, PluginViewProviding, PluginSettingsProviding {

    public static let id = "calculator"
    public static let name = "计算器"
    public static let icon = "plus.forwardslash.minus"
    public static let description = "在主搜索框中直接输入数学表达式即可快速求值，支持四则运算、函数计算、千分位显示与自动复制结果。"
    public static let triggerWords = ["计算稿纸", "计算", "calculator", "calc"]

    public static var functionCommands: [CommandDescriptor] {
        [
            CommandDescriptor(
                id: "calculator.history", pluginID: id, pluginName: name, title: "计算历史",
                subtitle: "查看历史计算记录", keywords: ["计算历史", "历史计算"],
                icon: "clock.arrow.circlepath")
        ]
    }

    public var isEnabled = true

    private let log = QuickLog.plugin(CalculatorPlugin.id)

    /// 计算引擎（无状态且 Sendable，可从任意隔离域读）
    private nonisolated let engine = CalcEngine()

    /// 计算历史（计算稿纸）
    private let store: CalcHistoryStore

    /// - Parameter storage: 由 AppCore 注入的存储句柄
    public init(storage: PluginStorage) {
        self.store = CalcHistoryStore(storage: storage)
    }

    // MARK: - 存储 schema

    /// 计算历史表
    ///
    /// 表结构归插件所有：宿主只负责把它跑一遍，不读这张表。
    public static var storageMigrations: [SQLiteMigration] {
        [
            SQLiteMigration(
                id: "calculator.history",
                statements: [
                    """
                    CREATE TABLE IF NOT EXISTS calc_history (
                        id TEXT PRIMARY KEY,
                        expression TEXT NOT NULL,
                        result TEXT NOT NULL,
                        created_at REAL NOT NULL
                    )
                    """,
                    "CREATE INDEX IF NOT EXISTS idx_calc_history_created ON calc_history(created_at DESC)",
                    "CREATE INDEX IF NOT EXISTS idx_calc_history_expression ON calc_history(expression)"
                ])
        ]
    }

    // MARK: - QuickPlugin 协议

    public func accepts(query: String) -> Bool {
        engine.looksLikeExpression(query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public nonisolated func dynamicSearch(query: String) async -> [SearchableItem] {
        guard !Task.isCancelled else { return [] }

        // 每次搜索都重新读设置：用户可能在面板开着的时候刚把小数位数改掉
        let options = CalcPreferences.displayOptions()
        guard let result = engine.evaluate(query, options: options) else { return [] }

        // 复制开关决定回车提示写什么，也在构造结果项的这一刻读
        let autoCopy = CalcPreferences.autoCopy()
        let store = self.store

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
                    // 提交即记入计算稿纸：主搜索回车与面板视图回车走的是同一条历史
                    store.record(expression: query, result: result.formatted)

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
        AnyView(
            CalculatorView(engine: engine, store: store, buffer: buffer)
                .prefillFromPluginContext(buffer))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(CalculatorSettingsView())
    }

    public func activate() {
        log.notice("插件已激活，计算历史 \(self.store.entries.count, privacy: .public) 条")
    }

    public func deactivate() {
        store.save()
        log.notice("插件已停用，计算历史已落盘")
    }
}
