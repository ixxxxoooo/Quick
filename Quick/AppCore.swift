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
import Foundation
import QuickCore
import QuickPlatform
import QuickUI

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

        // 4. 启动基础设施服务
        hotKeyService.onTogglePalette = { [weak self] in
            self?.paletteCoordinator.toggle()
        }
        hotKeyService.start()
        statusItemController.install()
        observeDebugWakeSignals()

        // 5. 后台刷新应用索引（不阻塞启动）
        Task { await appIndex.refresh() }

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
        for module in modules {
            module.deactivate()
        }
        EventBus.shared.removeAll()
        log.notice("退出清理完成")
    }

    // MARK: - 模块注册

    /// 注册所有 Feature Module
    ///
    /// 这是唯一创建模块实例的地方。
    /// 新增模块只需在此处添加一行注册。
    private func registerModules() {
        // Phase 2: 核心模块
        register(LauncherModule(appIndex: appIndex))
        register(ClipboardModule())
        register(CalculatorModule())
        register(SystemControlModule())

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
    }
}

// MARK: - 设置窗口的数据源

/// `AppCore` 是设置界面的数据源
///
/// 设置界面在 `QuickUI`，而模块实例与系统能力（登录项、快捷键）只有组装层看得到，
/// 所以由这里实现协议、把两边接起来。
extension AppCore: SettingsDataSource {

    /// 全部模块，按显示名排序
    ///
    /// 排序而不是按注册顺序：注册顺序是代码结构，用户不该看到它。
    var moduleEntries: [SettingsModule] {
        modules
            .map { SettingsModule(id: type(of: $0).id, name: type(of: $0).name, icon: type(of: $0).icon) }
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

    var isLaunchAtLoginEnabled: Bool { launchAtLogin.isEnabled }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin.setEnabled(enabled)
    }

    var hotKeyDescription: String { HotKeyService.defaultHotKeyDescription }

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
