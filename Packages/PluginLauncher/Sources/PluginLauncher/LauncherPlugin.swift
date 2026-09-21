// LauncherPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickPlatform
import QuickUI
import SwiftUI

/// 应用启动器插件
///
/// 核心插件，提供主搜索入口。扫描系统已安装应用，
/// 支持模糊搜索、拼音匹配、使用频率排序、收藏等功能。
@MainActor
public final class LauncherPlugin: QuickPlugin {

    public static let id = "launcher"
    public static let name = "应用启动器"
    public static let icon = "magnifyingglass"
    public static let triggerWords = ["应用", "app", "打开", "open", "启动", "launch"]

    public var isEnabled = true

    private let log = QuickLog.plugin(LauncherPlugin.id)

    /// 应用索引（由 AppCore 注入）
    private let appIndex: AppIndex

    /// 用户设置存储（可选，用于别名、自定义命令与 Shell 兜底）
    private let settingsStore: SettingsStore?

    /// 使用频率排序
    private let rankingStore: RankingStore

    /// 收藏应用
    private let favoritesStore: FavoritesStore

    /// 初始化启动器插件
    /// - Parameters:
    ///   - appIndex: 应用索引服务
    ///   - settingsStore: 用户设置存储
    ///   - storage: 由 AppCore 注入的存储句柄（使用频率与收藏共用同一个库）
    public init(appIndex: AppIndex, settingsStore: SettingsStore? = nil, storage: PluginStorage) {
        self.appIndex = appIndex
        self.settingsStore = settingsStore
        self.rankingStore = RankingStore(storage: storage)
        self.favoritesStore = FavoritesStore(storage: storage)
    }

    // MARK: - 存储 schema

    /// 启动器自己的两张表
    ///
    /// 表结构归插件所有：宿主只负责把它跑一遍，不读这两张表。
    /// 「使用频率」是高频自增的小表，「收藏」靠 `sort_order` 记住用户排定的顺序。
    public static var storageMigrations: [SQLiteMigration] {
        [
            SQLiteMigration(
                id: "launcher.usage_stats",
                statements: [
                    """
                    CREATE TABLE IF NOT EXISTS usage_stats (
                        item_id TEXT PRIMARY KEY,
                        count INTEGER NOT NULL DEFAULT 0,
                        last_used REAL
                    )
                    """
                ]),
            SQLiteMigration(
                id: "launcher.favorites",
                statements: [
                    """
                    CREATE TABLE IF NOT EXISTS favorites (
                        item_id TEXT PRIMARY KEY,
                        sort_order INTEGER NOT NULL DEFAULT 0,
                        created_at REAL NOT NULL
                    )
                    """,
                    "CREATE INDEX IF NOT EXISTS idx_favorites_order ON favorites(sort_order)"
                ])
        ]
    }

    // MARK: - QuickPlugin 协议

    /// 空查询时不要返回全部应用，避免首屏加载过多图标
    public func searchItems(query: String) async -> [SearchableItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // 空查询：展示应用列表（收藏置顶，其余应用按使用频率排序）
            let favorites = Set(favoritesStore.favoriteIDs)
            let favApps = appIndex.apps.filter { favorites.contains($0.bundleID) }
            let otherApps = appIndex.apps.filter { !favorites.contains($0.bundleID) }
            let sortedOther = otherApps.sorted {
                rankingStore.score(for: $0.bundleID) > rankingStore.score(for: $1.bundleID)
            }
            let source = Array((favApps + sortedOther).prefix(50))
            return source.map { entry in
                SearchableItem(
                    id: "launcher.\(entry.id)",
                    pluginID: Self.id,
                    title: entry.name,
                    // 副标题只留**额外信息**（收藏标记）。「应用程序」这类说明与右侧的
                    // 「应用启动器」徽章是同一件事，一行里写两遍只是噪音
                    subtitle: favorites.contains(entry.bundleID) ? "★ 收藏应用" : nil,
                    icon: "app",
                    iconType: .appIcon(entry.path),
                    relevance: favorites.contains(entry.bundleID) ? 1.0 : 0.5,
                    action: { [weak self] in
                        entry.launch()
                        self?.rankingStore.recordUsage(entry.bundleID)
                        EventBus.shared.post(HidePaletteEvent())
                    }
                )
            }
        }

        // 1. 如果以 '>' 开头，直接作为 Shell 命令执行
        if trimmed.hasPrefix(">") {
            let cmd = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            if !cmd.isEmpty {
                return [
                    SearchableItem(
                        id: "launcher.shell.direct",
                        pluginID: Self.id,
                        title: "运行 Shell: \(cmd)",
                        subtitle: "在 /bin/zsh 中执行",
                        icon: "terminal",
                        relevance: 1.0,
                        action: {
                            EventBus.shared.post(HidePaletteEvent())
                            Task {
                                let result = await ShellCommandRunner.run(cmd)
                                EventBus.shared.post(
                                    ShowHUDEvent(
                                        message: String(result.summary.prefix(80)),
                                        tone: result.succeeded ? .success : .warning
                                    )
                                )
                            }
                        }
                    )
                ]
            }
        }

