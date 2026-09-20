// ClipboardEntry.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 剪贴板条目
///
/// 表示一条剪贴板历史记录，支持文本和图片两类内容。
public struct ClipboardEntry: Identifiable, Codable, Sendable {

    /// 唯一 ID
    public let id: UUID

    /// 文本内容（图片类型时为空字符串）
    public let text: String

    /// 图片数据（仅图片类型时有值）
    ///
    /// 以 PNG 格式存储。磁盘上的条目可能很大，
    /// 但剪贴板历史的最大条目数已有上限保护。
    public let imageData: Data?

    /// 图片尺寸描述（如 "1920×1080"）
    public let imageSizeDescription: String?

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
        if type == .image {
            return "📷 图片 \(imageSizeDescription ?? "")"
        }
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
        case image = "image"

        /// 对应的 SF Symbol 图标
        public var icon: String {
            switch self {
            case .text: "doc.text"
            case .url: "link"
            case .code: "curlybraces"
            case .color: "paintpalette"
            case .image: "photo"
            }
        }

        /// 中文显示名
        public var displayName: String {
            switch self {
            case .text: "文本"
            case .url: "链接"
            case .code: "代码"
            case .color: "颜色"
            case .image: "图片"
            }
        }
    }

    /// 创建文本类条目
    public init(text: String, type: ContentType = .text) {
        self.id = UUID()
        self.text = text
        self.type = type
        self.timestamp = Date()
        self.isFavorite = false
        self.isPinned = false
        self.imageData = nil
        self.imageSizeDescription = nil
    }

    /// 创建图片条目
    public init(imageData: Data, sizeDescription: String) {
        self.id = UUID()
        self.text = ""
        self.type = .image
        self.timestamp = Date()
        self.isFavorite = false
        self.isPinned = false
        self.imageData = imageData
        self.imageSizeDescription = sizeDescription
    }

    /// 从数据库的一行还原
    ///
    /// 与上面两个初始化器不同，这个不生成新 id、不覆盖时间戳 —— 它还原的是已经存在过的
    /// 条目，任何「当作新条目」的默认值都会让历史在每次读取时漂移。
    init(
        id: UUID,
        text: String,
        imageData: Data?,
        imageSizeDescription: String?,
        type: ContentType,
        timestamp: Date,
        isFavorite: Bool,
        isPinned: Bool
    ) {
        self.id = id
        self.text = text
        self.imageData = imageData
        self.imageSizeDescription = imageSizeDescription
        self.type = type
        self.timestamp = timestamp
        self.isFavorite = isFavorite
        self.isPinned = isPinned
    }
}
