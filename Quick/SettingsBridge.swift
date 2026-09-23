// SettingsBridge.swift
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

// MARK: - 设置窗口的数据源

/// 设置界面的数据源，把 `QuickUI` 设置协议接到 `AppCore` 上的插件与系统能力
///
/// 设置界面在 `QuickUI`，而插件实例与系统能力（登录项、快捷键）只有组装层看得到，
/// 所以由这里实现协议、把两边接起来。
@MainActor
final class SettingsBridge: SettingsDataSource {

    unowned let core: AppCore

    private let log = QuickLog.app

    init(core: AppCore) {
        self.core = core
    }

    // MARK: - 通用设置

    var isLaunchAtLoginEnabled: Bool { core.launchAtLogin.isEnabled }

    func setLaunchAtLogin(_ enabled: Bool) {
        core.launchAtLogin.setEnabled(enabled)
    }

    var hotKeyDescription: String {
        core.hotKeyService.binding(for: CommandID.togglePalette)?.displayString
            ?? HotKeyService.defaultHotKeyDescription
    }

    var togglePaletteKeycaps: [String] {
        core.hotKeyService.binding(for: CommandID.togglePalette)?.keycaps ?? ["⌥", "Space"]
    }

    func shortcutKeycaps(keyCode: Int, carbonModifiers: Int) -> [String] {
        KeyShortcut(carbonKeyCode: keyCode, carbonModifiers: carbonModifiers).keycaps
    }

    func boundCommandBindings() -> [SettingsCommandBinding] {
        core.hotKeyService.boundCommandIDs().compactMap { commandID in
            guard commandID != CommandID.togglePalette else { return nil }
            // 超级面板的快捷键在它自己的设置页里改，不在快捷键页重复出现
            guard commandID != CommandID.superPanel else { return nil }
            guard core.hotKeyService.binding(for: commandID) != nil else { return nil }
            return describe(commandID: commandID)
        }
    }

