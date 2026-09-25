// AppCore.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import PluginAI
import PluginBase64Codec
import PluginCalculator
import PluginCalendar
import PluginClipboard
import PluginColorCompare
import PluginHashCalculator
import PluginJSONFormatter
import PluginKillProcess
import PluginLauncher
import PluginMarkdownPreview
import PluginNetworkTools
import PluginNotes
import PluginOCR
import PluginSQLFormatter
import PluginScreenshot
import PluginSnippets
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

    private let log = QuickLog.app

    // MARK: - 基础设施（不是 Plugin）

    /// 全局快捷键服务
    let hotKeyService = HotKeyService()

    /// 面板协调器
    let paletteCoordinator = PaletteCoordinator()

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

    /// 用户设置存储（插件开关等）
    let settingsStore = SettingsStore()

    /// 键盘布局切换（面板打开时强制到指定布局）
    let keyboardLayoutService = KeyboardLayoutService()

    /// 面板打开前的键盘布局，用于关闭时还原
    private var layoutBeforePanel: String?

    /// 粘贴回上一应用的待执行任务
    ///
    /// 用户在 settle 窗口内再次唤出面板时必须取消，否则 ⌘V 会打进刚打开的面板。
    private var pendingPasteTask: Task<Void, Never>?

    /// 数据库
    ///
    /// 全应用一个库，插件的批量数据与插件键值都在里面。`lazy` 是因为打开可能失败，
    /// 而失败的兜底需要写日志（`log` 是实例属性）。
    private(set) lazy var database: SQLiteDatabase = Self.openDatabase()

    /// 设置窗口的数据源桥接
    private(set) lazy var settingsBridge = SettingsBridge(core: self)

    /// 设置窗口控制器
    ///
    /// `lazy` 是因为它需要 `settingsBridge` 作为数据源，而初始化器里不能引用 `self`。
    /// 窗口本身也是惰性创建的：没打开过设置就不该有窗口。
    private(set) lazy var settingsWindowController = SettingsWindowController(dataSource: settingsBridge)

    /// 第一次启动的引导
    private let onboardingController = OnboardingWindowController()

    /// 文件搜索来源
    ///
    /// **不是插件**：它由宿主直接持有并注入给面板协调器，因此不进 `registerPlugins()`、
    /// 不出现在插件列表、也不能被单独禁用。
    private let fileSearchSource = FileSearchSource()

    /// 打开数据库
    ///
    /// 打不开文件时退到内存库继续运行：剪贴板、笔记这些功能不该因为存储问题整个用不了，
    /// 代价是本次运行不落盘 —— 所以这条日志是 error 级，不静默。
    private static func openDatabase() -> SQLiteDatabase {        do {
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

    /// 插件 id → 实例
    ///
    /// 与 `plugins` 同时维护，由 `rebuildCommandCatalog()` 重建。视图工厂、导航、
    /// 命令归属都问它，避免每次都遍历数组。
    private(set) var pluginsByID: [String: any QuickPlugin] = [:]

    /// 命令 id → 负责执行的插件 id
    ///
    /// 静态命令与动态命令的前缀回退是两条不同的路：这里只登记静态 `commands`，
    /// 动态命令（`launcher.app.*`）仍走前缀回退。
    private var commandOwners: [String: String] = [:]

    /// 事件订阅凭证（防止被释放）
    private var subscriptions: [EventSubscription] = []

    /// 调试唤醒通知观察者（必须强引用，否则立即失效）
    private var debugWakeObserver: NSObjectProtocol?

    /// 外观设置变化的观察者（必须强引用）
    private var appearanceSettingObserver: NSObjectProtocol?

    /// 超级面板鼠标偏好变化的观察者（必须强引用）
    private var superPanelDefaultsObserver: NSObjectProtocol?

    /// 最近使用（与协调器共用同一份，设置页清空时也动它）
    var usageHistory: UsageHistory?

    /// 实际生效外观的观察者（必须强引用）
    private var effectiveAppearanceObserver: NSKeyValueObservation?

    /// 设置数据源缓存（避免设置面板切换时重复全量计算与反序列化）
    var cachedIndexedApps: [SettingsAppItem]?
    var cachedCustomCommands: [SettingsCustomCommandItem]?

    private init() {}

    // MARK: - 启动

    /// 启动应用核心
    ///
    /// 由 AppDelegate.applicationDidFinishLaunching 调用一次。
    /// 按顺序完成：创建插件 → 注册事件 → 启动服务 → 激活插件。
    func start() {
        log.notice("AppCore 启动，bundle id=\(Bundle.main.bundleIdentifier ?? "-", privacy: .public)")

        // 0. API Key：UserDefaults 明文 → Keychain（失败保留旧值，下次再试）
        AIConfig.migrateAPIKeyIfNeeded()

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
            plugin.activate()
        }
        rebuildCommandCatalog()

        // 9–13. 开发启动参数（验收用）：统一在这里处理，AppDelegate 不再重复解析
        applyLaunchArguments(ProcessInfo.processInfo.arguments)

        log.notice("AppCore 启动完成")
    }

    /// 解析开发启动参数并执行对应动作
    ///
    /// 优先级：`-showPlugin` > `-showSettingsTab` > `-showSettings` > `-showPalette` /
    /// `-showSuperPanel` / `-showTranslator`（后三者可并存在不同路径上，但设置类互斥）。
    private func applyLaunchArguments(_ arguments: [String]) {
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

    /// 监听开发调试唤醒信号（分布式通知）
    ///
    /// 应用内用 `DistributedNotificationCenter` 发
    /// `com.ixxxxoooo.quick.togglePalette` 即可切换面板（不要用 `notifyutil -p`）。
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
        mouseTriggerMonitor.stop()
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
        guard let plugin = pluginsByID[pluginID],
            plugin.isEnabled
        else {
            log.warning("分离失败：找不到插件 \(pluginID, privacy: .public) 或插件已禁用")
            return
        }

        // 视图能力是运行时查询。`PluginPanelController` 的契约是非可选视图，所以失败时
        // 退化成空视图 —— 代价是窗口空白，所以这里必须留一条 error 说明根因。
        let viewProvider = { () -> AnyView in
            guard let provider = plugin as? PluginViewProviding else {
                QuickLog.app.error(
                    "插件 \(pluginID, privacy: .public) 未实现 PluginViewProviding，分离窗口无法显示")
                return AnyView(EmptyView())
            }
            return provider.makeView()
        }
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
        // 相同外观不重复赋值：这个函数挂在 `UserDefaults.didChangeNotification` 上，
        // 任何一处偏好改动都会触发它（包括设置页里拖动滑块时的连续写入）。
        // 重复赋同一个 `NSAppearance` 会让所有窗口重排，足以打断正在进行的拖动手势。
        let target = appearance.nsAppearance
        guard NSApp.appearance !== target else { return }
        NSApp.appearance = target
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
            (SnippetsPlugin.self, { SnippetsPlugin(storage: self.storage(for: SnippetsPlugin.id)) }),
            (OCRPlugin.self, { OCRPlugin() }),
            (TranslatorPlugin.self, { TranslatorPlugin(storage: self.storage(for: TranslatorPlugin.id)) }),

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
            (KillProcessPlugin.self, { KillProcessPlugin() }),
            (NetworkToolsPlugin.self, { NetworkToolsPlugin() }),
            (ScreenshotPlugin.self, { ScreenshotPlugin() })
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
                let targetApp = self.paletteCoordinator.hide(restoreFocus: true)
                self.schedulePasteIntoPreviousApp(targetApp: targetApp)
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

    // MARK: - 超级面板

    /// 接线超级面板：系统能力注入 + 鼠标唤出 + 默认快捷键
    ///
    /// 超级面板不认识 `QuickPlatform`（依赖方向），所以抓选区、合成粘贴、解析最近使用
    /// 都由这里注入进去。鼠标监听也归宿主：它是一项系统能力，不该跟着某个插件生死。
    private func wireSuperPanel() {
        let controller = superPanelController
        controller.captureSelection = { await SelectionCapture.captureText() }
        controller.canPaste = { [weak self] in self?.pasteService.canSynthesize ?? false }
        controller.paste = { [weak self] in _ = self?.pasteService.paste() }
        controller.recentItems = { [weak self] in self?.resolveRecentItems() ?? [] }
        controller.openSettings = { [weak self] in
            self?.settingsWindowController.show(tab: .superPanel)
        }

        mouseTriggerMonitor.onTrigger = { [weak self] kind in
            Task { @MainActor in
                QuickLog.app.notice(
                    "鼠标触发超级面板：\(String(describing: kind), privacy: .public)")
                self?.paletteCoordinator.hide(restoreFocus: false)
                self?.superPanelController.toggle()
            }
        }
        syncMouseTriggerConfiguration()

        if superPanelDefaultsObserver == nil {
            superPanelDefaultsObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: UserDefaults.standard,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.syncMouseTriggerConfiguration()
                }
            }
        }

        // 默认 ⌥C（对齐 Fasty）。用户清空后不再自动补回。
        if hotKeyService.binding(for: CommandID.superPanel) == nil {
            let shortcut = KeyShortcut(carbonKeyCode: kVK_ANSI_C, carbonModifiers: optionKey)
            _ = hotKeyService.setBinding(shortcut, for: CommandID.superPanel, registerNow: true)
        }
        controller.prewarm()
        log.notice("超级面板已接线")
    }

    /// 把鼠标偏好同步到监听器
    private func syncMouseTriggerConfiguration() {
        let config = SuperPanelPreferences.mouseConfiguration()
        mouseTriggerMonitor.apply(
            MouseTriggerMonitor.Configuration(
                rightLongPressEnabled: config.rightLongPressEnabled,
                middleClickEnabled: config.middleClickEnabled,
                thresholdMilliseconds: UInt64(config.thresholdMilliseconds)
            )
        )
    }

    /// 把「最近使用」的条目 id 解析成可展示的行（最多 4 条，对齐 Fasty）
    private func resolveRecentItems() -> [SuperPanelRecentItem] {
        guard let ids = usageHistory?.recentItemIDs(limit: 12) else { return [] }
        var items: [SuperPanelRecentItem] = []
        for id in ids {
            if let item = resolveRecentItem(id) {
                items.append(item)
            }
            if items.count >= 4 { break }
        }
        return items
    }

    /// 单个 id 的解析：应用、插件入口、插件命令
    private func resolveRecentItem(_ id: String) -> SuperPanelRecentItem? {
        if id.hasPrefix(CommandID.launchAppPrefix) {
            let bundleID = String(id.dropFirst(CommandID.launchAppPrefix.count))
            guard let app = appIndex.apps.first(where: { $0.bundleID == bundleID }) else { return nil }
            return SuperPanelRecentItem(
                id: id, title: app.name, subtitle: app.path, icon: "app",
                kind: .app, launchPath: app.path)
        }
        if let pluginID = CommandID.openedPluginID(in: id),
            let plugin = pluginsByID[pluginID]
        {
            return SuperPanelRecentItem(
                id: id, title: type(of: plugin).name, icon: type(of: plugin).icon,
                kind: .plugin, pluginID: pluginID)
        }
        // 功能命令：走命令归属表，与执行路径用的是同一份索引
        if let ownerID = commandOwners[id], let plugin = pluginsByID[ownerID] {
            return SuperPanelRecentItem(
                id: id, title: type(of: plugin).name, icon: type(of: plugin).icon,
                kind: .plugin, pluginID: ownerID)
        }
        return nil
    }

    // MARK: - 粘贴回上一个应用

    /// 最大等待前台应用激活时长（兜底）
    private static let maxPasteSettleDelay = Duration.milliseconds(120)

    /// 等前一个应用回到前台，再合成一次 ⌘V；没有辅助功能权限就只提示
    ///
    /// 相比固定死等 140ms，这里主动轮询 `frontmostApplication`：一旦目标应用成为前台，
    /// 仅保留 25ms 事件队列缓冲区就立即合成 ⌘V，实测 ~35-50ms 即可完成填充；若目标未响应
    /// 则在 120ms 兜底触发，兼顾瞬时手感与稳定性。
    private func schedulePasteIntoPreviousApp(targetApp: NSRunningApplication? = nil) {
        let canPaste = pasteService.canSynthesize
        pendingPasteTask?.cancel()
        pendingPasteTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard canPaste else {
                // 面板已隐藏，剪贴板里已经有内容了 —— 告诉用户为什么没自动粘贴
                self.hudController.show(
                    message: "已复制，开启辅助功能权限后可自动粘贴",
                    tone: .warning
                )
                return
            }

            let start = ContinuousClock.now
            if let targetApp, !targetApp.isTerminated {
                let targetPID = targetApp.processIdentifier
                let deadline = start + Self.maxPasteSettleDelay

                // 快速轮询等待目标应用成为 frontmostApplication
                while ContinuousClock.now < deadline {
                    if NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID {
                        // 目标应用已成为前台，等待短暂缓冲确保其窗口事件队列与光标就绪
                        try? await Task.sleep(for: .milliseconds(25))
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(8))
                }
            } else {
                // 没有明确目标应用时（例如上一应用已退出或未知），使用短固定延时
                try? await Task.sleep(for: .milliseconds(40))
            }

            guard !Task.isCancelled else { return }
            let waited = start.duration(to: .now).invokeMS
            self.log.notice("准备合成 ⌘V，等待上一应用就绪耗时：\(waited, format: .fixed(precision: 1)) ms")
            self.pasteService.paste()
        }
    }

    /// 取消尚未发出的合成粘贴（再次唤出面板时调用）
    private func cancelPendingPaste() {
        pendingPasteTask?.cancel()
        pendingPasteTask = nil
    }

    // MARK: - 自定义命令存储辅助

    func loadCustomCommands() -> [CustomCommand] {
        guard let data = settingsStore.customCommandsData,
            let list = try? JSONDecoder().decode([CustomCommand].self, from: data)
        else {
            return []
        }
        return list
    }

    func saveCustomCommands(_ commands: [CustomCommand]) {
        let data = try? JSONEncoder().encode(commands)
        settingsStore.setCustomCommandsData(data)
        cachedCustomCommands = nil
    }

    // MARK: - 快捷键恢复

    /// 执行一条命令。热键和搜索共用这一条路径
    private func invoke(commandID: String) {
        let invokeStart = ContinuousClock.now
        // 再次唤出时取消尚未发出的 ⌘V，避免打进面板自己的搜索框
        cancelPendingPaste()
        log.notice("执行命令 \(commandID, privacy: .public)")
        // 超级面板不是插件命令，也不在命令目录里，单独认领
        if commandID == CommandID.superPanel {
            paletteCoordinator.hide(restoreFocus: false)
            superPanelController.toggle()
            return
        }
        if commandID != CommandID.togglePalette, !settingsStore.isCommandEnabled(commandID) {
            log.notice("命令已关闭，拒绝调用 \(commandID, privacy: .public)")
            return
        }
        if commandID == CommandID.togglePalette {
            paletteCoordinator.toggle()
            let ms = invokeStart.duration(to: .now).invokeMS
            log.notice("invoke 完成（togglePalette）：\(ms, format: .fixed(precision: 1)) ms")
            return
        }
        if let pluginID = CommandID.openedPluginID(in: commandID) {
            // 与 togglePalette 同语义：面板正开着这个插件时再按一次就关掉，
            // 否则（关着 / 停在别的插件 / 主搜索）打开或切过去
            if paletteCoordinator.isVisible, paletteCoordinator.activePluginID == pluginID {
                paletteCoordinator.hide()
            } else {
                paletteCoordinator.show(pluginID: pluginID)
            }
            let ms = invokeStart.duration(to: .now).invokeMS
            log.notice("invoke 完成（openPlugin \(pluginID, privacy: .public)）：\(ms, format: .fixed(precision: 1)) ms")
            return
        }
        guard let plugin = plugin(forCommand: commandID) else {
            log.warning("没有插件认领命令 \(commandID, privacy: .public)")
            return
        }
        // 功能命令也做切换：面板正在显示该插件时再按同一个插件的快捷键就关掉。
        // plugin.open.* 已在上面处理，这里兜住 clipboard.clear 这类功能命令热键。
        let ownerPluginID = type(of: plugin).id
        if paletteCoordinator.isVisible, paletteCoordinator.activePluginID == ownerPluginID {
            paletteCoordinator.hide()
            let ms = invokeStart.duration(to: .now).invokeMS
            log.notice("invoke 完成（功能命令切换关闭 \(ownerPluginID, privacy: .public)）：\(ms, format: .fixed(precision: 1)) ms")
            return
        }
        plugin.perform(commandID: commandID)
        let ms = invokeStart.duration(to: .now).invokeMS
        log.notice("invoke 完成（perform \(commandID, privacy: .public)）：\(ms, format: .fixed(precision: 1)) ms")
    }

    /// 按插件 id 取实例
    ///
    /// 设置页与事件路由用它；`plugins` 数组仍保留给需要遍历的路径（注册、启停、退出）。
    func plugin(withID pluginID: String) -> (any QuickPlugin)? {
        pluginsByID[pluginID]
    }

    /// 某条命令归哪个插件
    ///
    /// 只查静态 `commands` 的登记表；动态命令（`launcher.app.*`）没有归属条目，
    /// 调用方需要自己认前缀。
    func pluginID(owningCommand commandID: String) -> String? {
        commandOwners[commandID]
    }

    /// 取某条命令的声明
    ///
    /// 设置页要用它的标题、关键词与图标来渲染一行 —— 这些信息只在声明里，
    /// 从执行路径拿不到。
    func commandDescriptor(of commandID: String, in pluginID: String) -> CommandDescriptor? {
        guard let plugin = pluginsByID[pluginID] else { return nil }
        return type(of: plugin).commands.first { $0.id == commandID }
    }

    /// 按命令 id 找到负责执行的插件
    ///
    /// 走 `commandOwners` 字典而不是遍历插件数组：设置页、热键、搜索结果都会问
    /// 「这条命令归谁」，线性扫描会随插件数与命令数一起增长。
    private func plugin(forCommand commandID: String) -> (any QuickPlugin)? {
        if let ownerID = commandOwners[commandID] {
            return pluginsByID[ownerID]
        }
        // 动态命令（如 `launcher.app.*`、`launcher.shell.*`）不在静态 `commands` 里，
        // 没有映射条目，只能按插件 id 前缀回退。前缀匹配天然只能遍历，但这类命令
        // 只在执行时问一次，不在按键热路径上。
        return plugins.first { commandID.hasPrefix(type(of: $0).id + ".") }
    }

    /// 用当前插件声明和开关重建静态命令快照，并按开关注册热键
    ///
    /// 顺带重建两个查找表（`pluginsByID`、`commandOwners`）—— 它们和命令快照
    /// 来自同一份数据，分开重建迟早会出现「快照里有的命令索引里没有」。
    func rebuildCommandCatalog() {
        var indexed: [IndexedCommand] = []
        var owners: [String: String] = [:]
        var byID: [String: any QuickPlugin] = [:]

        for plugin in plugins {
            let meta = type(of: plugin)
            byID[meta.id] = plugin

            // 命令归属与「是否启用」无关：禁用的插件也可能收到热键（用户先绑了键、
            // 后关掉插件），那时要能找到它并打日志说明它为什么没执行。
            for command in meta.commands {
                owners[command.id] = meta.id
            }

            guard plugin.isEnabled, settingsStore.isSearchSourceEnabled(meta.id) else { continue }
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

        pluginsByID = byID
        commandOwners = owners
        paletteCoordinator.staticCommands = indexed
        hotKeyService.syncRegistrations { [settingsStore] commandID in
            commandID == CommandID.togglePalette
                || commandID == CommandID.superPanel
                || settingsStore.isCommandEnabled(commandID)
        }
        log.notice(
            """
            命令目录已更新：静态命令 \(indexed.count, privacy: .public) 条，\
            登记归属 \(owners.count, privacy: .public) 条
            """)
    }
}

extension Duration {
    /// 转换为毫秒数（双精度），给 invoke 链路计时用
    fileprivate var invokeMS: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) * 1000 + Double(attoseconds) / 1_000_000_000_000_000
    }
}
