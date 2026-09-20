// OCRText.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// OCR 识别结果的文本拼装
///
/// Vision 逐条返回文本观测，插件再把它们拼成一段多行文本。拼接规则是纯逻辑，
/// 单独放进模型层，测试才能不启动 Vision 就固定住结果形状。
public enum OCRText {

    /// 把多条识别结果拼成一段文本
    ///
    /// 顺序即观测顺序（Vision 已按阅读顺序返回），这里不做重排；
    /// 空观测原样保留，于是相邻空观测会留下空行 —— 这是现状行为，不是疏漏。
    ///
    /// - Parameter transcripts: 每条观测识别出的文字
    /// - Returns: 用换行连接后的文本；没有观测时返回空串
    public static func joined(_ transcripts: [String]) -> String {
        transcripts.joined(separator: "\n")
    }
}
