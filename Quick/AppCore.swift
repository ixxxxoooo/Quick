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
        modules.append(LauncherModule(appIndex: appIndex))
        modules.append(ClipboardModule())
        modules.append(CalculatorModule())
        modules.append(SystemControlModule())

        // Phase 3: 效率与工具模块
        modules.append(FileSearchModule())
        modules.append(SnippetsModule())
        modules.append(OCRModule())
        modules.append(TranslatorModule())
        modules.append(DevToolsModule())

        // Phase 4: 扩展模块
        modules.append(CalendarModule())
        modules.append(WeatherModule())
        modules.append(NotesModule())
        modules.append(AIModule())
        modules.append(WindowManagerModule())
        modules.append(SystemMonitorModule())
        modules.append(NetworkToolsModule())
        modules.append(ScreenshotModule())
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
