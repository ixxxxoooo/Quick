// AppCore.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import ModuleAI
import ModuleCalculator
import ModuleCalendar
import ModuleClipboard
import ModuleDevTools
import ModuleFileSearch
import ModuleLauncher
import ModuleNetworkTools
import ModuleNotes
import ModuleOCR
import ModuleScreenshot
import ModuleSnippets
import ModuleSystemControl
import ModuleSystemMonitor
import ModuleTranslator
import ModuleWeather
import ModuleWindowManager
import Carbon.HIToolbox
import Foundation
import QuickCore
import QuickPlatform
import QuickUI
import SwiftUI

/// 应用核心组装器
///
/// AppCore 是整个应用的组装层，职责如下：
/// 1. 创建所有基础设施服务和 Feature Module 实例
/// 2. 将依赖注入到各模块
/// 3. 连接 EventBus 的订阅关系
/// 4. 管理全局生命周期（启动/退出）
///
/// AppCore **不持有任何业务逻辑**，不处理搜索、不管理 UI 状态。
@MainActor
final class AppCore {

    /// 全局单例
    static let shared = AppCore()

    private let log = QuickLog.app

    // MARK: - 基础设施（不是 Module）

    /// 全局快捷键服务
    let hotKeyService = HotKeyService()

    /// 面板协调器
    let paletteCoordinator = PaletteCoordinator()

    /// 权限服务
    let permissionService = PermissionService()

    /// 粘贴板服务
    let pasteboardService = PasteboardService()

    /// 应用索引
    let appIndex = AppIndex()

    /// HUD 控制器
    let hudController = HUDController()

    /// 分离窗口控制器
    let modulePanelController = ModulePanelController()

    /// 开机自启管理
    let launchAtLogin = LaunchAtLogin()

    /// 菜单栏状态项
    let statusItemController = StatusItemController()

    /// 用户设置存储（模块开关等）
    let settingsStore = SettingsStore()

    /// 设置窗口控制器
    ///
    /// `lazy` 是因为它需要 `self` 作为数据源，而初始化器里不能引用 `self`。
    /// 窗口本身也是惰性创建的：没打开过设置就不该有窗口。
    private(set) lazy var settingsWindowController = SettingsWindowController(dataSource: self)

    // MARK: - Feature Modules

    /// 所有已注册模块
    private(set) var modules: [any QuickModule] = []

    /// 事件订阅凭证（防止被释放）
    private var subscriptions: [EventSubscription] = []

    /// 调试唤醒通知观察者（必须强引用，否则立即失效）
    private var debugWakeObserver: NSObjectProtocol?

    /// 设置数据源缓存（避免设置面板切换时重复全量计算与反序列化）
    private var cachedIndexedApps: [SettingsAppItem]?
    private var cachedCustomCommands: [SettingsCustomCommandItem]?

    private init() {}

    // MARK: - 启动

