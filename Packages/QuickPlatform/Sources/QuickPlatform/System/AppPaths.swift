// AppPaths.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 应用路径管理
///
/// 统一管理应用的数据存储目录和文件路径。
public enum AppPaths {

    /// Application Support 目录（存放用户数据）
    public static func applicationSupport() -> URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Quick")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Caches 目录（存放缓存数据）
    public static func caches() -> URL {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Quick")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 日志目录
    public static func logs() -> URL {
        let url = applicationSupport().appendingPathComponent("Logs")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 模块数据目录
    /// - Parameter moduleID: 模块唯一标识
    /// - Returns: 模块专属数据目录
    public static func moduleData(_ moduleID: String) -> URL {
        let url = applicationSupport().appendingPathComponent("Modules").appendingPathComponent(moduleID)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
