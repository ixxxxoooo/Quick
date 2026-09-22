// AppCore.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import PluginAI
import PluginBase64Codec

import PluginCalculator
import PluginCalendar
import PluginClipboard
import PluginColorCompare

import PluginFileSearch
import PluginFileSearch

import PluginHashCalculator

import PluginJSONFormatter

import PluginLauncher
import PluginLauncher

import PluginMarkdownPreview

import PluginNetworkTools
import PluginNetworkTools

import PluginNotes
import PluginNotes

import PluginOCR
import PluginOCR

import PluginSQLFormatter

import PluginScreenshot
import PluginScreenshot

import PluginSnippets
import PluginSnippets

import PluginSystemControl
import PluginSystemControl

import PluginSystemMonitor
import PluginSystemMonitor

import PluginTextDiff

import PluginTimestampConverter

import PluginTranslator
import PluginTranslator

import PluginURLCodec

import PluginUUIDGenerator

import PluginSuperPanel

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

    private let log = QuickLog.app

    // MARK: - 基础设施（不是 Plugin）

    /// 全局快捷键服务
    let hotKeyService = HotKeyService()

    /// 面板协调器
    let paletteCoordinator = PaletteCoordinator()

    /// 权限服务
    let permissionService = PermissionService()

    /// 粘贴板服务
    let pasteboardService = PasteboardService()

    /// 合成系统粘贴（⌘V，需要辅助功能权限）
    let pasteService = PasteService()

    /// 应用索引
    let appIndex = AppIndex()

    /// HUD 控制器
    let hudController = HUDController()

    /// 分离窗口控制器
    let pluginPanelController = PluginPanelController()

    /// 开机自启管理
    let launchAtLogin = LaunchAtLogin()

    /// 菜单栏状态项
    let statusItemController = StatusItemController()

    /// 用户设置存储（插件开关等）
    let settingsStore = SettingsStore()

    /// 键盘布局切换（面板打开时强制到指定布局）
    let keyboardLayoutService = KeyboardLayoutService()

    /// 面板打开前的键盘布局，用于关闭时还原
    private var layoutBeforePanel: String?

    /// 数据库
    ///
    /// 全应用一个库，插件的批量数据与插件键值都在里面。`lazy` 是因为打开可能失败，
    /// 而失败的兜底需要写日志（`log` 是实例属性）。
    private(set) lazy var database: SQLiteDatabase = Self.openDatabase()

    /// 设置窗口控制器
    ///
    /// `lazy` 是因为它需要 `self` 作为数据源，而初始化器里不能引用 `self`。
    /// 窗口本身也是惰性创建的：没打开过设置就不该有窗口。
    private(set) lazy var settingsWindowController = SettingsWindowController(dataSource: self)

    /// 第一次启动的引导
    private let onboardingController = OnboardingWindowController()

    /// 打开数据库
    ///
    /// 打不开文件时退到内存库继续运行：剪贴板、笔记这些功能不该因为存储问题整个用不了，
    /// 代价是本次运行不落盘 —— 所以这条日志是 error 级，不静默。
    private static func openDatabase() -> SQLiteDatabase {
        do {
            return try SQLiteDatabase(path: AppPaths.database())
        } catch {
            QuickLog.app.error("数据库打不开，本次运行改用内存库，数据不会保存：\(error)")
            guard let fallback = try? SQLiteDatabase() else {
                // 连内存库都开不起来，说明进程已经没有可用的存储了
                fatalError("无法创建内存数据库：\(error)")
            }
            return fallback
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
    private(set) var plugins: [any QuickPlugin] = []

    /// 事件订阅凭证（防止被释放）
    private var subscriptions: [EventSubscription] = []

    /// 调试唤醒通知观察者（必须强引用，否则立即失效）
    private var debugWakeObserver: NSObjectProtocol?

    /// 外观设置变化的观察者（必须强引用）
    private var appearanceSettingObserver: NSObjectProtocol?

    /// 实际生效外观的观察者（必须强引用）
    private var effectiveAppearanceObserver: NSKeyValueObservation?

    /// 设置数据源缓存（避免设置面板切换时重复全量计算与反序列化）
    private var cachedIndexedApps: [SettingsAppItem]?
    private var cachedCustomCommands: [SettingsCustomCommandItem]?

    private init() {}

    // MARK: - 启动

    /// 启动应用核心
    ///
    /// 由 AppDelegate.applicationDidFinishLaunching 调用一次。
    /// 按顺序完成：创建插件 → 注册事件 → 启动服务 → 激活插件。
    func start() {
        log.notice("AppCore 启动，bundle id=\(Bundle.main.bundleIdentifier ?? "-", privacy: .public)")

        // 1. 打开数据库并应用宿主自己的 schema
        //    必须在注册插件之前：需要真表的插件在构造时就要拿到存储句柄
        migrateHostStorage()
        log.notice("数据库已就绪：\(self.database.path ?? "内存库", privacy: .public)")

        // 2. 建表 → 创建并注册所有 Feature Plugin
        registerPlugins()
        log.notice("插件注册完成，共 \(self.plugins.count, privacy: .public) 个")

        // 3. 将插件注入到面板协调器，并接上「最近使用」与键盘布局
        paletteCoordinator.setPlugins(plugins)
        paletteCoordinator.usageHistory = UsageHistory(database: database)
        paletteCoordinator.onPanelWillShow = { [weak self] in
            self?.applyForcedKeyboardLayout()
        }
        paletteCoordinator.onPanelDidHide = { [weak self] in
            self?.restoreKeyboardLayout()
        }

        // 4. 连接事件总线
        wireEventBus()
        log.notice("事件总线接线完成，订阅 \(self.subscriptions.count, privacy: .public) 条")

        // 5. 设置协调器的分离回调
        paletteCoordinator.onDetach = { [weak self] pluginID in
            self?.detachPlugin(pluginID)
        }

        // 6. 启动基础设施服务
        hotKeyService.onCommand = { [weak self] commandID in
            self?.invoke(commandID: commandID)
        }
        hotKeyService.start()

        paletteCoordinator.invokeCommand = { [weak self] commandID in
            self?.invoke(commandID: commandID)
        }
        paletteCoordinator.isSearchSourceEnabled = { [weak self] pluginID in
            self?.settingsStore.isSearchSourceEnabled(pluginID) ?? true
        }

        // 快捷键录制协调器：录制时暂停/恢复全局快捷键
        ShortcutRecorderCoordinator.shared.onPause = { [weak self] in
            self?.hotKeyService.isPaused = true
        }
        ShortcutRecorderCoordinator.shared.onResume = { [weak self] in
            self?.hotKeyService.isPaused = false
        }

        statusItemController.install()
        statusItemController.applyVisibility()
        onboardingController.isLaunchAtLoginEnabled = { [weak self] in
            self?.isLaunchAtLoginEnabled ?? false
        }
        onboardingController.setLaunchAtLogin = { [weak self] enabled in
            self?.setLaunchAtLogin(enabled)
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
            plugin.activate()
        }
        rebuildCommandCatalog()

        // 9. 开发启动参数：立即显示面板（验收用）
        if ProcessInfo.processInfo.arguments.contains("-showPalette") {
            log.notice("命中启动参数 -showPalette，立即显示面板")
            paletteCoordinator.show()
        }

        // 10. 开发启动参数：立即显示设置窗口（验收用）
        if ProcessInfo.processInfo.arguments.contains("-showSettings") {
            log.notice("命中启动参数 -showSettings，立即显示设置窗口")
            paletteCoordinator.hide()
            settingsWindowController.show()
        }

        log.notice("AppCore 启动完成")
    }

    /// 监听开发调试唤醒信号（分布式通知）
    ///
    /// 用法：`notifyutil -p com.ixxxxoooo.quick.togglePalette`
    private func observeDebugWakeSignals() {
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
        hotKeyService.stop()
        statusItemController.remove()
        pluginPanelController.closeAll()
        for plugin in plugins {
            plugin.deactivate()
        }
        EventBus.shared.removeAll()
        log.notice("退出清理完成")
    }

    // MARK: - 插件分离

    /// 将指定插件分离为独立窗口
    ///
    /// 查找插件实例 → 获取视图 → 创建独立窗口 → 主面板返回搜索模式。
    private func detachPlugin(_ pluginID: String) {
        guard let plugin = plugins.first(where: { type(of: $0).id == pluginID }),
            plugin.isEnabled
        else {
            log.warning("分离失败：找不到插件 \(pluginID, privacy: .public) 或插件已禁用")
            return
        }

        let viewProvider = { plugin.makeView() }
        let name = type(of: plugin).name
        let icon = type(of: plugin).icon
        let supportsSearch = type(of: plugin).supportsPanelSearch

        pluginPanelController.detach(
            pluginID: pluginID,
            pluginName: name,
            icon: icon,
            supportsSearch: supportsSearch,
            viewProvider: viewProvider,
            sourceWindow: nil
        )

        paletteCoordinator.popToRoot()
        paletteCoordinator.hide(restoreFocus: false)
    }

    // MARK: - 键盘布局

    /// 面板打开时切到用户指定的键盘布局
    ///
    /// 中文输入法用户按 ⌥Space 时往往还停在拼音状态，输入的其实是拼音串 ——
    /// 强制切到 ABC 才能直接打命令。关闭面板时还原（见 restoreKeyboardLayout）。
    private func applyForcedKeyboardLayout() {
        let configured = UserDefaults.standard.string(forKey: SettingsKey.paletteForceKeyboardLayout) ?? ""
        guard !configured.isEmpty else { return }

        let current = keyboardLayoutService.currentLayoutID()
        // 已经在目标布局上就不动：既省一次切换，也保证「还原」不会记错原值
        guard current != configured else { return }

        layoutBeforePanel = current
        if keyboardLayoutService.select(layoutID: configured) {
            log.notice("面板打开，键盘布局已切到 \(configured, privacy: .public)")
        } else {
            // 用户可能已经删掉了那个布局：留个 warning，不要静默
            log.warning("指定的键盘布局不存在，未切换：\(configured, privacy: .public)")
            layoutBeforePanel = nil
        }
    }

    /// 面板关闭时还原原来的键盘布局
    private func restoreKeyboardLayout() {
        guard let previous = layoutBeforePanel else { return }
        layoutBeforePanel = nil
        if keyboardLayoutService.select(layoutID: previous) {
            log.debug("面板关闭，键盘布局已还原：\(previous, privacy: .public)")
        }
    }

    // MARK: - 外观

    /// 应用外观设置
    ///
    /// **全仓只有这一处给 `NSApp.appearance` 赋值。** 它是应用级的，所以面板、设置窗口、
    /// 分离窗口一起跟着变 —— 逐个窗口设置迟早会漏掉一个（HUD、分离窗口、设置窗口各一份），
    /// 而 `.system` 映射成 `nil` 之后，系统切换外观由 AppKit 自己跟进，不需要我们监听什么。
    private func applyAppearance() {
        let appearance = AppAppearance.stored()
        NSApp.appearance = appearance.nsAppearance
        log.debug("外观已应用：\(appearance.rawValue, privacy: .public)")
    }

    /// 外观设置改了要立刻生效：不该为了换个主题重启应用
    ///
    /// 用 `UserDefaults.didChangeNotification` 而不是 `@AppStorage`：设置页写在
    /// `QuickUI` 里，这里只该知道「偏好变了」，不该认识那个视图。
    private func observeAppearance() {
        if appearanceSettingObserver == nil {
            appearanceSettingObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: UserDefaults.standard,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.applyAppearance()
                    self?.statusItemController.applyVisibility()
                    self?.paletteCoordinator.applyPaletteMetrics()
                }
            }
        }

        guard effectiveAppearanceObserver == nil else { return }
        // 图标缓存是按外观出的位图，翻了面要让它重来。
        // 挂在 `NSApp.effectiveAppearance` 上而不是 `applyAppearance()` 里：
        // 「跟随系统」时我们从不赋值，那条路只有这里能收到。
        effectiveAppearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.initial]) { app, _ in
            MainActor.assumeIsolated {
                IconCache.setDarkSurface(app.effectiveAppearance.isDark)
            }
        }
    }

    // MARK: - 存储迁移

    /// 应用宿主自己的 schema
    private func migrateHostStorage() {
        do {
            try database.migrate([.corePluginData, .coreUsageHistory])
        } catch {
            // 迁移失败不能静默：继续跑下去会以「表不存在」的形式在插件里炸开，
            // 那时已经看不出根因了
            log.error("宿主存储迁移失败：\(error)")
        }
    }

    /// 应用各插件声明的 schema
    ///
    /// 表结构归插件所有，宿主只负责按注册顺序把它们跑一遍。顺序固定（注册顺序），
    /// 所以同一个库在两台机器上的建表顺序一致。
    /// - Parameter types: 插件类型列表；`storageMigrations` 是静态的，所以不需要实例
    private func migratePluginStorage(_ types: [any QuickPlugin.Type]) {
        let migrations = types.flatMap { $0.storageMigrations }
        guard !migrations.isEmpty else { return }
        do {
            try database.migrate(migrations)
            log.notice("插件 schema 已就绪，共 \(migrations.count, privacy: .public) 个迁移")
        } catch {
            log.error("插件存储迁移失败：\(error)")
        }
    }

    // MARK: - 插件注册

    /// 注册所有 Feature Plugin
    ///
    /// 这是唯一创建插件实例的地方。
    /// 新增插件只需在此处添加一行注册。
    /// 插件的注册清单
    ///
    /// 每一项是「类型 + 工厂」而不是直接给实例：**schema 必须在实例化之前建好**。
    /// 需要真表的插件在 `init` 里就会查自己的表（store 同步加载），如果先构造再迁移，
    /// 首次启动时表还不存在，插件会以「读取失败，按空数据继续」启动 —— 数据看起来
    /// 像是丢了，而且只在第一次运行时出现。
    ///
    /// 类型与工厂成对列出，是为了让迁移能从类型上取（`storageMigrations` 是静态的），
    /// 而依赖注入留在工厂里。
    private var pluginRegistrations: [(type: any QuickPlugin.Type, make: () -> any QuickPlugin)] {
        [
            // Phase 2: 核心插件
            (
                LauncherPlugin.self,
                {
                    LauncherPlugin(
                        appIndex: self.appIndex,
                        settingsStore: self.settingsStore,
                        storage: self.storage(for: LauncherPlugin.id))
                }
            ),
            (ClipboardPlugin.self, { ClipboardPlugin(storage: self.storage(for: ClipboardPlugin.id)) }),
            (CalculatorPlugin.self, { CalculatorPlugin(storage: self.storage(for: CalculatorPlugin.id)) }),
            (SystemControlPlugin.self, { SystemControlPlugin(settingsStore: self.settingsStore) }),

            // Phase 3: 效率与工具插件
            (FileSearchPlugin.self, { FileSearchPlugin() }),
            (SnippetsPlugin.self, { SnippetsPlugin(storage: self.storage(for: SnippetsPlugin.id)) }),
            (OCRPlugin.self, { OCRPlugin() }),
            (TranslatorPlugin.self, { TranslatorPlugin() }),

            // Phase 3.5: 开发者工具插件（原先是一个 devtools 容器，现在每个工具都是独立插件）
            (JSONFormatterPlugin.self, { JSONFormatterPlugin() }),
            (SQLFormatterPlugin.self, { SQLFormatterPlugin() }),
            (Base64CodecPlugin.self, { Base64CodecPlugin() }),
            (URLCodecPlugin.self, { URLCodecPlugin() }),
            (UUIDGeneratorPlugin.self, { UUIDGeneratorPlugin() }),
            (HashCalculatorPlugin.self, { HashCalculatorPlugin() }),
            (TimestampConverterPlugin.self, { TimestampConverterPlugin() }),
            (TextDiffPlugin.self, { TextDiffPlugin() }),
            (MarkdownPreviewPlugin.self, { MarkdownPreviewPlugin() }),
            (ColorComparePlugin.self, { ColorComparePlugin() }),

            // Phase 4: 扩展插件
            (CalendarPlugin.self, { CalendarPlugin() }),
            (NotesPlugin.self, { NotesPlugin(storage: self.storage(for: NotesPlugin.id)) }),
            (AIPlugin.self, { AIPlugin() }),
            (SystemMonitorPlugin.self, { SystemMonitorPlugin() }),
            (NetworkToolsPlugin.self, { NetworkToolsPlugin() }),
            (ScreenshotPlugin.self, { ScreenshotPlugin() }),

            // Phase 5: 超级面板
            (SuperPanelPlugin.self, { SuperPanelPlugin() })
        ]
    }

    /// 建表并实例化全部插件
    ///
    /// 这是全仓唯一 `plugins.append(...)` 的地方。
    private func registerPlugins() {
        let registrations = pluginRegistrations

        // 先建 schema：插件的 store 在 init 里就会读表
        migratePluginStorage(registrations.map(\.type))

        // 再实例化
        for registration in registrations {
            let plugin = registration.make()
            plugin.isEnabled = settingsStore.isPluginEnabled(type(of: plugin).id)
            plugins.append(plugin)
        }
    }

    /// 注册一个插件，并恢复用户上次的启用状态
    ///
    /// 启用状态在这里从设置里读出来应用，而不是让插件自己去读：
    /// 插件不认识设置存储，依赖方向保持单向。
    ///
    /// - Parameter plugin: 插件实例
    private func register(_ plugin: any QuickPlugin) {
        plugin.isEnabled = settingsStore.isPluginEnabled(type(of: plugin).id)
        plugins.append(plugin)
    }

    // MARK: - 事件总线连接

    /// 连接 EventBus 订阅
    ///
    /// 所有插件间的通信都在这里统一接线。
    /// 插件发布事件 → EventBus → AppCore 路由到目标。
    private func wireEventBus() {
        let bus = EventBus.shared

        // 导航事件 → 面板协调器
        subscriptions.append(
            bus.on(NavigateEvent.self) { [weak self] event in
                self?.paletteCoordinator.navigate(to: event.pluginID, context: event.context)
            }
        )

        // 复制到剪贴板事件 → 粘贴板服务
        subscriptions.append(
            bus.on(CopyToClipboardEvent.self) { [weak self] event in
                self?.pasteboardService.copyText(event.text)
                if event.showHUD {
                    self?.hudController.show(message: "已复制", tone: .success)
                }
            }
        )

        // HUD 消息事件 → HUD 控制器
        subscriptions.append(
            bus.on(ShowHUDEvent.self) { [weak self] event in
                self?.hudController.show(message: event.message, tone: event.tone)
            }
        )

        // 隐藏面板事件
        subscriptions.append(
            bus.on(HidePaletteEvent.self) { [weak self] event in
                self?.paletteCoordinator.hide(restoreFocus: event.restoreFocus)
            }
        )

        // 粘贴回上一个应用：内容已经写好，这里只负责隐藏面板、交还焦点、再合成 ⌘V
        subscriptions.append(
            bus.on(PasteIntoPreviousAppEvent.self) { [weak self] _ in
                guard let self else { return }
                self.paletteCoordinator.hide(restoreFocus: true)
                self.schedulePasteIntoPreviousApp()
            }
        )

        // 显示面板事件
        subscriptions.append(
            bus.on(ShowPaletteEvent.self) { [weak self] event in
                self?.paletteCoordinator.show(pluginID: event.pluginID, query: event.query)
            }
        )

        // 打开设置窗口事件
        subscriptions.append(
            bus.on(ShowPaletteSettingsEvent.self) { [weak self] _ in
                Task { @MainActor in
                    self?.paletteCoordinator.hide(restoreFocus: false)
                    self?.settingsWindowController.show()
                }
            }
        )

        // 分离面板事件 → 创建独立插件窗口
        subscriptions.append(
            bus.on(DetachPanelEvent.self) { [weak self] event in
                guard let self else { return }
                self.detachPlugin(event.pluginID)
            }
        )

        // 应用索引刷新事件（清除设置应用缓存）
        subscriptions.append(
            bus.on(AppIndexRefreshedEvent.self) { [weak self] _ in
                self?.cachedIndexedApps = nil
            }
        )

        subscriptions.append(
            bus.on(CommandCatalogChangedEvent.self) { [weak self] _ in
                self?.rebuildCommandCatalog()
            }
        )
    }

    // MARK: - 粘贴回上一个应用

    /// 交还焦点后多久再合成 ⌘V
    ///
    /// `NSRunningApplication.activate()` 是异步的：立刻发 ⌘V 会打在被切走的面板或
    /// 还没回到前台的旧应用上。给系统一点时间把前一个应用带到前台。
    private static let pasteSettleDelay = Duration.milliseconds(140)

    /// 等前一个应用回到前台，再合成一次 ⌘V；没有辅助功能权限就只提示
    private func schedulePasteIntoPreviousApp() {
        let canPaste = pasteService.canSynthesize
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard canPaste else {
                // 面板已隐藏，剪贴板里已经有内容了 —— 告诉用户为什么没自动粘贴
                self.hudController.show(
                    message: "已复制，开启辅助功能权限后可自动粘贴",
                    tone: .warning
                )
                return
            }
            try? await Task.sleep(for: Self.pasteSettleDelay)
            self.pasteService.paste()
        }
    }

    // MARK: - 自定义命令存储辅助

    private func loadCustomCommands() -> [CustomCommand] {
        guard let data = settingsStore.customCommandsData,
            let list = try? JSONDecoder().decode([CustomCommand].self, from: data)
        else {
            return []
        }
        return list
    }

    private func saveCustomCommands(_ commands: [CustomCommand]) {
        let data = try? JSONEncoder().encode(commands)
        settingsStore.setCustomCommandsData(data)
        cachedCustomCommands = nil
    }

    // MARK: - 快捷键恢复

    /// 执行一条命令。热键和搜索共用这一条路径
    private func invoke(commandID: String) {
        log.notice("执行命令 \(commandID, privacy: .public)")
        if commandID != CommandID.togglePalette, !settingsStore.isCommandEnabled(commandID) {
            log.notice("命令已关闭，拒绝调用 \(commandID, privacy: .public)")
            return
        }
        if commandID == CommandID.togglePalette {
            paletteCoordinator.toggle()
            return
        }
        if let pluginID = CommandID.openedPluginID(in: commandID) {
            paletteCoordinator.show(pluginID: pluginID)
            return
        }
        guard let plugin = plugin(forCommand: commandID) else {
            log.warning("没有插件认领命令 \(commandID, privacy: .public)")
            return
        }
        plugin.perform(commandID: commandID)
    }

    /// 按 id 前缀找到负责执行的插件
    private func plugin(forCommand commandID: String) -> (any QuickPlugin)? {
        if commandID.hasPrefix("launcher.") {
            return plugins.first { type(of: $0).id == LauncherPlugin.id }
        }
        if commandID.hasPrefix("systemcontrol.") {
            return plugins.first { type(of: $0).id == SystemControlPlugin.id }
        }
        if let owner = plugins.first(where: { type(of: $0).commands.contains { $0.id == commandID } }) {
            return owner
        }
        return plugins.first { commandID.hasPrefix(type(of: $0).id + ".") }
    }

    /// 用当前插件声明和开关重建静态命令快照，并按开关注册热键
    private func rebuildCommandCatalog() {
        var indexed: [IndexedCommand] = []
        for plugin in plugins where plugin.isEnabled {
            let meta = type(of: plugin)
            guard settingsStore.isSearchSourceEnabled(meta.id) else { continue }
            for command in meta.commands {
                guard settingsStore.isCommandEnabled(command.id) else { continue }
                var keywords = command.keywords
                if let aliasKey = command.aliasKey,
                    let alias = settingsStore.alias(for: aliasKey),
                    !alias.isEmpty
                {
                    keywords.append(alias)
                }
                indexed.append(IndexedCommand(command.replacingKeywords(keywords)))
            }
        }
        paletteCoordinator.staticCommands = indexed
        hotKeyService.syncRegistrations { [settingsStore] commandID in
            commandID == CommandID.togglePalette || settingsStore.isCommandEnabled(commandID)
        }
        log.notice("命令目录已更新，静态命令 \(indexed.count, privacy: .public) 条")
    }
}

