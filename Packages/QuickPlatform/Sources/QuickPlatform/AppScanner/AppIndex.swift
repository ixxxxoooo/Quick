// AppIndex.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore

/// 已安装应用索引
///
/// 扫描系统中已安装的应用程序，建立搜索索引。
/// 支持按名称、Bundle ID 搜索，以及拼音首字母匹配。
@MainActor
public final class AppIndex {

    /// 已索引的应用条目
    public private(set) var apps: [AppEntry] = []

    /// 是否正在扫描中
    public private(set) var isScanning = false

    private let log = QuickLog.platform

    /// 当前应用搜索目录
    public private(set) var searchScopes: [String] = SearchScopes.defaults

    public init(scopes: [String]? = nil) {
        if let scopes {
            self.searchScopes = scopes
        }
    }

    /// 扫描并刷新应用索引
    ///
    /// 磁盘枚举必须离开主线程 —— 冷启动不该被 IO 挡住，所以它跑在 `Task.detached` 上。
    /// - Parameter scopes: 可选的新搜索范围，若提供则更新并以该范围扫描
    public func refresh(scopes: [String]? = nil) async {
        if let scopes {
            self.searchScopes = SearchScopes.normalize(scopes)
        }
        guard !isScanning else {
            log.debug("扫描已在进行中，跳过本次请求")
            return
        }
        isScanning = true
        defer { isScanning = false }

        let expandedPaths = searchScopes.map { SearchScopes.expand($0) }
        let signpost = QuickLog.signposter(QuickLog.Category.platform)
        let interval = signpost.beginInterval("AppIndex.refresh")
        let started = Date()

        let entries = await Task.detached(priority: .userInitiated) {
            AppIndex.scan(searchPaths: expandedPaths)
        }.value

        // 去重（按 Bundle ID）
        var seen = Set<String>()
        apps = entries.filter { seen.insert($0.bundleID).inserted }

        signpost.endInterval("AppIndex.refresh", interval)
        let elapsedMS = Date().timeIntervalSince(started) * 1000
        // notice：扫描结果与耗时是冷启动排障的关键数据，必须落盘。
        log.notice(
            """
            应用扫描完成：扫描 \(entries.count, privacy: .public) 条，\
            去重后 \(self.apps.count, privacy: .public) 条，\
            耗时 \(elapsedMS, format: .fixed(precision: 1)) ms
            """)

        EventBus.shared.post(AppIndexRefreshedEvent())
    }

    /// 在后台枚举磁盘上的 `.app`，返回未去重的条目
    ///
    /// `nonisolated` 是必需的：`AppIndex` 是 `@MainActor`，静态成员默认也继承主 actor 隔离，
    /// 不加这个标注的话 `Task.detached` 里调用它仍会跳回主线程。
    ///
    /// - Parameter searchPaths: 要扫描的目录列表
    /// - Returns: 扫到的应用条目（可能含重复 bundle id）
    nonisolated private static func scan(searchPaths: [String]) -> [AppEntry] {
        var results: [AppEntry] = []

        for path in searchPaths {
            let url = URL(fileURLWithPath: path)
            if url.pathExtension == "app" {
                if let bundle = Bundle(url: url) {
                    let name =
                        bundle.infoDictionary?["CFBundleName"] as? String
                        ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
                        ?? url.deletingPathExtension().lastPathComponent
                    let bundleID = bundle.bundleIdentifier ?? url.path
                    results.append(
                        AppEntry(
                            id: bundleID,
                            name: name,
                            bundleID: bundleID,
                            path: url.path,
                            isSystemApp: path.hasPrefix("/System")
                        )
                    )
                }
                continue
            }

            guard
                let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isApplicationKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
            else {
                QuickLog.platform.debug("应用目录不可枚举，已跳过：\(path, privacy: .public)")
                continue
            }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "app" else { continue }
                guard let bundle = Bundle(url: fileURL) else { continue }
                let name =
                    bundle.infoDictionary?["CFBundleName"] as? String
                    ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
                    ?? fileURL.deletingPathExtension().lastPathComponent

                let bundleID = bundle.bundleIdentifier ?? fileURL.path
                results.append(
                    AppEntry(
                        id: bundleID,
                        name: name,
                        bundleID: bundleID,
                        path: fileURL.path,
                        isSystemApp: path.hasPrefix("/System")
                    )
                )
            }
        }

        return results
    }

    /// 搜索应用
    /// - Parameter query: 搜索关键词
    /// - Returns: 匹配的应用条目（按相关度排序）
    public func search(query: String) -> [AppEntry] {
        guard !query.isEmpty else { return apps }
        return
            apps
            .map { ($0, $0.name.fuzzyScore(query)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// 根据 Bundle ID 获取已索引的应用条目
    public func app(withBundleID bundleID: String) -> AppEntry? {
        apps.first { $0.bundleID == bundleID }
    }
}

/// 应用条目
public struct AppEntry: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let bundleID: String
    public let path: String
    public let isSystemApp: Bool

    /// 启动此应用
    @MainActor
    public func launch() {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.openApplication(
            at: url,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if let error {
                QuickLog.platform.error(
                    """
                    启动应用失败：\(self.name, privacy: .public) \
                    (\(self.bundleID, privacy: .public)) — \
                    \(error.localizedDescription, privacy: .public)
                    """)
            } else {
                QuickLog.platform.info("已启动应用 \(self.name, privacy: .public)")
            }
        }
    }
}
