// SearchScopes.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 启动器应用搜索范围管理
public enum SearchScopes {

    /// 初始默认搜索目录列表
    public static let defaults: [String] = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        "~/Applications",
        "/System/Library/CoreServices"
    ]

    /// 路径以 ~ 缩写表示（便于多设备或多用户下配置持久化）
    public static func abbreviate(_ path: String) -> String {
        let trimmed = trimTrailingSlash(path)
        return (trimmed as NSString).abbreviatingWithTildeInPath
    }

    /// 将 ~ 展开为完整绝对路径
    public static func expand(_ path: String) -> String {
        (trimTrailingSlash(path) as NSString).expandingTildeInPath
    }

    /// 规范化路径列表（去除空项、去重、保持顺序）
    public static func normalize(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.map(abbreviate).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func trimTrailingSlash(_ path: String) -> String {
        var path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}
