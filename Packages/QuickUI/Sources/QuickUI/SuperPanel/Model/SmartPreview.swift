// SmartPreview.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 智能预览结果（对齐 Fasty smart_preview）
///
/// 纯数据：不依赖 AppKit / SwiftUI，可在测试中独立断言。
public enum SmartPreview: Sendable, Equatable {
    case url(url: String, domain: String)
    case filePath(path: String, exists: Bool, isDirectory: Bool)
    case color(hex: String, rgb: String)
    case timestamp(
        original: String,
        formatted: String,
        relative: String,
        unixSeconds: String? = nil,
        unixMilliseconds: String? = nil,
        localTime: String? = nil,
        isFromDateString: Bool = false
    )
    case base64(decoded: String)
    case urlEncoded(decoded: String)
    case math(expr: String, result: String)
    case email(email: String)
    case ip(address: String)
    case json(summary: String, lineCount: Int)
    case sql(statement: String, lineCount: Int)
    case phone(formatted: String)
    case translation(
        source: String,
        detectedLang: String,
        translated: String? = nil,
        phonetic: String? = nil,
        senses: [String]? = nil
    )
    case plainText(summary: String, charCount: Int)

    /// Spotlight 卡片标题
    public var title: String {
        switch self {
        case .url: "网址"
        case .filePath: "文件路径"
        case .color: "颜色"
        case .timestamp(_, _, _, _, _, _, let isFromDateString): isFromDateString ? "时间文本" : "时间戳"
        case .base64: "Base64"
        case .urlEncoded: "URL 编码"
        case .math: "计算结果"
        case .email: "邮箱"
        case .ip: "IP 地址"
        case .json: "JSON"
        case .sql: "SQL"
        case .phone: "电话"
        case .translation(_, let lang, let translated, _, _):
            translated != nil
                ? (lang == "en" ? "英文翻译" : "翻译")
                : (lang == "en" ? "英文文本" : "中文文本")
        case .plainText: "文本"
        }
    }

    /// Spotlight 卡片副标题 / 预览摘要
    public var detail: String {
        switch self {
        case .url(let url, _): url
        case .filePath(let path, let exists, _): exists ? path : "\(path)（不存在）"
        case .color(let hex, let rgb): "\(hex) · \(rgb)"
        case .timestamp(_, let formatted, let relative, let unixSeconds, _, _, let isFromDateString):
            isFromDateString ? "\(unixSeconds ?? formatted) · \(relative)" : "\(formatted) · \(relative)"
        case .base64(let decoded): decoded
        case .urlEncoded(let decoded): decoded
        case .math(let expr, let result): "\(expr) = \(result)"
        case .email(let email): email
        case .ip(let address): address
        case .json(let summary, let lines): "\(summary) · \(lines) 行"
        case .sql(let statement, let lines): "\(statement) · \(lines) 行"
        case .phone(let formatted): formatted
        case .translation(let source, _, let translated, _, _): translated ?? source
        case .plainText(let summary, let count): "\(summary)（\(count) 字）"
        }
    }

    /// SF Symbol
    public var icon: String {
        switch self {
        case .url: "link"
        case .filePath: "folder"
        case .color: "paintpalette"
        case .timestamp(_, _, _, _, _, _, let isFromDateString): isFromDateString ? "calendar" : "clock"
        case .base64: "lock.rectangle"
        case .urlEncoded: "percent"
        case .math: "plus.forwardslash.minus"
        case .email: "envelope"
        case .ip: "network"
        case .json: "curlybraces"
        case .sql: "cylinder"
        case .phone: "phone"
        case .translation: "character.book.closed"
        case .plainText: "text.alignleft"
        }
    }

    /// 类型徽章（列表右侧短标签）
    public var badge: String {
        switch self {
        case .url(_, let domain): domain
        case .filePath(_, _, let isDir): isDir ? "目录" : "文件"
        case .color: "HEX"
        case .timestamp(_, _, _, _, _, _, let isFromDateString): isFromDateString ? "Date" : "Time"
        case .base64: "Base64"
        case .urlEncoded: "URL"
        case .math: "Calc"
        case .email: "Email"
        case .ip: "IP"
        case .json: "JSON"
        case .sql(let statement, _): statement
        case .phone: "Phone"
        case .translation(_, let lang, _, _, _): lang.uppercased()
        case .plainText: "Text"
        }
    }

    /// 是否为「有意义」的预览（非纯文本兜底）
    public var isMeaningful: Bool {
        if case .plainText = self { return false }
        return true
    }

    // MARK: - 面板展示用（纯文本，视图与控制器共用）

    /// 是否值得单独占一块「预览卡」
    ///
    /// 网址 / 算式 / 邮箱 / IP / 电话这类预览，答案一行就说完了，直接由第一个动作的副标题
    /// 带出，不再多占一块卡片的高度；文件、颜色、JSON、解码结果等有多行信息的才出卡。
    public var hasRichDetail: Bool {
        switch self {
        case .filePath, .color, .base64, .urlEncoded, .json, .sql, .timestamp, .translation: true
        case .url, .math, .email, .ip, .phone, .plainText: false
        }
    }

    /// 主标题：直接给「答案」，而不是类型标签
    public var headline: String {
        switch self {
        case .url(_, let domain): domain
        case .filePath(let path, _, _): (path as NSString).lastPathComponent
        case .color(let hex, _): hex
        case .timestamp(_, let formatted, _, let unixSeconds, _, _, let isFromDateString):
            isFromDateString ? (unixSeconds ?? formatted) : formatted
        case .math(_, let result): result
        case .email(let email): email
        case .ip(let address): address
        case .phone(let formatted): formatted
        case .base64: "Base64"
        case .urlEncoded: "URL 编码"
        case .json(let summary, let lines): "\(summary) · \(lines) 行"
        case .sql(let statement, let lines): "\(statement) · \(lines) 行"
        case .translation(let source, _, let translated, _, _): translated ?? source
        case .plainText: "文本"
        }
    }

    /// 副标题：补充说明，没有可补充的就是 nil
    public var subheadline: String? {
        switch self {
        case .url(let url, _): return url
        case .filePath(let path, _, _): return path
        case .color(_, let rgb): return rgb
        case .timestamp(let original, _, let relative, _, _, _, _): return "\(relative) · \(original)"
        case .math(let expr, _): return expr
        case .translation(let source, _, let translated, let phonetic, _):
            if let phonetic, !phonetic.isEmpty { return "\(phonetic) · \(source)" }
            return translated != nil ? source : nil
        case .base64, .urlEncoded, .json, .sql, .email, .ip, .phone, .plainText:
            return nil
        }
    }

    /// 「复制」该预览时应写入剪贴板的文本；`sourceText` 是兜底的原文
    public func copyText(sourceText: String) -> String {
        switch self {
        case .translation(_, _, let translated, _, _): translated ?? sourceText
        case .math(_, let result): result
        case .timestamp(_, let formatted, _, let unixSeconds, _, _, let isFromDateString):
            isFromDateString ? (unixSeconds ?? formatted) : formatted
        case .color(let hex, _): hex
        case .base64(let decoded), .urlEncoded(let decoded): decoded
        case .filePath(let path, _, _): path
        case .url(let url, _): url
        case .email(let email): email
        case .ip(let address): address
        case .phone(let formatted): formatted
        case .json, .sql, .plainText: sourceText
        }
    }
}
