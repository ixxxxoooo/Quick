// IconCache.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Synchronization

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

    /// 当前缓存里的图标是按哪套外观出的图
    ///
    /// 位图必须跟着外观走：一部分系统应用的图标在深色/浅色下是两套资源，
    /// 缓存住旧的那套就会在切换主题后继续显示错的那张。
    private static let darkSurface = Mutex(false)

    /// 系统外观变了
    ///
    /// 只有真的翻了面才清缓存 —— `effectiveAppearance` 的通知远多于真实变化
    /// （窗口获得焦点、应用激活都会发），每次清一遍等于把缓存废掉。
    ///
    /// - Parameter isDark: 新的外观是不是深色
    @MainActor
    public static func setDarkSurface(_ isDark: Bool) {
        let changed = darkSurface.withLock { current -> Bool in
            defer { current = isDark }
            return current != isDark
        }
        guard changed else { return }
        shared.clearAll()
    }
}
