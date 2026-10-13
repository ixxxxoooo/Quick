// AppCore+EventBus.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Carbon.HIToolbox
import Foundation
import QuickCore
import QuickPlatform
import QuickUI
import SwiftUI

/// 事件总线连接：插件间通信与宿主响应的全部接线
///
/// 从 `AppCore.swift` 按职责拆出的扩展：状态仍然只属于 `AppCore`（唯一所有者），
/// 这里只放行为。拆文件是为了让每个文件能一次读完，不是为了拆出新的所有者。
extension AppCore {

    // MARK: - 事件总线连接

    /// 连接 EventBus 订阅
    ///
    /// 所有插件间的通信都在这里统一接线。
    /// 插件发布事件 → EventBus → AppCore 路由到目标。
    func wireEventBus() {
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
                let requestedAt = ContinuousClock.now
                let targetApp = self.paletteCoordinator.hide(restoreFocus: true)
                self.schedulePasteIntoPreviousApp(targetApp: targetApp, requestedAt: requestedAt)
            }
        )

        // 显示面板事件
        subscriptions.append(
            bus.on(ShowPaletteEvent.self) { [weak self] event in
                self?.paletteCoordinator.show(pluginID: event.pluginID, query: event.query)
            }
        )

        // 打开设置窗口事件（支持跳转到指定插件）
        subscriptions.append(
            bus.on(ShowPaletteSettingsEvent.self) { [weak self] event in
                Task { @MainActor in
                    self?.paletteCoordinator.hide(restoreFocus: false)
                    if let pluginID = event.pluginID,
                        let tab = SettingsTab.tab(forPluginID: pluginID)
                    {
                        self?.settingsWindowController.show(tab: tab)
                    } else {
                        self?.settingsWindowController.show()
                    }
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

        // 面板唤出时轻量级校验应用目录 mtime，有变动则自动重扫应用
        subscriptions.append(
            bus.on(PaletteVisibilityChangedEvent.self) { [weak self] event in
                guard event.isVisible else { return }
                Task { [weak self] in
                    await self?.appIndex.checkAndRefreshIfNeeded()
                }
            }
        )

        subscriptions.append(
            bus.on(CommandCatalogChangedEvent.self) { [weak self] _ in
                self?.rebuildCommandCatalog()
            }
        )
    }
}
