// AppIndex.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore

/// 已安装应用索引
///
/// 扫描系统中已安装的应用程序，建立搜索索引。
/// 按名称搜索，支持模糊匹配与拼音（全拼、首字母）。
@MainActor
public final class AppIndex {

    /// 已索引的应用条目
    public private(set) var apps: [AppEntry] = []

    /// 是否正在扫描中
    public private(set) var isScanning = false

    private let log = QuickLog.platform

    /// 当前应用搜索目录
    public private(set) var searchScopes: [String] = SearchScopes.defaults

    /// 目录变动监听器
    private var directoryWatcher: AppDirectoryWatcher?

    /// 记录各扫描目录最近的修改时间戳，用于极轻量级变化检查
    private var lastScannedTimestamps: [String: Date] = [:]

    /// 是否开启目录自动监听（测试时可设为 false）
    public let autoWatch: Bool

    public init(scopes: [String]? = nil, autoWatch: Bool = true) {
        self.autoWatch = autoWatch
        if let scopes {
            self.searchScopes = scopes
        }
    }

    deinit {
        directoryWatcher?.stop()
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

        // 记录各目录 modificationDate
        for path in expandedPaths {
            if let attr = try? FileManager.default.attributesOfItem(atPath: path),
                let mtime = attr[.modificationDate] as? Date
            {
                lastScannedTimestamps[path] = mtime
            }
        }

        // 维护应用目录实时监听
        if autoWatch {
            if let watcher = directoryWatcher {
                watcher.update(paths: expandedPaths)
            } else {
                directoryWatcher = AppDirectoryWatcher(paths: expandedPaths) { [weak self] in
                    Task { @MainActor in
                        await self?.refresh()
                    }
                }
            }
        }

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

    /// 检查各应用目录的最近修改时间戳，若发现有新变动则自动刷新
    public func checkAndRefreshIfNeeded() async {
        guard !isScanning else { return }
        let expandedPaths = searchScopes.map { SearchScopes.expand($0) }
        var needsRefresh = false
        for path in expandedPaths {
            if let attr = try? FileManager.default.attributesOfItem(atPath: path),
                let mtime = attr[.modificationDate] as? Date
            {
                if let recorded = lastScannedTimestamps[path] {
                    if mtime > recorded {
                        needsRefresh = true
                        break
                    }
                } else {
                    needsRefresh = true
                    break
                }
            }
        }
        if needsRefresh {
            log.notice("检测到应用目录修改时间已变更，自动触发刷新")
            await refresh()
        }
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
                if let bundle = Bundle(url: url), isUserFacingApplication(bundle: bundle, url: url) {
                    let entry = makeAppEntry(bundle: bundle, url: url, isSystem: path.hasPrefix("/System"))
                    results.append(entry)
                }
                continue
            }

            let isShallowCoreServices =
                path.hasPrefix("/System/Library/CoreServices") && !path.contains("/Applications")
            let options: FileManager.DirectoryEnumerationOptions =
                isShallowCoreServices
                ? [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
                : [.skipsHiddenFiles, .skipsPackageDescendants]

            guard
                let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isApplicationKey],
                    options: options
                )
            else {
                QuickLog.platform.debug("应用目录不可枚举，已跳过：\(path, privacy: .public)")
                continue
            }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "app" else { continue }
                guard let bundle = Bundle(url: fileURL) else { continue }
                guard isUserFacingApplication(bundle: bundle, url: fileURL) else { continue }
                let entry = makeAppEntry(bundle: bundle, url: fileURL, isSystem: path.hasPrefix("/System"))
                results.append(entry)
            }
        }

        return results
    }

    /// 校验该 Bundle 是否为面向用户的应用程序（排除系统内部后台服务、Agent 与无 UI 进程）
    nonisolated private static func isUserFacingApplication(bundle: Bundle, url: URL) -> Bool {
        let path = url.path
        let info = bundle.infoDictionary ?? [:]

        // 1. 排除无 UI 的纯后台工具（如 AddressBookUrlForwarder）
        if let bg = info["LSBackgroundOnly"] {
            let s = "\(bg)".trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if s == "1" || s == "true" { return false }
        }

        // 2. 系统目录（/System）下排除内部 UIElement 代理与后台服务（如 FileProvider-Feedback, LaunchPolicyAlertAgent）
        if path.hasPrefix("/System/") {
            if let ui = info["LSUIElement"] {
                let s = "\(ui)".trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if s == "1" || s == "true" { return false }
            }
            let fileName = url.lastPathComponent
            if fileName.hasSuffix("Agent.app") || fileName.hasSuffix("Service.app") || fileName.hasSuffix("Helper.app") {
                return false
            }
        }

        return true
    }

    nonisolated private static func makeAppEntry(bundle: Bundle, url: URL, isSystem: Bool) -> AppEntry {
        let fileName = url.deletingPathExtension().lastPathComponent
        let localizedDisplayName = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
        let localizedName = bundle.localizedInfoDictionary?["CFBundleName"] as? String
        let baseDisplayName = bundle.infoDictionary?["CFBundleDisplayName"] as? String
        let baseName = bundle.infoDictionary?["CFBundleName"] as? String

        let primaryName = localizedDisplayName ?? baseDisplayName ?? localizedName ?? baseName ?? fileName
        var alternateNames: [String] = []
        for candidate in [localizedDisplayName, baseDisplayName, localizedName, baseName, fileName] {
            if let candidate, !candidate.isEmpty, candidate != primaryName, !alternateNames.contains(candidate) {
                alternateNames.append(candidate)
            }
        }

        let bundleID = bundle.bundleIdentifier ?? url.path
        return AppEntry(
            id: bundleID,
            name: primaryName,
            bundleID: bundleID,
            path: url.path,
            isSystemApp: isSystem,
            alternateNames: alternateNames
        )
    }

    /// 搜索应用
    /// - Parameter query: 搜索关键词
    /// - Returns: 匹配的应用条目（按相关度排序）
    public func search(query: String) -> [AppEntry] {
        let matchQuery = MatchQuery(query)
        guard !matchQuery.isEmpty else { return apps }

        return
            apps
            .map { entry -> (AppEntry, Double) in
                var score = matchQuery.score(entry.matchText)
                for alt in entry.alternateMatchTexts {
                    score = max(score, matchQuery.score(alt) * 0.95)
                }
                return (entry, score)
            }
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

    /// 主名称的匹配形态
    ///
    /// 折叠与拼音转写在扫描时算好一次 —— 索引有上百条，每次按键都重算一遍是浪费。
    public let matchText: MatchText

    /// 备用名称（如 Bundle 原始名、文件包名）的匹配形态
    public let alternateMatchTexts: [MatchText]

    public init(
        id: String,
        name: String,
        bundleID: String,
        path: String,
        isSystemApp: Bool,
        alternateNames: [String] = []
    ) {
        self.id = id
        self.name = name
        self.bundleID = bundleID
        self.path = path
        self.isSystemApp = isSystemApp
        self.matchText = MatchText(name)
        self.alternateMatchTexts = alternateNames
            .filter { !$0.isEmpty && $0 != name }
            .map { MatchText($0) }
    }

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
