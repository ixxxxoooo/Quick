// PluginPrefill.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 出现时把导航上下文里的文本填进插件输入框
///
/// 主面板搜索、超级面板跳转到插件时可以携带一段文本（`NavigateEvent.context["query"]`），
/// 例如「选中一段 Base64 → 从超级面板打开 Base64 工具」。插件视图通过 `@Environment(\.pluginContext)`
/// 读到它，出现时填进自己的 `TextBuffer`。
///
/// 抽成一个修饰器，是为了让每个插件只在自己的 `makeView()` 上加一行，而不是各自
/// 复刻一遍「读环境 + 判空 + 写入」。
private struct PluginPrefillModifier: ViewModifier {

    @Environment(\.pluginContext) private var context
    let buffer: TextBuffer

    func body(content: Content) -> some View {
        content.task(id: context) {
            guard let query = context["query"], !query.isEmpty else { return }
            buffer.text = query
        }
    }
}

extension View {
    /// 把导航上下文里的 `query` 预填进 `buffer`
    ///
    /// 只有上下文确实带了文本才覆盖 —— 普通打开（没有携带文本）保留上一次的内容。
    public func prefillFromPluginContext(_ buffer: TextBuffer) -> some View {
        modifier(PluginPrefillModifier(buffer: buffer))
    }
}
