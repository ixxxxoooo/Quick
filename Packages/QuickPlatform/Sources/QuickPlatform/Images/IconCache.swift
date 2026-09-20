// IconCache.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit

/// 应用图标缓存
///
/// 缓存已加载的应用图标，避免重复读取文件系统。
/// 支持深色/浅色模式切换时清除缓存。
@MainActor
public final class IconCache {

    /// 全局单例
    public static let shared = IconCache()

    /// 图标缓存（key: bundle path 或 bundle ID）
    private var cache: [String: NSImage] = [:]

    /// 缓存大小上限
    private let maxCacheSize = 500

    private init() {}

    /// 获取应用图标
    /// - Parameter bundlePath: 应用 Bundle 路径
    /// - Returns: 应用图标（缓存命中或从文件系统加载）
    public func icon(forBundlePath bundlePath: String) -> NSImage? {
        if let cached = cache[bundlePath] {
            return cached
        }

        let icon = NSWorkspace.shared.icon(forFile: bundlePath)
        icon.size = NSSize(width: 32, height: 32)

        if cache.count >= maxCacheSize {
            // 简单 LRU：清除一半缓存
            let keys = Array(cache.keys.prefix(maxCacheSize / 2))
            for key in keys { cache.removeValue(forKey: key) }
        }

        cache[bundlePath] = icon
        return icon
    }

    /// 获取应用图标（通过 Bundle ID）
    /// - Parameter bundleID: 应用 Bundle Identifier
    /// - Returns: 应用图标
    public func icon(forBundleID bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] {
            return cached
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }

        return icon(forBundlePath: url.path)
    }

    /// 清除所有缓存（外观模式切换时调用）
    public func clearAll() {
        cache.removeAll()
    }
}
