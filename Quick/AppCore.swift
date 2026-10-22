// AppCore.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import PluginAI
import PluginBase64Codec
import PluginCalculator
import PluginCalendar
import PluginClipboard
import PluginHashCalculator
import PluginJSONFormatter
import PluginKillProcess
import PluginLauncher
import PluginNetworkTools
import PluginSQLFormatter
import PluginScreenshot
import PluginSystemControl
import PluginSystemMonitor
import PluginTextDiff
import PluginTimestampConverter
import PluginTranslator
import PluginURLCodec
import PluginUUIDGenerator

import Carbon.HIToolbox
import Foundation
import QuickCore
import QuickPlatform
import QuickUI
import SwiftUI

/// 应用核心组装器
///
/// AppCore 是整个应用的组装层，职责如下：
/// 1. 创建所有基础设施服务和 Feature Plugin 实例
/// 2. 将依赖注入到各插件
/// 3. 连接 EventBus 的订阅关系
/// 4. 管理全局生命周期（启动/退出）
///
/// AppCore **不持有任何业务逻辑**，不处理搜索、不管理 UI 状态。
@MainActor
final class AppCore {

    /// 全局单例
    static let shared = AppCore()

    let log = QuickLog.app

    // MARK: - 基础设施（不是 Plugin）

    /// 全局快捷键服务
    let hotKeyService = HotKeyService()

    /// 面板协调器
    let paletteCoordinator = PaletteCoordinator()

    /// AI 对话（宿主级：面板里按 Tab 进入；会话与流式生成都归它）
    let aiChat = AIChatController()

    /// 超级面板（宿主级浮层，不是插件）
    let superPanelController = SuperPanelController()

    /// 鼠标唤出监听（右键长按 / 中键单击）
    let mouseTriggerMonitor = MouseTriggerMonitor()

    /// 权限服务
    let permissionService = PermissionService()

    /// 粘贴板服务
    let pasteboardService = PasteboardService()

    /// 合成系统粘贴（⌘V，需要辅助功能权限）
    let pasteService = PasteService()

    /// 应用索引
    let appIndex = AppIndex()

    /// 应用图标缓存（与 `IconCache.shared` 同一实例，避免宿主与 UI 各持一份）
    let iconCache = IconCache.shared

    /// HUD 控制器
    let hudController = HUDController()

    /// 分离窗口控制器
    let pluginPanelController = PluginPanelController()

    /// 开机自启管理
    let launchAtLogin = LaunchAtLogin()

    /// 菜单栏状态项
    let statusItemController = StatusItemController()
    let updateController = UpdateController()

    /// 用户设置存储（插件开关等）
    let settingsStore = SettingsStore()

    /// 键盘布局切换（面板打开时强制到指定布局）
    let keyboardLayoutService = KeyboardLayoutService()

    /// 面板打开前的键盘布局，用于关闭时还原
    var layoutBeforePanel: String?

    /// 粘贴回上一应用的待执行任务
    ///
    /// 用户在 settle 窗口内再次唤出面板时必须取消，否则 ⌘V 会打进刚打开的面板。
    var pendingPasteTask: Task<Void, Never>?

    /// 数据库
    ///
    /// 全应用一个库，插件的批量数据与插件键值都在里面。`lazy` 是因为打开可能失败，
    /// 而失败的兜底需要写日志（`log` 是实例属性）。
    private(set) lazy var database: SQLiteDatabase = openDatabase()

    /// 设置窗口的数据源桥接
    private(set) lazy var settingsBridge = SettingsBridge(core: self)

    /// 设置窗口控制器
    ///
    /// `lazy` 是因为它需要 `settingsBridge` 作为数据源，而初始化器里不能引用 `self`。
    /// 窗口本身也是惰性创建的：没打开过设置就不该有窗口。
    private(set) lazy var settingsWindowController = SettingsWindowController(dataSource: settingsBridge)

    /// 第一次启动的引导
    let onboardingController = OnboardingWindowController()

    /// 文件搜索来源
    ///
    /// **不是插件**：它由宿主直接持有并注入给面板协调器，因此不进 `registerPlugins()`、
    /// 不出现在插件列表、也不能被单独禁用。
    let fileSearchSource = FileSearchSource()

    /// 数据库健康状况；`start()` 末尾据此提示用户
    /// 由 `AppCore+Plugins` 的数据库打开流程写入，其余文件只读
    var databaseNotice: String?

