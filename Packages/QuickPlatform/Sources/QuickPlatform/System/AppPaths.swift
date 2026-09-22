// AppPaths.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 应用路径管理。
///
/// 目录名取自 `Bundle.main.bundleIdentifier`，因此 Debug（`com.ixxxxoooo.quick.dev`）
/// 与 Release（`com.ixxxxoooo.quick`）各有一份 Application Support / Caches，互不污染。
public enum AppPaths {

    /// 当前构建的根目录名（= bundle id；测试宿主缺失时回退正式版 id）
    public static var rootFolderName: String {
        Bundle.main.bundleIdentifier ?? "com.ixxxxoooo.quick"
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

    /// 数据库文件
    ///
    /// 全应用一个库：插件的批量数据与插件键值都在里面。集中在一处是为了让
    /// 「备份 Quick」等于「拷一个文件」，而不是记住一串散落的 json 路径。
    public static func database() -> URL {
        applicationSupport().appendingPathComponent("quick.db")
    }
}
