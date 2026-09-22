// ClipboardPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickPlatform
import QuickUI
import SwiftUI

/// 剪贴板历史插件
///
/// 监听系统剪贴板变化，自动记录历史条目。
/// 支持搜索、分类（文本/图片/文件）、收藏和快速粘贴。
@MainActor
public final class ClipboardPlugin: QuickPlugin {

    public static let id = "clipboard"
    public static let name = "剪贴板历史"
    public static let icon = "doc.on.clipboard"
    public static let description = "自动记录系统剪贴板历史，支持文本、代码与图片预览，提供快速搜索、置顶收藏与重新复制。"
    public static let triggerWords = ["剪贴板历史", "剪贴板", "剪切板", "剪切", "clipboard", "粘贴板", "历史"]

    /// 面板头部保留搜索框：输入即过滤剪贴板历史
    public static var supportsPanelSearch: Bool { true }

    public var isEnabled = true

    private let log = QuickLog.plugin(ClipboardPlugin.id)

    /// 剪贴板监听器
    private let monitor = ClipboardMonitor()

    /// 剪贴板条目存储
    private let store: ClipboardStore

    /// 设置变化的观察者（`activate()` 挂上，`deactivate()` 摘掉）
    private var settingObserver: NSObjectProtocol?

    /// 剪贴板监听是否正在运行
    ///
    /// 由设置页的「启用剪贴板监听」驱动：开关关掉后这里必须是 false，
    /// 否则用户以为不记录了，剪贴板却还在往历史里写。
    var isMonitoring: Bool { monitor.isRunning }

    /// - Parameter storage: 由 AppCore 注入的存储句柄
    public init(storage: PluginStorage) {
        self.store = ClipboardStore(storage: storage)
    }

    // MARK: - 存储 schema

    /// 剪贴板历史表
    ///
    /// 表结构归插件所有：宿主只负责把它跑一遍，不读这张表。
    /// `(is_pinned, created_at)` 的复合索引对应界面上的排序 —— 置顶在最前，其余按时间倒序。
    public static var storageMigrations: [SQLiteMigration] {
        [
            SQLiteMigration(
                id: "clipboard.history",
                statements: [
                    """
                    CREATE TABLE IF NOT EXISTS clipboard_history (
                        id TEXT PRIMARY KEY,
                        text TEXT NOT NULL DEFAULT '',
                        image_data BLOB,
                        image_size TEXT,
                        type TEXT NOT NULL,
                        is_favorite INTEGER NOT NULL DEFAULT 0,
                        is_pinned INTEGER NOT NULL DEFAULT 0,
                        created_at REAL NOT NULL
                    )
                    """,
                    """
                    CREATE INDEX IF NOT EXISTS idx_clip_order
                        ON clipboard_history(is_pinned DESC, created_at DESC)
                    """,
                    "CREATE INDEX IF NOT EXISTS idx_clip_type ON clipboard_history(type)",
                    "CREATE INDEX IF NOT EXISTS idx_clip_text ON clipboard_history(text)"
                ]),
            // 来源应用：单独的迁移，老库已经有 clipboard_history 表，只能 ALTER 补列。
            // 新库会依次跑这两条 —— CREATE 里不能带这两列，否则这里的 ALTER 会重复。
            SQLiteMigration(
                id: "clipboard.history.source",
                statements: [
                    "ALTER TABLE clipboard_history ADD COLUMN source_app TEXT",
                    "ALTER TABLE clipboard_history ADD COLUMN source_bundle_id TEXT"
                ])
        ]
    }

    // MARK: - QuickPlugin 协议

    public func accepts(query: String) -> Bool {
        query.matchesAnyTrigger(Self.triggerWords)
    }

    public func dynamicSearch(query: String) async -> [SearchableItem] {
        guard !Task.isCancelled else { return [] }
        let items = await searchItems(query: query)
        return items.filter { $0.id != "clipboard.open-panel" }
    }

