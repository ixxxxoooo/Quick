// SettingsBridge+Plugins.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Carbon.HIToolbox
import Foundation
import PluginLauncher
import PluginSystemControl
import QuickCore
import QuickPlatform
import QuickUI
import SwiftUI

/// 功能插件设置：键盘布局、插件开关、各插件专属设置页
///
/// 从 `SettingsBridge.swift` 按设置页分区拆出，协议一致性仍声明在主类上。
extension SettingsBridge {

    // MARK: - 功能插件设置

    /// 系统里可选的键盘布局
    var keyboardLayouts: [SettingsKeyboardLayout] {
        core.keyboardLayoutService.availableLayouts().map {
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
        core.plugins
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
        core.settingsStore.isPluginEnabled(id)
    }

    /// 切换插件启用状态
    ///
    /// 三件事必须一起做：持久化、改插件实例、启停插件。
    /// 只改设置不启停，用户会看到开关变了但功能还在跑（或反过来）。
    func setPluginEnabled(_ id: String, enabled: Bool) {
        core.settingsStore.setPluginEnabled(id, enabled: enabled)

        guard let plugin = core.pluginsByID[id] else {
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
        core.rebuildCommandCatalog()
    }

    func makeFeatureSettingsView(for tab: SettingsTab) -> AnyView? {
        guard let pluginID = tab.pluginID,
            let plugin = core.pluginsByID[pluginID]
        else {
            return nil
        }
        // 设置页能力同样是运行时查询：没实现就回落到 FeatureSettingsPane 的默认三段式布局，
        // 这不是错误路径，所以不打日志。
        return (plugin as? PluginSettingsProviding)?.makeSettingsView()
    }
}
