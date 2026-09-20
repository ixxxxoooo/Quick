// MarkdownPreviewLogic.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// Markdown 预览的纯逻辑
///
/// 这个工具几乎没有可抽取的转换逻辑：预览是把原始字符串直接交给
/// `Text(LocalizedStringKey(_:))` 渲染的（Foundation 的 markdown 解析在 SwiftUI 内部），
/// 本工具自己不做 Markdown → 纯文本 / HTML 的变换。
///
/// 因此这里只放真正存在的逻辑 —— 工具栏那行字符统计：什么时候显示、显示成什么样。
/// 抽出来是为了能脱离界面测试（尤其是它按 Swift 的 Character 计数，
/// 而不是按 UTF-16 码元，emoji 和组合字形的结果完全不同）。
enum MarkdownPreviewLogic {

    /// 工具栏字符统计文案
    ///
    /// - Parameter text: 编辑器里的文本
    /// - Returns: 形如 `"42 字符"` 的文案；文本为空时返回 nil（此时不显示统计）
    static func characterCountLabel(for text: String) -> String? {
        guard !text.isEmpty else { return nil }
        return "\(text.count) 字符"
    }
}