    public func searchItems(query: String) async -> [SearchableItem] {
        // 仅当搜索词与剪贴板相关时才返回入口
        guard query.matchesAnyTrigger(Self.triggerWords) else { return [] }

        // 剥离触发词后的词才是真正的筛选条件；为空表示列出最近几条
        let keyword = query.removingTrigger(Self.triggerWords)
        let matches = keyword.isEmpty ? store.entries : store.search(keyword)

        // 关掉「显示内容预览」后标题与副标题都不许出现剪贴板正文 ——
        // 这条设置就是「别在搜索结果里露出我复制过的东西」
        let showsPreview = PluginDefaults.isEnabled(PluginSettingKey.Clipboard.showPreview, default: true)

        var results: [SearchableItem] = []

        // 第一项：打开剪贴板管理器面板（导航到插件模式）
        results.append(
            SearchableItem(
                id: "clipboard.open-panel",
                pluginID: Self.id,
                title: "打开剪贴板管理器",
                subtitle: "查看全部 \(store.entries.count) 条剪贴板历史",
                icon: Self.icon,
                relevance: 0.9,
                action: {
                    EventBus.shared.post(
                        NavigateEvent(pluginID: ClipboardPlugin.id))
                }
            ))

        // 最近的几条文本记录，点击直接复制（图片需进入面板操作）
        let textMatches = matches.filter { $0.type != .image }
        results += textMatches.prefix(5).map { entry in
            let timestamp = entry.timestamp.formatted(date: .abbreviated, time: .shortened)
            return SearchableItem(
                id: "clipboard.\(entry.id)",
                pluginID: Self.id,
                title: showsPreview ? entry.preview : entry.type.displayName,
                // 关掉预览时副标题补上内容类型，否则一行结果只剩时间戳，等于什么都没说
                subtitle: showsPreview ? timestamp : "\(entry.type.displayName) · \(timestamp)",
                icon: entry.type.icon,
                relevance: 0.5,
                action: {
                    EventBus.shared.post(CopyToClipboardEvent(text: entry.text))
                    EventBus.shared.post(HidePaletteEvent())
                }
            )
        }

        return results
    }

    public func makeView() -> AnyView {
        AnyView(ClipboardListView(store: store))
    }

    public func makeSettingsView() -> AnyView? {
        // 配置项由 FeatureSettingsPane 的 ClipboardFeatureSection 统一管理
        nil
    }

    public func activate() {
        monitor.onNewContent = { [weak self] entry in
            self?.store.add(entry)
            // 广播「刚复制过」：面板的自动粘贴靠它判断时间窗。只发时间点，内容谁要谁去读
            EventBus.shared.post(ClipboardChangedEvent())
        }
        observeMonitorSetting()
        applyMonitorSetting()
        log.notice(
            """
            插件已激活：加载 \(self.store.entries.count, privacy: .public) 条历史，\
            剪贴板监听\(self.isMonitoring ? "已启动" : "已按设置关闭", privacy: .public)
            """)
    }

    public func deactivate() {
        if let settingObserver {
            NotificationCenter.default.removeObserver(settingObserver)
        }
        settingObserver = nil
        monitor.stop()
        if clearsHistoryOnQuit {
            store.clearHistory()
            log.notice("已按设置清空剪贴板历史，收藏与置顶条目保留")
        }
        store.save()
        log.notice("插件已停用，剪贴板监听已停止，历史已落盘")
    }

    // MARK: - 设置

    /// 设置页上的「启用剪贴板监听」
    private var isMonitorSettingOn: Bool {
        PluginDefaults.isEnabled(PluginSettingKey.Clipboard.monitorEnabled, default: true)
    }

    /// 设置页上的「退出时清除历史」
    private var clearsHistoryOnQuit: Bool {
        PluginDefaults.isEnabled(PluginSettingKey.Clipboard.clearOnQuit, default: false)
    }

    // MARK: - 监听起停

    /// 盯着设置变化
    ///
    /// 开关是运行期可改的，而监听器不能只在 `activate()` 时决定一次 —— 不盯着
    /// `UserDefaults` 的话，用户关掉开关之后剪贴板照旧被记录，这正是这类
    /// 「设置页看着有、实际没人读」缺陷的典型样子。
    private func observeMonitorSetting() {
        guard settingObserver == nil else { return }
        settingObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyMonitorSetting()
            }
        }
    }

    /// 按设置起停监听器
    ///
    /// `start()` 是幂等的，所以这里不必自己记「现在跑着没有」—— 少一份可能与
    /// 设置漂移的状态。
    private func applyMonitorSetting() {
        if isMonitorSettingOn {
            monitor.start()
        } else {
            monitor.stop()
        }
    }
}