    /// 启动应用核心
    ///
    /// 由 AppDelegate.applicationDidFinishLaunching 调用一次。
    /// 按顺序完成：创建模块 → 注册事件 → 启动服务 → 激活模块。
    func start() {
        log.notice("AppCore 启动，bundle id=\(Bundle.main.bundleIdentifier ?? "-", privacy: .public)")

        // 1. 创建并注册所有 Feature Module
        registerModules()
        log.notice("模块注册完成，共 \(self.modules.count, privacy: .public) 个")

        // 2. 将模块注入到面板协调器
        paletteCoordinator.setModules(modules)

        // 3. 连接事件总线
        wireEventBus()
        log.notice("事件总线接线完成，订阅 \(self.subscriptions.count, privacy: .public) 条")

        // 4. 设置协调器的分离回调
        paletteCoordinator.onDetach = { [weak self] moduleID in
            self?.detachModule(moduleID)
        }

        // 5. 启动基础设施服务
        hotKeyService.onTogglePalette = { [weak self] in
            self?.paletteCoordinator.toggle()
        }
        hotKeyService.onLaunchApp = { [weak self] bundleID in
            self?.appIndex.app(withBundleID: bundleID)?.launch()
        }
        hotKeyService.onRunSystemAction = { [weak self] id in
            if let systemModule = self?.modules.first(where: { type(of: $0).id == SystemControlModule.id })
                as? SystemControlModule,
                let action = SystemAction(rawValue: id)
            {
                systemModule.execute(action)
            }
        }
        hotKeyService.onRunCustomCommand = { [weak self] id in
            guard let self else { return }
            let list = self.loadCustomCommands()
            if let cmd = list.first(where: { $0.id == id && $0.isEnabled }) {
                Task {
                    let result = await ShellCommandRunner.run(
                        cmd.command, workingDirectory: cmd.workingDirectory)
                    EventBus.shared.post(
                        ShowHUDEvent(
                            message: String(result.summary.prefix(80)),
                            tone: result.succeeded ? .success : .warning
                        )
                    )
                }
            }
        }
        hotKeyService.onNavigateToModule = { [weak self] moduleID in
            self?.paletteCoordinator.show(moduleID: moduleID)
        }
        hotKeyService.start()

        // 快捷键录制协调器：录制时暂停/恢复全局快捷键
        ShortcutRecorderCoordinator.shared.onPause = { [weak self] in
            self?.hotKeyService.isPaused = true
        }
        ShortcutRecorderCoordinator.shared.onResume = { [weak self] in
            self?.hotKeyService.isPaused = false
        }

        statusItemController.install()
        observeDebugWakeSignals()

        // 5. 读取持久化的搜索范围并在后台刷新应用索引
        let initialScopes = settingsStore.searchScopes(defaultScopes: SearchScopes.defaults)
        Task {
            await appIndex.refresh(scopes: initialScopes)
            self.restoreSavedHotKeys()
        }

        // 6. 激活所有已启用的模块
        for module in modules where module.isEnabled {
            module.activate()
        }

        // 7. 开发启动参数：立即显示面板（验收用）
        if ProcessInfo.processInfo.arguments.contains("-showPalette") {
            log.notice("命中启动参数 -showPalette，立即显示面板")
            paletteCoordinator.show()
        }

        // 8. 开发启动参数：立即显示设置窗口（验收用）
        if ProcessInfo.processInfo.arguments.contains("-showSettings") {
            log.notice("命中启动参数 -showSettings，立即显示设置窗口")
            paletteCoordinator.hide()
            settingsWindowController.show()
        }

        log.notice("AppCore 启动完成")
    }

    /// 监听开发调试唤醒信号（分布式通知）
    ///
    /// 用法：`notifyutil -p com.ygw.quick.togglePalette`
    private func observeDebugWakeSignals() {
        debugWakeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.ygw.quick.togglePalette"),
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
        modulePanelController.closeAll()
        for module in modules {
            module.deactivate()
        }
        EventBus.shared.removeAll()
        log.notice("退出清理完成")
    }

    // MARK: - 模块分离

    /// 将指定模块分离为独立窗口
    ///
    /// 查找模块实例 → 获取视图 → 创建独立窗口 → 主面板返回搜索模式。
    private func detachModule(_ moduleID: String) {
        guard let module = modules.first(where: { type(of: $0).id == moduleID }),
            module.isEnabled
        else {
            log.warning("分离失败：找不到模块 \(moduleID, privacy: .public) 或模块已禁用")
            return
        }

        let view = module.makeView()
        let name = type(of: module).name
        let icon = type(of: module).icon

        modulePanelController.detach(
            moduleID: moduleID,
            moduleName: name,
            icon: icon,
            view: view,
            sourceWindow: nil
        )

        paletteCoordinator.popToRoot()
        paletteCoordinator.hide(restoreFocus: false)
    }

    // MARK: - 模块注册

    /// 注册所有 Feature Module
    ///
    /// 这是唯一创建模块实例的地方。
    /// 新增模块只需在此处添加一行注册。
    private func registerModules() {
        // Phase 2: 核心模块
        register(LauncherModule(appIndex: appIndex, settingsStore: settingsStore))
        register(ClipboardModule())
        register(CalculatorModule())
        register(SystemControlModule(settingsStore: settingsStore))

        // Phase 3: 效率与工具模块
        register(FileSearchModule())
        register(SnippetsModule())
        register(OCRModule())
        register(TranslatorModule())
        register(DevToolsModule())

        // Phase 4: 扩展模块
        register(CalendarModule())
        register(WeatherModule())
        register(NotesModule())
        register(AIModule())
        register(WindowManagerModule())
        register(SystemMonitorModule())
        register(NetworkToolsModule())
        register(ScreenshotModule())
    }

    /// 注册一个模块，并恢复用户上次的启用状态
    ///
    /// 启用状态在这里从设置里读出来应用，而不是让模块自己去读：
    /// 模块不认识设置存储，依赖方向保持单向。
    ///
    /// - Parameter module: 模块实例
    private func register(_ module: any QuickModule) {
        module.isEnabled = settingsStore.isModuleEnabled(type(of: module).id)
        modules.append(module)
    }

