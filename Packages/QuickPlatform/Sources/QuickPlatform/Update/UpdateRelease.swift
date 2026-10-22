// UpdateRelease.swift
// Quick — 原生 macOS 效率启动器
// @author ixxxxoooo

import Foundation

/// GitHub 上最新发布的版本信息
public struct UpdateRelease: Sendable, Equatable {
    /// 语义化版本号，不含 `v` 前缀
    public let version: String
    /// DMG 下载地址
    public let downloadURL: URL
    /// 发布说明（Markdown 原文）
    public let notes: String

    public init(version: String, downloadURL: URL, notes: String) {
        self.version = version
        self.downloadURL = downloadURL
        self.notes = notes
    }

    /// 解析 GitHub `releases/latest` 的响应
    /// - Parameter data: 响应体 JSON
    /// - Returns: 解析出的发布信息；缺少 tag 或 DMG 资源、下载地址不是 github.com 时返回 nil
    public static func parse(_ data: Data) -> UpdateRelease? {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        struct Payload: Decodable {
            let tag_name: String
            let body: String?
            let assets: [Asset]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
            let asset = payload.assets.first(where: { $0.name.hasSuffix(".dmg") }),
            asset.browser_download_url.scheme == "https",
            asset.browser_download_url.host == "github.com"
        else { return nil }
        let version = payload.tag_name.hasPrefix("v") ? String(payload.tag_name.dropFirst()) : payload.tag_name
        return UpdateRelease(version: version, downloadURL: asset.browser_download_url, notes: payload.body ?? "")
    }

    /// 判断 `candidate` 是否比 `current` 新（按点分数字逐段比较，缺位按 0）
    /// - Parameters:
    ///   - candidate: 候选版本号
    ///   - current: 当前版本号
    /// - Returns: 候选版本更新时为 true；任一方含非数字段时为 false
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = candidate.split(separator: ".").map { Int($0) }
        let rhs = current.split(separator: ".").map { Int($0) }
        guard !lhs.contains(nil), !rhs.contains(nil) else { return false }
        let a = lhs.compactMap { $0 }, b = rhs.compactMap { $0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