    /// 崩溃自愈：记录上次是否异常退出，以及死在哪个插件的启动里
    ///
    /// 状态文件独立于数据库 —— 数据库本身就可能是崩溃的原因，不能把它放在同一个地方。
    let launchGuard = LaunchGuard(
        fileURL: AppPaths.applicationSupport().appendingPathComponent("launch-state.json"))

    /// 本次启动因反复崩溃而被自动停用的插件名；`start()` 末尾据此提示用户
    var quarantinedPluginNames: [String] = []

    /// 是否处于崩溃循环（连续多次异常退出）
    var isCrashLoop = false

    /// 打开数据库
    ///
    /// 走 `ResilientDatabase` 的三级降级：正常 → 隔离坏库后重建 → 内存库。
    /// 不静默：重建与内存库都会留下 `databaseNotice`，由 `start()` 弹 HUD。
    func openDatabase() -> SQLiteDatabase {
        do {
            let outcome = try ResilientDatabase.open(at: AppPaths.database())
            switch outcome {
            case .opened:
                break
            case .recovered(_, let quarantined):
                databaseNotice = "数据库已损坏，已备份为 \(quarantined.lastPathComponent) 并重新创建"
            case .inMemory(_, let reason):
                QuickLog.app.error("数据库不可用，本次运行改用内存库，数据不会保存：\(reason, privacy: .public)")
                databaseNotice = "数据库不可用，本次运行的数据不会保存"
            }
            return outcome.database
        } catch {
            // 连内存库都开不起来，说明进程已经没有可用的存储了
            fatalError("无法创建内存数据库：\(error)")
        }
    }

    /// 取某个插件的存储句柄
    ///
    /// 句柄绑定插件 id，所以插件写不到别人的命名空间里去。
    func storage(for pluginID: String) -> PluginStorage {
        PluginStorage(pluginID: pluginID, database: database)
    }

    // MARK: - Feature Plugins

    /// 所有已注册插件
    /// 已注册的插件。**只有 `AppCore+Plugins.swift` 的 `registerPlugins()` 允许写入**（跨文件无法再用 `private(set)` 表达，靠约定与 `check-plugin-references.py` 守住）
    var plugins: [any QuickPlugin] = []

    /// 插件 id → 实例
    ///
    /// 与 `plugins` 同时维护，由 `rebuildCommandCatalog()` 重建。视图工厂、导航、
    /// 命令归属都问它，避免每次都遍历数组。
    var pluginsByID: [String: any QuickPlugin] = [:]

    /// 命令 id → 负责执行的插件 id
    ///
    /// 静态命令与动态命令的前缀回退是两条不同的路：这里只登记静态 `commands`，
    /// 动态命令（`launcher.app.*`）仍走前缀回退。
    var commandOwners: [String: String] = [:]

    /// 事件订阅凭证（防止被释放）
    var subscriptions: [EventSubscription] = []

    /// 单实例唤醒通知观察者（必须强引用）
    var wakeUpObserver: NSObjectProtocol?

    /// 调试唤醒通知观察者（必须强引用，否则立即失效）
    var debugWakeObserver: NSObjectProtocol?

    /// 外观设置变化的观察者（必须强引用）
    var appearanceSettingObserver: NSObjectProtocol?

    /// 超级面板鼠标偏好变化的观察者（必须强引用）
    var superPanelDefaultsObserver: NSObjectProtocol?

    /// 最近使用（与协调器共用同一份，设置页清空时也动它）
    var usageHistory: UsageHistory?

    /// 实际生效外观的观察者（必须强引用）
    var effectiveAppearanceObserver: NSKeyValueObservation?

    /// 设置数据源缓存（避免设置面板切换时重复全量计算与反序列化）
    var cachedIndexedApps: [SettingsAppItem]?
    var cachedCustomCommands: [SettingsCustomCommandItem]?

    init() {}

    // MARK: - 启动

