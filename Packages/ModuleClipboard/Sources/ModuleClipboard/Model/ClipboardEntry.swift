// ClipboardEntry.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 剪贴板条目
///
/// 表示一条剪贴板历史记录，包含文本内容、类型和时间戳。
public struct ClipboardEntry: Identifiable, Codable, Sendable {

    /// 唯一 ID
    public let id: UUID

    /// 文本内容
    public let text: String

    /// 内容类型
    public let type: ContentType

    /// 记录时间
    public let timestamp: Date

    /// 是否收藏
    public var isFavorite: Bool

    /// 是否置顶
    public var isPinned: Bool

    /// 预览文本（单行，最多 80 个字符）
    ///
    /// 三种换行都要处理：从 Windows/网页复制来的文本常带 `\r\n`，
    /// 只替换 `\n` 会留下一个游离的 `\r`，让预览在列表里显示成断行。
    public var preview: String {
        let flattened =
            text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if flattened.count <= 80 { return flattened }
        return String(flattened.prefix(80)) + "…"
    }

    /// 内容类型
    public enum ContentType: String, Codable, Sendable {
        case text = "text"
        case url = "url"
        case code = "code"
        case color = "color"

        /// 对应的 SF Symbol 图标
        public var icon: String {
            switch self {
            case .text: "doc.text"
            case .url: "link"
            case .code: "curlybraces"
            case .color: "paintpalette"
            }
        }
    }

    public init(text: String, type: ContentType = .text) {
        self.id = UUID()
        self.text = text
        self.type = type
        self.timestamp = Date()
        self.isFavorite = false
        self.isPinned = false
    }
}
