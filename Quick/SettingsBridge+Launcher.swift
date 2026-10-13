// SettingsBridge+Launcher.swift
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

/// 启动器设置：应用与搜索范围、系统操作、Shell 与自定义命令
///
/// 从 `SettingsBridge.swift` 按设置页分区拆出，协议一致性仍声明在主类上。
extension SettingsBridge {

    // MARK: - 启动器：应用与搜索范围

    var searchScopes: [String] {
        core.settingsStore.searchScopes(defaultScopes: SearchScopes.defaults)
    }

    func setSearchScopes(_ scopes: [String]) {
        core.settingsStore.setSearchScopes(scopes)
        Task {
            await core.appIndex.refresh(scopes: scopes)
            core.cachedIndexedApps = nil
        }
    }

    func restoreDefaultSearchScopes() {
        setSearchScopes(SearchScopes.defaults)
    }

    var indexedApplications: [SettingsAppItem] {
        if let cached = core.cachedIndexedApps {
            return cached
        }
        let items = core.appIndex.apps.map { entry in
            let alias = core.settingsStore.alias(for: "app." + entry.bundleID)
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
            core.cachedIndexedApps = items
        }
        return items
    }

    func appIcon(for path: String) -> NSImage? {
        core.iconCache.icon(forBundlePath: path)
    }

    func setAppAlias(_ alias: String?, for bundleID: String) {
        core.settingsStore.setAlias(alias, for: "app." + bundleID)
        core.cachedIndexedApps = nil
    }

    // MARK: - 启动器：系统操作

    var systemActions: [SettingsSystemActionItem] {
        SystemAction.allCases.map { action in
            let alias = core.settingsStore.alias(for: "system." + action.rawValue)
            let commandID = CommandID.systemAction(action.rawValue)
            return SettingsSystemActionItem(
                id: action.rawValue,
                title: action.title,
                description: action.description,
                icon: action.icon,
                alias: alias,
                isEnabled: core.settingsStore.isCommandEnabled(commandID)
            )
        }
    }

    func setSystemActionAlias(_ alias: String?, for id: String) {
        core.settingsStore.setAlias(alias, for: "system." + id)
        core.rebuildCommandCatalog()
    }

    // MARK: - 启动器：Shell 与自定义命令

    var isRunShellFallbackEnabled: Bool {
        core.settingsStore.isRunShellFallbackEnabled
    }

    func setRunShellFallbackEnabled(_ enabled: Bool) {
        core.settingsStore.setRunShellFallbackEnabled(enabled)
    }

    var customCommands: [SettingsCustomCommandItem] {
        if let cached = core.cachedCustomCommands {
            return cached
        }
        let list = core.loadCustomCommands()
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
        core.cachedCustomCommands = items
        return items
    }

    func addCustomCommand(
        name: String, command: String, workingDirectory: String?, loadsShellEnvironment: Bool
    ) {
        var list = core.loadCustomCommands()
        let item = CustomCommand(
            name: name,
            command: command,
            isEnabled: true,
            loadsShellEnvironment: loadsShellEnvironment,
            workingDirectory: workingDirectory
        )
        list.append(item)
        core.saveCustomCommands(list)
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
        var list = core.loadCustomCommands()
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        list[index].name = name
        list[index].command = command
        list[index].isEnabled = isEnabled
        list[index].alias = alias
        list[index].workingDirectory = workingDirectory
        list[index].loadsShellEnvironment = loadsShellEnvironment
        core.saveCustomCommands(list)
    }

    func deleteCustomCommand(id: UUID) {
        var list = core.loadCustomCommands()
        list.removeAll { $0.id == id }
        core.saveCustomCommands(list)
        core.hotKeyService.setBinding(nil, for: CommandID.shell(id.uuidString), registerNow: false)
    }
}
