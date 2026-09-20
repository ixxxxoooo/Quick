// OCRQuery.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// OCR 插件触发词的匹配
///
/// 触发词按「包含」判断而不是「整词」：中文没有词边界，`帮我识别这段文字` 必须命中
/// `识别`；代价是拉丁字母也会子串命中（`microcre` 里藏着 `ocr`）。这条取舍写在
/// 模型层，测试才能把它固定下来，也顺带成为触发词的唯一真相。
public enum OCRQuery {

    /// 触发词列表（插件对外声明的 triggerWords 就是它）
    public static let triggers = ["ocr", "识别", "文字识别", "截图识别"]

    /// 查询是否在问 OCR
    ///
    /// - Parameter query: 用户在搜索框里输入的原文
    /// - Returns: 命中任一触发词时为 true
    public static func isTriggered(by query: String) -> Bool {
        triggers.contains(where: { query.lowercased().contains($0) })
    }
}