    // MARK: - 事件总线连接

    /// 连接 EventBus 订阅
    ///
    /// 所有模块间的通信都在这里统一接线。
    /// 模块发布事件 → EventBus → AppCore 路由到目标。
    private func wireEventBus() {
        let bus = EventBus.shared

        // 导航事件 → 面板协调器
        subscriptions.append(
            bus.on(NavigateEvent.self) { [weak self] event in
                self?.paletteCoordinator.navigate(to: event.moduleID, context: event.context)
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

        // 显示面板事件
        subscriptions.append(
            bus.on(ShowPaletteEvent.self) { [weak self] event in
                self?.paletteCoordinator.show(moduleID: event.moduleID, query: event.query)
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

        // 分离面板事件 → 创建独立模块窗口
        subscriptions.append(
            bus.on(DetachPanelEvent.self) { [weak self] event in
                guard let self else { return }
                self.detachModule(event.moduleID)
            }
        )

        // 应用索引刷新事件（清除设置应用缓存）
        subscriptions.append(
            bus.on(AppIndexRefreshedEvent.self) { [weak self] _ in
                self?.cachedIndexedApps = nil
            }
        )
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

    private func restoreSavedHotKeys() {
        let appIDs = appIndex.apps.map(\.bundleID)
        let systemIDs = SystemAction.allCases.map(\.rawValue)
        let cmdIDs = loadCustomCommands().map(\.id)
        let moduleIDs = modules.map { type(of: $0).id }
        hotKeyService.restoreHotKeys(
            appBundleIDs: appIDs, systemActionIDs: systemIDs,
            customCommandIDs: cmdIDs, moduleIDs: moduleIDs)
    }
}

// MARK: - 设置窗口的数据源

/// `AppCore` 是设置界面的数据源
///
/// 设置界面在 `QuickUI`，而模块实例与系统能力（登录项、快捷键）只有组装层看得到，
/// 所以由这里实现协议、把两边接起来。
extension AppCore: SettingsDataSource {

    // MARK: - 通用设置

    var isLaunchAtLoginEnabled: Bool { launchAtLogin.isEnabled }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin.setEnabled(enabled)
    }

    var hotKeyDescription: String { HotKeyService.defaultHotKeyDescription }

    var globalShortcutKeycaps: [String]? {
        hotKeyService.binding(for: .togglePalette)?.keycaps
    }

    func setGlobalShortcut(keyCode: Int, carbonModifiers: Int) {
        let shortcut = KeyShortcut(carbonKeyCode: keyCode, carbonModifiers: carbonModifiers)
        hotKeyService.setBinding(shortcut, for: .togglePalette)
    }

    func clearGlobalShortcut() {
        // 清除后恢复默认的 ⌥Space
        let defaultShortcut = KeyShortcut(
            carbonKeyCode: kVK_Space,
            carbonModifiers: optionKey
        )
        hotKeyService.setBinding(defaultShortcut, for: .togglePalette)
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
            self.restoreSavedHotKeys()
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
            let shortcut = hotKeyService.binding(for: .app(bundleID: entry.bundleID))
            return SettingsAppItem(
                id: entry.id,
                name: entry.name,
                bundleID: entry.bundleID,
                path: entry.path,
                isSystemApp: entry.isSystemApp,
                alias: alias,
                shortcutKeycaps: shortcut?.keycaps
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

    func setAppShortcut(keyCode: Int, carbonModifiers: Int, for bundleID: String) {
        let shortcut = KeyShortcut(carbonKeyCode: keyCode, carbonModifiers: carbonModifiers)
        hotKeyService.setBinding(shortcut, for: .app(bundleID: bundleID))
        cachedIndexedApps = nil
    }

    func clearAppShortcut(for bundleID: String) {
        hotKeyService.setBinding(nil, for: .app(bundleID: bundleID))
        cachedIndexedApps = nil
    }

    // MARK: - 启动器：系统操作

    var systemActions: [SettingsSystemActionItem] {
        SystemAction.allCases.map { action in
            let alias = settingsStore.alias(for: "system." + action.rawValue)
            let shortcut = hotKeyService.binding(for: .systemAction(id: action.rawValue))
            return SettingsSystemActionItem(
                id: action.rawValue,
                title: action.title,
                description: action.description,
                icon: action.icon,
                alias: alias,
                shortcutKeycaps: shortcut?.keycaps
            )
        }
    }

    func setSystemActionAlias(_ alias: String?, for id: String) {
        settingsStore.setAlias(alias, for: "system." + id)
    }

    func setSystemActionShortcut(keyCode: Int, carbonModifiers: Int, for id: String) {
        let shortcut = KeyShortcut(carbonKeyCode: keyCode, carbonModifiers: carbonModifiers)
        hotKeyService.setBinding(shortcut, for: .systemAction(id: id))
    }

    func clearSystemActionShortcut(for id: String) {
        hotKeyService.setBinding(nil, for: .systemAction(id: id))
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
            let shortcut = hotKeyService.binding(for: .customCommand(id: cmd.id))
            return SettingsCustomCommandItem(
                id: cmd.id,
                name: cmd.name,
                command: cmd.command,
                isEnabled: cmd.isEnabled,
                alias: cmd.alias,
                shortcutKeycaps: shortcut?.keycaps,
                workingDirectory: cmd.workingDirectory
            )
        }
        cachedCustomCommands = items
        return items
    }

    func addCustomCommand(name: String, command: String, workingDirectory: String?) {
        var list = loadCustomCommands()
        let item = CustomCommand(
            name: name,
            command: command,
            isEnabled: true,
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
        workingDirectory: String?
    ) {
        var list = loadCustomCommands()
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        list[index].name = name
        list[index].command = command
        list[index].isEnabled = isEnabled
        list[index].alias = alias
        list[index].workingDirectory = workingDirectory
        saveCustomCommands(list)
    }

    func deleteCustomCommand(id: UUID) {
        var list = loadCustomCommands()
        list.removeAll { $0.id == id }
        saveCustomCommands(list)
        clearCustomCommandShortcut(for: id)
    }

    func setCustomCommandShortcut(keyCode: Int, carbonModifiers: Int, for id: UUID) {
        let shortcut = KeyShortcut(carbonKeyCode: keyCode, carbonModifiers: carbonModifiers)
        hotKeyService.setBinding(shortcut, for: .customCommand(id: id))
        cachedCustomCommands = nil
    }

    func clearCustomCommandShortcut(for id: UUID) {
        hotKeyService.setBinding(nil, for: .customCommand(id: id))
        cachedCustomCommands = nil
    }

    // MARK: - 功能模块设置

    /// 全部模块，按显示名排序
    ///
    /// 排序而不是按注册顺序：注册顺序是代码结构，用户不该看到它。
    var moduleEntries: [SettingsModule] {
        modules
            .map {
                SettingsModule(
                    id: type(of: $0).id,
                    name: type(of: $0).name,
                    icon: type(of: $0).icon,
                    triggerWords: type(of: $0).triggerWords
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func isModuleEnabled(_ id: String) -> Bool {
        settingsStore.isModuleEnabled(id)
    }

    /// 切换模块启用状态
    ///
    /// 三件事必须一起做：持久化、改模块实例、启停模块。
    /// 只改设置不启停，用户会看到开关变了但功能还在跑（或反过来）。
    func setModuleEnabled(_ id: String, enabled: Bool) {
        settingsStore.setModuleEnabled(id, enabled: enabled)

        guard let module = modules.first(where: { type(of: $0).id == id }) else {
            log.warning("找不到模块 \(id, privacy: .public)，设置已保存但未同步实例")
            return
        }
        guard module.isEnabled != enabled else { return }

        module.isEnabled = enabled
        if enabled {
            module.activate()
        } else {
            module.deactivate()
        }
        log.notice("模块 \(id, privacy: .public) 已\(enabled ? "启用" : "停用", privacy: .public)并同步实例")
    }

    func makeFeatureSettingsView(for tab: SettingsTab) -> AnyView? {
        guard let moduleID = tab.moduleID,
            let module = modules.first(where: { type(of: $0).id == moduleID })
        else {
            return nil
        }
        return module.makeSettingsView()
    }

    func moduleShortcutKeycaps(for moduleID: String) -> [String]? {
        hotKeyService.binding(for: .module(id: moduleID))?.keycaps
    }

    func setModuleShortcut(keyCode: Int, carbonModifiers: Int, for moduleID: String) {
        let shortcut = KeyShortcut(carbonKeyCode: keyCode, carbonModifiers: carbonModifiers)
        hotKeyService.setBinding(shortcut, for: .module(id: moduleID))
    }

    func clearModuleShortcut(for moduleID: String) {
        hotKeyService.setBinding(nil, for: .module(id: moduleID))
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
            // 定位的申请入口只有天气模块那一处（用户主动查看天气时），
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