    func resolveKeyword(_ keyword: String) -> SettingsCommandBinding? {
        var descriptors: [CommandDescriptor] = []
        for plugin in core.plugins where plugin.isEnabled {
            descriptors.append(contentsOf: type(of: plugin).commands)
        }
        for cmd in core.loadCustomCommands() where cmd.isEnabled {
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
        let apps = core.appIndex.apps.filter {
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
        guard let shortcut = core.hotKeyService.binding(for: commandID) else {
            return "这条绑定已经没有快捷键。"
        }
        guard let target = resolveKeyword(keyword) else {
            return "没有唯一对上的关键字。写插件声明的唤醒词，或功能标题。"
        }
        guard target.id != commandID else { return nil }
        core.hotKeyService.setBinding(nil, for: commandID, registerNow: false)
        let registerNow = core.settingsStore.isCommandEnabled(target.id)
        let outcome = core.hotKeyService.setBinding(shortcut, for: target.id, registerNow: registerNow)
        if case .conflict = outcome {
            let restore = commandID == CommandID.togglePalette || core.settingsStore.isCommandEnabled(commandID)
            core.hotKeyService.setBinding(shortcut, for: commandID, registerNow: restore)
            return "这个组合键已经绑给别的命令，没有改动。"
        }
        return nil
    }

    func pluginCommands(_ pluginID: String) -> [SettingsCommandBinding] {
        if pluginID == LauncherPlugin.id {
            return core.loadCustomCommands().map { describe(commandID: CommandID.shell($0.id.uuidString)) }
        }
        guard let plugin = core.plugins.first(where: { type(of: $0).id == pluginID }) else { return [] }
        return type(of: plugin).commands.map { bindingRow(for: $0) }
    }

    /// 把命令 id 解析成设置行。应用和终端命令不在静态声明里，要单独认前缀
    private func describe(commandID: String) -> SettingsCommandBinding {
        if let command = core.plugins.lazy.compactMap({ plugin in
            type(of: plugin).commands.first { $0.id == commandID }
        }).first {
            return bindingRow(for: command)
        }
        if commandID.hasPrefix(CommandID.launchAppPrefix) {
            let bundleID = String(commandID.dropFirst(CommandID.launchAppPrefix.count))
            let name = core.appIndex.apps.first { $0.bundleID == bundleID }?.name ?? bundleID
            return SettingsCommandBinding(
                id: commandID,
                title: name,
                pluginName: LauncherPlugin.name,
                icon: "app",
                isInvocationEnabled: core.settingsStore.isCommandEnabled(commandID),
                keycaps: core.hotKeyService.binding(for: commandID)?.keycaps,
                keywords: [name]
            )
        }
        if commandID.hasPrefix(CommandID.shellPrefix) {
            let raw = String(commandID.dropFirst(CommandID.shellPrefix.count))
            let command = core.loadCustomCommands().first { $0.id.uuidString.lowercased() == raw }
            let name = command?.name ?? raw
            var words = [name]
            if let alias = command?.alias, !alias.isEmpty { words.append(alias) }
            return SettingsCommandBinding(
                id: commandID,
                title: name,
                pluginName: "终端命令",
                icon: "terminal",
                isInvocationEnabled: core.settingsStore.isCommandEnabled(commandID),
                keycaps: core.hotKeyService.binding(for: commandID)?.keycaps,
                keywords: words
            )
        }
        return SettingsCommandBinding(
            id: commandID,
            title: commandID,
            pluginName: "命令",
            icon: "command",
            isInvocationEnabled: core.settingsStore.isCommandEnabled(commandID),
            keycaps: core.hotKeyService.binding(for: commandID)?.keycaps,
            keywords: [commandID]
        )
    }

    func setCommandShortcut(keyCode: Int, carbonModifiers: Int, for commandID: String) -> Bool {
        let shortcut = KeyShortcut(carbonKeyCode: keyCode, carbonModifiers: carbonModifiers)
        let registerNow =
            commandID == CommandID.togglePalette
            || commandID == CommandID.superPanel
            || core.settingsStore.isCommandEnabled(commandID)
        let outcome = core.hotKeyService.setBinding(shortcut, for: commandID, registerNow: registerNow)
        if case .conflict = outcome { return false }
        return true
    }

    func clearCommandShortcut(for commandID: String) {
        if commandID == CommandID.togglePalette {
            let defaultShortcut = KeyShortcut(carbonKeyCode: kVK_Space, carbonModifiers: optionKey)
            core.hotKeyService.setBinding(defaultShortcut, for: commandID, registerNow: true)
            return
        }
        core.hotKeyService.setBinding(nil, for: commandID, registerNow: false)
    }

    func isCommandEnabled(_ commandID: String) -> Bool {
        if commandID == CommandID.togglePalette || commandID == CommandID.superPanel { return true }
        return core.settingsStore.isCommandEnabled(commandID)
    }

    func setCommandEnabled(_ commandID: String, enabled: Bool) {
        guard commandID != CommandID.togglePalette else { return }
        core.settingsStore.setCommandEnabled(commandID, enabled: enabled)
        core.rebuildCommandCatalog()
    }

    var searchSources: [SettingsSearchSource] {
        pluginEntries.map { plugin in
            SettingsSearchSource(
                id: plugin.id,
                title: plugin.name,
                subtitle: "关闭后，主面板不再搜索这个插件的命令和结果。",
                icon: plugin.icon,
                isEnabled: core.settingsStore.isSearchSourceEnabled(plugin.id)
            )
        }
    }

    func setSearchSourceEnabled(_ pluginID: String, enabled: Bool) {
        core.settingsStore.setSearchSourceEnabled(pluginID, enabled: enabled)
        core.rebuildCommandCatalog()
    }

    private func bindingRow(for command: CommandDescriptor) -> SettingsCommandBinding {
        SettingsCommandBinding(
            id: command.id,
            title: command.title,
            subtitle: command.subtitle,
            pluginName: command.pluginName,
            icon: command.icon,
            isInvocationEnabled: core.settingsStore.isCommandEnabled(command.id),
            keycaps: core.hotKeyService.binding(for: command.id)?.keycaps,
            keywords: command.keywords.isEmpty ? [command.title] : command.keywords
        )
    }

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

        guard let plugin = core.plugins.first(where: { type(of: $0).id == id }) else {
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
            let plugin = core.plugins.first(where: { type(of: $0).id == pluginID })
        else {
            return nil
        }
        return plugin.makeSettingsView()
    }

    // MARK: - 超级面板

    func makeSuperPanelSettingsView() -> AnyView {
        AnyView(SuperPanelSettingsView(dataSource: self))
    }

    var superPanelShortcutKeycaps: [String]? {
        core.hotKeyService.binding(for: CommandID.superPanel)?.keycaps
    }

    func setSuperPanelShortcut(keyCode: Int, carbonModifiers: Int) -> Bool {
        let shortcut = KeyShortcut(carbonKeyCode: keyCode, carbonModifiers: carbonModifiers)
        let outcome = core.hotKeyService.setBinding(shortcut, for: CommandID.superPanel, registerNow: true)
        if case .conflict = outcome { return false }
        return true
    }

    func clearSuperPanelShortcut() {
        core.hotKeyService.setBinding(nil, for: CommandID.superPanel, registerNow: false)
    }

    func clearRecentUsage() {
        core.usageHistory?.removeAll()
        log.notice("最近使用记录已清空")
    }

    // MARK: - AI 基座

    func makeAISettingsView() -> AnyView {
        AnyView(AISettingsPane(dataSource: self))
    }

    func testAIConnection() async -> SettingsAITestResult {
        do {
            let reply = try await AIService.testConnection()
            let snippet = reply.isEmpty ? "OK" : String(reply.prefix(40))
            log.notice("AI 连接测试成功")
            return SettingsAITestResult(isSuccess: true, message: "连接成功：\(snippet)")
        } catch {
            log.warning("AI 连接测试失败：\(error.localizedDescription, privacy: .public)")
            return SettingsAITestResult(
                isSuccess: false, message: error.localizedDescription)
        }
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
            let granted = core.permissionService.isAccessibilityGranted()
            return SettingsPermissionState(isGranted: granted, canRequest: !granted)

        case .screenCapture:
            let granted = core.permissionService.isScreenCaptureGranted()
            return SettingsPermissionState(isGranted: granted, canRequest: !granted)

        case .location:
            switch core.permissionService.locationStatus() {
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
            core.permissionService.requestAccessibility()
        case .screenCapture:
            core.permissionService.requestScreenCapture()
        case .location:
            // 定位的申请入口只有天气插件那一处（用户主动查看天气时），
            // 设置页只负责把状态显示出来、把人带到系统设置。
            core.permissionService.openLocationSettings()
        }
    }

    func openPermissionSettings(_ permission: SettingsPermission) {
        switch permission {
        case .accessibility:
            core.permissionService.openAccessibilitySettings()
        case .screenCapture:
            core.permissionService.openScreenCaptureSettings()
        case .location:
            core.permissionService.openLocationSettings()
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
