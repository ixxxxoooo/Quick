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
    case timestamp(original: String, formatted: String, relative: String)
    case base64(decoded: String)
    case urlEncoded(decoded: String)
    case math(expr: String, result: String)
    case email(email: String)
    case ip(address: String)
    case json(summary: String, lineCount: Int)
    case sql(statement: String, lineCount: Int)
    case phone(formatted: String)
    case translation(source: String, detectedLang: String)
    case plainText(summary: String, charCount: Int)

    /// Spotlight 卡片标题
    public var title: String {
        switch self {
        case .url: "网址"
        case .filePath: "文件路径"
        case .color: "颜色"
        case .timestamp: "时间戳"
        case .base64: "Base64"
        case .urlEncoded: "URL 编码"
        case .math: "计算结果"
        case .email: "邮箱"
        case .ip: "IP 地址"
        case .json: "JSON"
        case .sql: "SQL"
        case .phone: "电话"
        case .translation(_, let lang): lang == "en" ? "英文文本" : "中文文本"
        case .plainText: "文本"
        }
    }

    /// Spotlight 卡片副标题 / 预览摘要
    public var detail: String {
        switch self {
        case .url(let url, _): url
        case .filePath(let path, let exists, _): exists ? path : "\(path)（不存在）"
        case .color(let hex, let rgb): "\(hex) · \(rgb)"
        case .timestamp(_, let formatted, let relative): "\(formatted) · \(relative)"
        case .base64(let decoded): decoded
        case .urlEncoded(let decoded): decoded
        case .math(let expr, let result): "\(expr) = \(result)"
        case .email(let email): email
        case .ip(let address): address
        case .json(let summary, let lines): "\(summary) · \(lines) 行"
        case .sql(let statement, let lines): "\(statement) · \(lines) 行"
        case .phone(let formatted): formatted
        case .translation(let source, _): source
        case .plainText(let summary, let count): "\(summary)（\(count) 字）"
        }
    }

    /// SF Symbol
    public var icon: String {
        switch self {
        case .url: "link"
        case .filePath: "folder"
        case .color: "paintpalette"
        case .timestamp: "clock"
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
        case .timestamp: "Time"
        case .base64: "Base64"
        case .urlEncoded: "URL"
        case .math: "Calc"
        case .email: "Email"
        case .ip: "IP"
        case .json: "JSON"
        case .sql(let statement, _): statement
        case .phone: "Phone"
        case .translation(_, let lang): lang.uppercased()
        case .plainText: "Text"
        }
    }

    /// 是否为「有意义」的预览（非纯文本兜底）
    public var isMeaningful: Bool {
        if case .plainText = self { return false }
        return true
    }
}
