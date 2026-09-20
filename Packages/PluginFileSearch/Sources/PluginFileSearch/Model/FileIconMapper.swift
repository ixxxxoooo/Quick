// FileIconMapper.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 文件扩展名 → SF Symbol 图标
///
/// 纯逻辑：只按名字里的扩展名查表，不碰文件系统也不碰 AppKit 图标。
/// 放在模型层（而不是 FileSearchSession 里），是因为它是搜索结果的展示规则，
/// 应当能脱离 Spotlight 单独验证。
public enum FileIconMapper {

    /// 按文件名给出图标
    ///
    /// 扩展名大小写不敏感；没有扩展名（含 `.gitignore` 这类点开头的隐藏文件）
    /// 一律落到默认图标。
    ///
    /// - Parameter name: 文件名（不是路径）
    /// - Returns: SF Symbol 名称
    public static func icon(forFileName name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext"
        case "jpg", "jpeg", "png", "gif", "webp", "heic": return "photo"
        case "mp4", "mov", "avi": return "film"
        case "mp3", "wav", "aac", "m4a": return "music.note"
        case "zip", "rar", "7z", "tar", "gz": return "archivebox"
        case "swift", "py", "js", "ts", "java", "c", "cpp", "rs":
            return "chevron.left.forwardslash.chevron.right"
        case "md", "txt": return "doc.text"
        case "html", "css": return "globe"
        default: return "doc"
        }
    }
}
