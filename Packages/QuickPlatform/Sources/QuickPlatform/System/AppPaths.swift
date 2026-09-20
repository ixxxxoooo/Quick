// AppPaths.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 应用路径管理。
///
/// 目录名取自 `Bundle.main.bundleIdentifier`，因此 Debug（`com.ygw.quick.dev`）
/// 与 Release（`com.ygw.quick`）各有一份 Application Support / Caches，互不污染。
public enum AppPaths {

    /// 当前构建的根目录名（= bundle id；测试宿主缺失时回退正式版 id）
    public static var rootFolderName: String {
        Bundle.main.bundleIdentifier ?? "com.ygw.quick"
    }

    /// Application Support 目录（存放用户数据）
    public static func applicationSupport() -> URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(rootFolderName)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Caches 目录（存放缓存数据）
    public static func caches() -> URL {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(rootFolderName)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 日志目录
    public static func logs() -> URL {
        let url = applicationSupport().appendingPathComponent("Logs")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 插件数据目录
    /// - Parameter pluginID: 插件唯一标识
    /// - Returns: 插件专属数据目录
    public static func pluginData(_ pluginID: String) -> URL {
        let url = applicationSupport().appendingPathComponent("Plugins").appendingPathComponent(pluginID)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