        var items: [SearchableItem] = []

        // 一个查询词只折叠一次，下面两轮搜索都复用它
        let matchQuery = MatchQuery(trimmed)

        // 2. 自定义命令搜索
        if let customCommandsData = settingsStore?.customCommandsData,
            let customCommands = try? JSONDecoder().decode([CustomCommand].self, from: customCommandsData)
        {
            for cmd in customCommands where cmd.isEnabled {
                var score = matchQuery.score(cmd.name.matchText)
                if let alias = cmd.alias, !alias.isEmpty {
                    score = max(score, matchQuery.score(alias.matchText))
                }
                guard score > 0 else { continue }

                items.append(
                    SearchableItem(
                        id: "launcher.cmd.\(cmd.id.uuidString)",
                        pluginID: Self.id,
                        title: cmd.name,
                        subtitle: cmd.alias != nil ? "别名: \(cmd.alias!) · \(cmd.command)" : cmd.command,
                        icon: "terminal",
                        relevance: score,
                        action: {
                            EventBus.shared.post(HidePaletteEvent())
                            Task {
                                let result = await ShellCommandRunner.run(
                                    cmd.command,
                                    workingDirectory: cmd.workingDirectory
                                )
                                EventBus.shared.post(
                                    ShowHUDEvent(
                                        message: String(result.summary.prefix(80)),
                                        tone: result.succeeded ? .success : .warning
                                    )
                                )
                            }
                        }
                    )
                )
            }
        }

        // 3. 应用搜索（支持自定义别名优先匹配）
        for entry in appIndex.apps {
            let alias = settingsStore?.alias(for: "app." + entry.bundleID)
            var matchScore = matchQuery.score(entry.matchText)
            if let alias, !alias.isEmpty {
                matchScore = max(matchScore, matchQuery.score(alias.matchText))
            }
            guard matchScore > 0 else { continue }

            let ranking = rankingStore.score(for: entry.bundleID)
            let finalScore = matchScore * 0.7 + ranking * 0.3

            let subtitle =
                (alias != nil && !alias!.isEmpty)
                ? "别名: \(alias!) · \(entry.path)"
                : (entry.isSystemApp ? "系统应用" : "应用程序")

            items.append(
                SearchableItem(
                    id: "launcher.\(entry.id)",
                    pluginID: Self.id,
                    title: entry.name,
                    subtitle: subtitle,
                    icon: "app",
                    iconType: .appIcon(entry.path),
                    relevance: finalScore,
                    action: { [weak self] in
                        entry.launch()
                        self?.rankingStore.recordUsage(entry.bundleID)
                        EventBus.shared.post(HidePaletteEvent())
                    }
                )
            )
        }

        // 按相关度降序排列
        items.sort { $0.relevance > $1.relevance }

        var results = Array(items.prefix(19))

        // 4. 如果开启了 Shell 兜底，追加一个兜底执行项（在终端中打开）
        if settingsStore?.isRunShellFallbackEnabled ?? true {
            let commandText = trimmed
            results.append(
                SearchableItem(
                    id: "launcher.shell.fallback",
                    pluginID: Self.id,
                    title: "在终端中运行",
                    subtitle: "$ \(commandText)",
                    icon: "terminal",
                    relevance: 0.01,
                    action: {
                        EventBus.shared.post(HidePaletteEvent())
                        // 读取用户偏好的终端
                        let terminalID =
                            UserDefaults.standard.string(forKey: PluginSettingKey.Shell.preferredTerminal)
                            ?? "com.apple.Terminal"
                        let terminal = PreferredTerminal(rawValue: terminalID) ?? .terminal
                        ShellCommandRunner.runInTerminal(commandText, terminal: terminal)
                    }
                )
            )
        }

        return Array(results.prefix(20))
    }

    /// 首屏不额外贡献条目：它提供的应用列表本身就是首屏主体
    public func defaultItems() async -> [SearchableItem] { [] }

    public func makeView() -> AnyView {
        AnyView(LauncherView(plugin: self))
    }

    public func makeSettingsView() -> AnyView? {
        nil
    }

    public func activate() {
        // 加载已在 init 里完成，这里只汇报
        log.notice(
            """
            插件已激活：收藏 \(self.favoritesStore.favoriteIDs.count, privacy: .public) 个，\
            索引内 \(self.appIndex.apps.count, privacy: .public) 个应用
            """)
    }

    public func deactivate() {
        rankingStore.save()
        log.notice("插件已停用，使用频率已落盘")
    }
}
