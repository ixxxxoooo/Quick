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

    /// 应用搜索目录
    private let searchPaths: [String] = [
        "/Applications",
        "/System/Applications",
        "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
        "/System/Library/CoreServices"
    ]

    public init() {}

    /// 扫描并刷新应用索引
    public func refresh() async {
        guard !isScanning else { return }
        isScanning = true

        let paths = searchPaths
        let entries: [AppEntry] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var results: [AppEntry] = []
                for path in paths {
                    let url = URL(fileURLWithPath: path)
                    guard let enumerator = FileManager.default.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.isApplicationKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    ) else { continue }

                    for case let fileURL as URL in enumerator {
                        guard fileURL.pathExtension == "app" else { continue }
                        guard let bundle = Bundle(url: fileURL) else { continue }
                        let name = bundle.infoDictionary?["CFBundleName"] as? String
                            ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
                            ?? fileURL.deletingPathExtension().lastPathComponent

                        let bundleID = bundle.bundleIdentifier ?? fileURL.path
                        let entry = AppEntry(
                            id: bundleID,
                            name: name,
                            bundleID: bundleID,
                            path: fileURL.path,
                            isSystemApp: path.hasPrefix("/System")
                        )
                        results.append(entry)
                    }
                }
                continuation.resume(returning: results)
            }
        }

        // 去重（按 Bundle ID）
        var seen = Set<String>()
        apps = entries.filter { seen.insert($0.bundleID).inserted }
        isScanning = false
    }

    /// 搜索应用
    /// - Parameter query: 搜索关键词
    /// - Returns: 匹配的应用条目（按相关度排序）
    public func search(query: String) -> [AppEntry] {
        guard !query.isEmpty else { return apps }
        return apps
            .map { ($0, $0.name.fuzzyScore(query)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
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
                print("[AppIndex] 启动应用失败: \(error.localizedDescription)")
            }
        }
    }
}
