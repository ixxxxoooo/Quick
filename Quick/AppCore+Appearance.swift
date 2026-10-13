// AppCore+Appearance.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Carbon.HIToolbox
import Foundation
import QuickCore
import QuickPlatform
import QuickUI
import SwiftUI

/// 外观：浅色 / 深色 / 跟随系统及其监听
///
/// 从 `AppCore.swift` 按职责拆出的扩展：状态仍然只属于 `AppCore`（唯一所有者），
/// 这里只放行为。拆文件是为了让每个文件能一次读完，不是为了拆出新的所有者。
extension AppCore {

    // MARK: - 外观

    /// 应用外观设置
    ///
    /// **全仓只有这一处给 `NSApp.appearance` 赋值。** 它是应用级的，所以面板、设置窗口、
    /// 分离窗口一起跟着变 —— 逐个窗口设置迟早会漏掉一个（HUD、分离窗口、设置窗口各一份），
    /// 而 `.system` 映射成 `nil` 之后，系统切换外观由 AppKit 自己跟进，不需要我们监听什么。
    func applyAppearance() {
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
    func observeAppearance() {
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
}