// MARK: - 设置窗口的数据源

/// `AppCore` 是设置界面的数据源
///
/// 设置界面在 `QuickUI`，而插件实例与系统能力（登录项、快捷键）只有组装层看得到，
/// 所以由这里实现协议、把两边接起来。
extension AppCore: SettingsDataSource {

    // MARK: - 通用设置

    var isLaunchAtLoginEnabled: Bool { launchAtLogin.isEnabled }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin.setEnabled(enabled)
    }

    var hotKeyDescription: String {
        hotKeyService.binding(for: CommandID.togglePalette)?.displayString
            ?? HotKeyService.defaultHotKeyDescription
    }

    var togglePaletteKeycaps: [String] {
        hotKeyService.binding(for: CommandID.togglePalette)?.keycaps ?? ["⌥", "Space"]
    }

    func shortcutKeycaps(keyCode: Int, carbonModifiers: Int) -> [String] {
        KeyShortcut(carbonKeyCode: keyCode, carbonModifiers: carbonModifiers).keycaps
    }

    func boundCommandBindings() -> [SettingsCommandBinding] {
        hotKeyService.boundCommandIDs().compactMap { commandID in
            guard commandID != CommandID.togglePalette else { return nil }
            guard hotKeyService.binding(for: commandID) != nil else { return nil }
            return describe(commandID: commandID)
        }
    }

    func resolveKeyword(_ keyword: String) -> SettingsCommandBinding? {
        var descriptors: [CommandDescriptor] = []
        for plugin in plugins where plugin.isEnabled {
            descriptors.append(contentsOf: type(of: plugin).commands)
        }
        for cmd in loadCustomCommands() where cmd.isEnabled {
            var words = [cmd.name]
            if let alias = cmd.alias, !alias.isEmpty { words.append(alias) }
            descriptors.append(
                CommandDescriptor(
                    id: CommandID.shell(cmd.id.uuidString),
                    pluginID: LauncherPlugin.id,
                    pluginName: "终端命令",
                    title: cmd.name,
                    keywords: words,
                    icon: "terminal"
                )
            )
        }
        if let hit = KeywordResolver.match(query: keyword, commands: descriptors) {
            return describe(commandID: hit.id)
        }

        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let apps = appIndex.apps.filter {
            $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }
        guard apps.count == 1, let app = apps.first else { return nil }
        return describe(commandID: CommandID.launchApp(app.bundleID))
    }

    func retargetShortcut(from commandID: String, keyword: String) -> String? {
        let current = describe(commandID: commandID)
        if keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            .compare(current.wakeKeyword, options: .caseInsensitive) == .orderedSame
        {
            return nil
        }
        guard let shortcut = hotKeyService.binding(for: commandID) else {
            return "这条绑定已经没有快捷键。"
        }
        guard let target = resolveKeyword(keyword) else {
            return "没有唯一对上的关键字。写插件声明的唤醒词，或功能标题。"
        }
        guard target.id != commandID else { return nil }
        hotKeyService.setBinding(nil, for: commandID, registerNow: false)
        let registerNow = settingsStore.isCommandEnabled(target.id)
        let outcome = hotKeyService.setBinding(shortcut, for: target.id, registerNow: registerNow)
        if case .conflict = outcome {
            let restore = commandID == CommandID.togglePalette || settingsStore.isCommandEnabled(commandID)
            hotKeyService.setBinding(shortcut, for: commandID, registerNow: restore)
            return "这个组合键已经绑给别的命令，没有改动。"
        }
        return nil
    }

    func pluginCommands(_ pluginID: String) -> [SettingsCommandBinding] {
        if pluginID == LauncherPlugin.id {
            return loadCustomCommands().map { describe(commandID: CommandID.shell($0.id.uuidString)) }
        }
        guard let plugin = plugins.first(where: { type(of: $0).id == pluginID }) else { return [] }
        return type(of: plugin).commands.map { bindingRow(for: $0) }
    }

    /// 把命令 id 解析成设置行。应用和终端命令不在静态声明里，要单独认前缀
    private func describe(commandID: String) -> SettingsCommandBinding {
        if let command = plugins.lazy.compactMap({ plugin in
            type(of: plugin).commands.first { $0.id == commandID }
        }).first {
            return bindingRow(for: command)
        }
        if commandID.hasPrefix(CommandID.launchAppPrefix) {
            let bundleID = String(commandID.dropFirst(CommandID.launchAppPrefix.count))
            let name = appIndex.apps.first { $0.bundleID == bundleID }?.name ?? bundleID
            return SettingsCommandBinding(
                id: commandID,
                title: name,
                pluginName: LauncherPlugin.name,
                icon: "app",
                isInvocationEnabled: settingsStore.isCommandEnabled(commandID),
                keycaps: hotKeyService.binding(for: commandID)?.keycaps,
                keywords: [name]
            )
        }
        if commandID.hasPrefix(CommandID.shellPrefix) {
            let raw = String(commandID.dropFirst(CommandID.shellPrefix.count))
            let command = loadCustomCommands().first { $0.id.uuidString.lowercased() == raw }
            let name = command?.name ?? raw
            var words = [name]
            if let alias = command?.alias, !alias.isEmpty { words.append(alias) }
            return SettingsCommandBinding(
                id: commandID,
                title: name,
                pluginName: "终端命令",
                icon: "terminal",
                isInvocationEnabled: settingsStore.isCommandEnabled(commandID),
                keycaps: hotKeyService.binding(for: commandID)?.keycaps,
                keywords: words
            )
        }
        return SettingsCommandBinding(
            id: commandID,
            title: commandID,
            pluginName: "命令",
            icon: "command",
            isInvocationEnabled: settingsStore.isCommandEnabled(commandID),
            keycaps: hotKeyService.binding(for: commandID)?.keycaps,
            keywords: [commandID]
        )
    }

    func setCommandShortcut(keyCode: Int, carbonModifiers: Int, for commandID: String) -> Bool {
        let shortcut = KeyShortcut(carbonKeyCode: keyCode, carbonModifiers: carbonModifiers)
        let registerNow = commandID == CommandID.togglePalette || settingsStore.isCommandEnabled(commandID)
        let outcome = hotKeyService.setBinding(shortcut, for: commandID, registerNow: registerNow)
        if case .conflict = outcome { return false }
        return true
    }

    func clearCommandShortcut(for commandID: String) {
        if commandID == CommandID.togglePalette {
            let defaultShortcut = KeyShortcut(carbonKeyCode: kVK_Space, carbonModifiers: optionKey)
            hotKeyService.setBinding(defaultShortcut, for: commandID, registerNow: true)
            return
        }
        hotKeyService.setBinding(nil, for: commandID, registerNow: false)
    }

    func isCommandEnabled(_ commandID: String) -> Bool {
        if commandID == CommandID.togglePalette { return true }
        return settingsStore.isCommandEnabled(commandID)
    }

    func setCommandEnabled(_ commandID: String, enabled: Bool) {
        guard commandID != CommandID.togglePalette else { return }
        settingsStore.setCommandEnabled(commandID, enabled: enabled)
        rebuildCommandCatalog()
    }

    var searchSources: [SettingsSearchSource] {
        pluginEntries.map { plugin in
            SettingsSearchSource(
                id: plugin.id,
                title: plugin.name,
                subtitle: "关闭后，主面板不再搜索这个插件的命令和结果。",
                icon: plugin.icon,
                isEnabled: settingsStore.isSearchSourceEnabled(plugin.id)
            )
        }
    }

    func setSearchSourceEnabled(_ pluginID: String, enabled: Bool) {
        settingsStore.setSearchSourceEnabled(pluginID, enabled: enabled)
        rebuildCommandCatalog()
    }

    private func bindingRow(for command: CommandDescriptor) -> SettingsCommandBinding {
        SettingsCommandBinding(
            id: command.id,
            title: command.title,
            pluginName: command.pluginName,
            icon: command.icon,
            isInvocationEnabled: settingsStore.isCommandEnabled(command.id),
            keycaps: hotKeyService.binding(for: command.id)?.keycaps,
            keywords: command.keywords.isEmpty ? [command.title] : command.keywords
        )
    }

    // MARK: - 启动器：应用与搜索范围

    var searchScopes: [String] {
        settingsStore.searchScopes(defaultScopes: SearchScopes.defaults)
    }

    func setSearchScopes(_ scopes: [String]) {
        settingsStore.setSearchScopes(scopes)
        Task {
            await appIndex.refresh(scopes: scopes)
            self.cachedIndexedApps = nil
        }
    }

    func restoreDefaultSearchScopes() {
        setSearchScopes(SearchScopes.defaults)
    }

    var indexedApplications: [SettingsAppItem] {
        if let cached = cachedIndexedApps {
            return cached
        }
        let items = appIndex.apps.map { entry in
            let alias = settingsStore.alias(for: "app." + entry.bundleID)
            return SettingsAppItem(
                id: entry.id,
                name: entry.name,
                bundleID: entry.bundleID,
                path: entry.path,
                isSystemApp: entry.isSystemApp,
                alias: alias
            )
        }
        if !items.isEmpty {
            cachedIndexedApps = items
        }
        return items
    }

    func appIcon(for path: String) -> NSImage? {
        IconCache.shared.icon(forBundlePath: path)
    }

    func setAppAlias(_ alias: String?, for bundleID: String) {
        settingsStore.setAlias(alias, for: "app." + bundleID)
        cachedIndexedApps = nil
    }

    // MARK: - 启动器：系统操作

    var systemActions: [SettingsSystemActionItem] {
        SystemAction.allCases.map { action in
            let alias = settingsStore.alias(for: "system." + action.rawValue)
            let commandID = CommandID.systemAction(action.rawValue)
            return SettingsSystemActionItem(
                id: action.rawValue,
                title: action.title,
                description: action.description,
                icon: action.icon,
                alias: alias,
                isEnabled: settingsStore.isCommandEnabled(commandID)
            )
        }
    }

    func setSystemActionAlias(_ alias: String?, for id: String) {
        settingsStore.setAlias(alias, for: "system." + id)
        rebuildCommandCatalog()
    }

    // MARK: - 启动器：Shell 与自定义命令

    var isRunShellFallbackEnabled: Bool {
        settingsStore.isRunShellFallbackEnabled
    }

    func setRunShellFallbackEnabled(_ enabled: Bool) {
        settingsStore.setRunShellFallbackEnabled(enabled)
    }

    var customCommands: [SettingsCustomCommandItem] {
        if let cached = cachedCustomCommands {
            return cached
        }
        let list = loadCustomCommands()
        let items = list.map { cmd in
            return SettingsCustomCommandItem(
                id: cmd.id,
                name: cmd.name,
                command: cmd.command,
                isEnabled: cmd.isEnabled,
                alias: cmd.alias,
                workingDirectory: cmd.workingDirectory,
                loadsShellEnvironment: cmd.loadsShellEnvironment
            )
        }
        cachedCustomCommands = items
        return items
    }

    func addCustomCommand(
        name: String, command: String, workingDirectory: String?, loadsShellEnvironment: Bool
    ) {
        var list = loadCustomCommands()
        let item = CustomCommand(
            name: name,
            command: command,
            isEnabled: true,
            loadsShellEnvironment: loadsShellEnvironment,
            workingDirectory: workingDirectory
        )
        list.append(item)
        saveCustomCommands(list)
    }

    func updateCustomCommand(
        id: UUID,
        name: String,
        command: String,
        isEnabled: Bool,
        alias: String?,
        workingDirectory: String?,
        loadsShellEnvironment: Bool
    ) {
        var list = loadCustomCommands()
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        list[index].name = name
        list[index].command = command
        list[index].isEnabled = isEnabled
        list[index].alias = alias
        list[index].workingDirectory = workingDirectory
        list[index].loadsShellEnvironment = loadsShellEnvironment
        saveCustomCommands(list)
    }

    func deleteCustomCommand(id: UUID) {
        var list = loadCustomCommands()
        list.removeAll { $0.id == id }
        saveCustomCommands(list)
        hotKeyService.setBinding(nil, for: CommandID.shell(id.uuidString), registerNow: false)
    }

    // MARK: - 功能插件设置

    /// 系统里可选的键盘布局
    var keyboardLayouts: [SettingsKeyboardLayout] {
        keyboardLayoutService.availableLayouts().map {
            SettingsKeyboardLayout(id: $0.id, name: $0.name)
        }
    }

    var forcedKeyboardLayoutID: String? {
        UserDefaults.standard.string(forKey: SettingsKey.paletteForceKeyboardLayout)
    }

    func setForcedKeyboardLayout(_ layoutID: String?) {
        if let layoutID, !layoutID.isEmpty {
            UserDefaults.standard.set(layoutID, forKey: SettingsKey.paletteForceKeyboardLayout)
        } else {
            UserDefaults.standard.removeObject(forKey: SettingsKey.paletteForceKeyboardLayout)
        }
    }

    /// 全部插件，按显示名排序
    ///
    /// 排序而不是按注册顺序：注册顺序是代码结构，用户不该看到它。
    var pluginEntries: [SettingsPlugin] {
        plugins
            .map {
                SettingsPlugin(
                    id: type(of: $0).id,
                    name: type(of: $0).name,
                    icon: type(of: $0).icon,
                    description: type(of: $0).description,
                    triggerWords: type(of: $0).triggerWords
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func isPluginEnabled(_ id: String) -> Bool {
        settingsStore.isPluginEnabled(id)
    }

    /// 切换插件启用状态
    ///
    /// 三件事必须一起做：持久化、改插件实例、启停插件。
    /// 只改设置不启停，用户会看到开关变了但功能还在跑（或反过来）。
    func setPluginEnabled(_ id: String, enabled: Bool) {
        settingsStore.setPluginEnabled(id, enabled: enabled)

        guard let plugin = plugins.first(where: { type(of: $0).id == id }) else {
            log.warning("找不到插件 \(id, privacy: .public)，设置已保存但未同步实例")
            return
        }
        guard plugin.isEnabled != enabled else { return }

        plugin.isEnabled = enabled
        if enabled {
            plugin.activate()
        } else {
            plugin.deactivate()
        }
        log.notice("插件 \(id, privacy: .public) 已\(enabled ? "启用" : "停用", privacy: .public)并同步实例")
        rebuildCommandCatalog()
    }

    func makeFeatureSettingsView(for tab: SettingsTab) -> AnyView? {
        guard let pluginID = tab.pluginID,
            let plugin = plugins.first(where: { type(of: $0).id == pluginID })
        else {
            return nil
        }
        return plugin.makeSettingsView()
    }

    // MARK: - 权限

    /// 权限状态
    ///
    /// `canRequest` 的判定依据是「系统还会不会再弹框」：
    /// 未决定的可以申请，已经拒绝过的只能去系统设置里手动打开 ——
    /// 这时给一个「申请」按钮是骗人的，点了什么都不会发生。
    func permissionState(_ permission: SettingsPermission) -> SettingsPermissionState {
        switch permission {
        case .accessibility:
            let granted = permissionService.isAccessibilityGranted()
            return SettingsPermissionState(isGranted: granted, canRequest: !granted)

        case .screenCapture:
            let granted = permissionService.isScreenCaptureGranted()
            return SettingsPermissionState(isGranted: granted, canRequest: !granted)

        case .location:
            switch permissionService.locationStatus() {
            case .granted:
                return SettingsPermissionState(isGranted: true, canRequest: false)
            case .notDetermined:
                return SettingsPermissionState(isGranted: false, canRequest: true)
            case .denied:
                return SettingsPermissionState(isGranted: false, canRequest: false)
            }
        }
    }

    func requestPermission(_ permission: SettingsPermission) {
        log.notice("用户从设置页申请权限 \(permission.rawValue, privacy: .public)")
        switch permission {
        case .accessibility:
            permissionService.requestAccessibility()
        case .screenCapture:
            permissionService.requestScreenCapture()
        case .location:
            // 定位的申请入口只有天气插件那一处（用户主动查看天气时），
            // 设置页只负责把状态显示出来、把人带到系统设置。
            permissionService.openLocationSettings()
        }
    }

    func openPermissionSettings(_ permission: SettingsPermission) {
        switch permission {
        case .accessibility:
            permissionService.openAccessibilitySettings()
        case .screenCapture:
            permissionService.openScreenCaptureSettings()
        case .location:
            permissionService.openLocationSettings()
        }
    }

    // MARK: - 关于

    var versionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    var bundleIdentifier: String { Bundle.main.bundleIdentifier ?? "—" }

    var panelGeometryDescription: String {
        "\(Int(DesignTokens.Size.panelWidth)) × \(Int(DesignTokens.Size.panelHeight)) · 圆角 \(Int(DesignTokens.Radius.panel))"
    }
}