    /// 启动应用核心
    ///
    /// 由 AppDelegate.applicationDidFinishLaunching 调用一次。
    /// 按顺序完成：创建插件 → 注册事件 → 启动服务 → 激活插件。
    func start() {
        log.notice("AppCore 启动，bundle id=\(Bundle.main.bundleIdentifier ?? "-", privacy: .public)")

        // -1. 崩溃自愈：必须在注册插件之前 —— 插件的启用状态在注册时读取。
        //    启动器是核心，豁免隔离：停用它等于把 Quick 变成空壳。
        let launchOutcome = launchGuard.begin(exempt: [LauncherPlugin.id])
        isCrashLoop = launchOutcome.isCrashLoop
        for pluginID in launchOutcome.quarantine {
            settingsStore.setPluginEnabled(pluginID, enabled: false)
            log.error("插件 \(pluginID, privacy: .public) 连续两次死在启动里，已自动停用")
        }
        quarantinedPluginNames = launchOutcome.quarantine.map { pluginID in
            pluginRegistrations.first { $0.type.id == pluginID }?.type.name ?? pluginID
        }

        // 1. 打开数据库并应用宿主自己的 schema
        //    必须在注册插件之前：需要真表的插件在构造时就要拿到存储句柄
        migrateHostStorage()
        log.notice("数据库已就绪：\(self.database.path ?? "内存库", privacy: .public)")

        // 2. 建表 → 创建并注册所有 Feature Plugin
        registerPlugins()
        log.notice("插件注册完成，共 \(self.plugins.count, privacy: .public) 个")

        // 3. 注入宿主的全部外部依赖，并把插件交给协调器
        //
        // 依赖一次性收进 `PaletteDependencies`：以前这里是六七行 `paletteCoordinator.xxx = ...`，
        // 漏掉一行不报错，只表现为某个功能静默失效。
        paletteCoordinator.setPlugins(plugins)
        let history = UsageHistory(database: database)
        usageHistory = history
        paletteCoordinator.attach(
            PaletteDependencies(
                isSearchSourceEnabled: { [weak self] pluginID in
                    self?.settingsStore.isSearchSourceEnabled(pluginID) ?? true
                },
                invokeCommand: { [weak self] commandID in
                    self?.invoke(commandID: commandID)
                },
                onDetach: { [weak self] pluginID in
                    self?.detachPlugin(pluginID)
                },
                onPanelWillShow: { [weak self] in
                    self?.applyForcedKeyboardLayout()
                },
                onPanelDidHide: { [weak self] in
                    self?.restoreKeyboardLayout()
                },
                aiChat: aiChat,
                usageHistory: history,
                hostSearchSource: fileSearchSource
            ))
        log.notice("面板协调器依赖已注入")

        // 3.5 预热面板：首次 ensurePanel 需 ~13 ms（NSPanel + SwiftUI 视图树），
        // 提前到启动阶段吸收，避免首次按快捷键时被用户感知为延迟
        paletteCoordinator.prewarm()

        // 4. 连接事件总线
        wireEventBus()
        log.notice("事件总线接线完成，订阅 \(self.subscriptions.count, privacy: .public) 条")

        // 5. 启动基础设施服务
        hotKeyService.onCommand = { [weak self] commandID in
            self?.invoke(commandID: commandID)
        }
        hotKeyService.start()
        wireSuperPanel()

        // 快捷键录制协调器：录制时暂停/恢复全局快捷键
        ShortcutRecorderCoordinator.shared.onPause = { [weak self] in
            self?.hotKeyService.isPaused = true
        }
        ShortcutRecorderCoordinator.shared.onResume = { [weak self] in
            self?.hotKeyService.isPaused = false
        }

        statusItemController.install()
        statusItemController.applyVisibility()
        updateController.checkInBackground()
        onboardingController.isLaunchAtLoginEnabled = { [weak self] in
            self?.settingsBridge.isLaunchAtLoginEnabled ?? false
        }
        onboardingController.setLaunchAtLogin = { [weak self] enabled in
            self?.settingsBridge.setLaunchAtLogin(enabled)
        }
        onboardingController.presentIfNeeded()
        observeDebugWakeSignals()
        applyAppearance()
        observeAppearance()

        // 7. 读取持久化的搜索范围并在后台刷新应用索引
        let initialScopes = settingsStore.searchScopes(defaultScopes: SearchScopes.defaults)
        Task {
            await appIndex.refresh(scopes: initialScopes)
            self.cachedIndexedApps = nil
        }

        // 8. 激活所有已启用的插件
        for plugin in plugins where plugin.isEnabled {
            launchGuard.guardStart(type(of: plugin).id) { plugin.activate() }
        }
        rebuildCommandCatalog()

        // 9–13. 开发启动参数（验收用）：统一在这里处理，AppDelegate 不再重复解析
        applyLaunchArguments(ProcessInfo.processInfo.arguments)

        // 存储出过问题就明说：用户看到的症状是「历史记不住」，根因只在日志里
        // 同一时刻只能显示一条 HUD（后一条会顶掉前一条），所以把要说的话合成一条
        var notices: [String] = []
        if let notice = databaseNotice { notices.append(notice) }
        if !quarantinedPluginNames.isEmpty {
            let names = quarantinedPluginNames.joined(separator: "、")
            notices.append("「\(names)」连续启动崩溃，已自动停用，可在 设置 → 插件 中重新启用")
        } else if isCrashLoop {
            notices.append("Quick 最近多次异常退出，原因请查看日志")
        }
        if !notices.isEmpty {
            hudController.show(message: notices.joined(separator: "；"), tone: .warning)
        }

        log.notice("AppCore 启动完成")
    }

    /// 解析开发启动参数并执行对应动作
    ///
    /// 优先级：`-showPlugin` > `-showSettingsTab` > `-showSettings` > `-showPalette` /
    /// `-showSuperPanel` / `-showAIChat` / `-showTranslator`（后三者可并存在不同路径上，但设置类互斥）。
    func applyLaunchArguments(_ arguments: [String]) {
        if let index = arguments.firstIndex(of: "-showPlugin"),
            index + 1 < arguments.count
        {
            let pluginID = arguments[index + 1]
            log.notice("命中启动参数 -showPlugin \(pluginID, privacy: .public)")
            paletteCoordinator.show(pluginID: pluginID)
            return
        }

        if let index = arguments.firstIndex(of: "-showSettingsTab"),
            index + 1 < arguments.count,
            let tab = SettingsTab(rawValue: arguments[index + 1])
        {
            log.notice("命中启动参数 -showSettingsTab \(tab.rawValue, privacy: .public)")
            paletteCoordinator.hide()
            settingsWindowController.show(tab: tab)
            return
        }

        if arguments.contains("-showSettings") {
            log.notice("命中启动参数 -showSettings，立即显示设置窗口")
            paletteCoordinator.hide()
            settingsWindowController.show()
            return
        }

        if arguments.contains("-showPalette") {
            log.notice("命中启动参数 -showPalette，立即显示面板")
            paletteCoordinator.show()
        }

        if arguments.contains("-showAIChat") {
            log.notice("命中启动参数 -showAIChat，立即进入 AI 对话")
            paletteCoordinator.showAIChat()
        }

        if arguments.contains("-showSuperPanel") {
            log.notice("命中启动参数 -showSuperPanel，立即显示超级面板")
            superPanelController.show()
        }

        // 走真实的导航事件 + 上下文通道（与超级面板跳转同一条路），验收的就是
        // `.prefillFromPluginContext` 本身，而不是某条旁路。
        if arguments.contains("-showTranslator") {
            log.notice("命中启动参数 -showTranslator，打开翻译面板并携带文本")
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                EventBus.shared.post(
                    NavigateEvent(
                        pluginID: TranslatorPlugin.id,
                        context: ["query": "Hello, how are you today?"]))
            }
        }
    }

    /// 监听开发调试唤醒信号（分布式通知）与单实例重复启动协同
    func observeDebugWakeSignals() {
        // 1. 监听单实例重复启动唤醒
        wakeUpObserver = DistributedNotificationCenter.default().addObserver(
            forName: SingleInstanceGuard.wakeUpNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let args = notification.userInfo?["arguments"] as? [String]
            Task { @MainActor in
                if let args {
                    self?.applyLaunchArguments(args)
                }
                self?.paletteCoordinator.show()
            }
        }

        // 2. 兼容原有的 com.ixxxxoooo.quick.togglePalette
        debugWakeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.ixxxxoooo.quick.togglePalette"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.paletteCoordinator.toggle()
            }
        }
    }

    // MARK: - 退出清理

    /// 准备退出（释放系统资源）
    func prepareForTermination() {
        log.notice("开始退出清理")
        aiChat.flushPendingSaves()
        hotKeyService.stop()
        mouseTriggerMonitor.stop()
        statusItemController.remove()
        pluginPanelController.closeAll()
        if let obs = wakeUpObserver {
            DistributedNotificationCenter.default().removeObserver(obs)
            wakeUpObserver = nil
        }
        if let obs = debugWakeObserver {
            DistributedNotificationCenter.default().removeObserver(obs)
            debugWakeObserver = nil
        }
        for plugin in plugins {
            plugin.deactivate()
        }
        EventBus.shared.removeAll()
        // 走到这里才算正常退出；SIGTERM 也会经过 `prepareForTermination`，所以重启脚本不会被当成崩溃
        launchGuard.markCleanExit()
        log.notice("退出清理完成")
    }

}

extension Duration {
    /// 转换为毫秒数（双精度），给 invoke 链路计时用
    var invokeMS: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) * 1000 + Double(attoseconds) / 1_000_000_000_000_000
    }
}
