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

    let log = QuickLog.app

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

    func fuzzyMatchCommands(_ keyword: String) -> [SettingsCommandBinding] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var results: [(binding: SettingsCommandBinding, score: Double)] = []

        for plugin in core.plugins where plugin.isEnabled {
            for command in type(of: plugin).commands {
                let keywords = command.keywords.isEmpty ? [command.title] : command.keywords
                let best = ([command.title] + keywords).compactMap { word -> Double? in
                    let score = word.fuzzyScore(trimmed)
                    return score > 0 ? score : nil
                }.max() ?? 0

                if best > 0 {
                    results.append((binding: bindingRow(for: command), score: best))
                }
            }
        }

        for cmd in core.loadCustomCommands() where cmd.isEnabled {
            let words = [cmd.name] + (cmd.alias.map { [$0] } ?? [])
            let best = words.compactMap { word -> Double? in
                let score = word.fuzzyScore(trimmed)
                return score > 0 ? score : nil
            }.max() ?? 0

            if best > 0 {
                let desc = CommandDescriptor(
                    id: CommandID.shell(cmd.id.uuidString),
                    pluginID: LauncherPlugin.id,
                    pluginName: "终端命令",
                    title: cmd.name,
                    keywords: words,
                    icon: "terminal"
                )
                results.append((binding: bindingRow(for: desc), score: best))
            }
        }

        // 按应用名搜索
        for app in core.appIndex.apps {
            let score = app.name.fuzzyScore(trimmed)
            if score > 0 {
                let binding = SettingsCommandBinding(
                    id: CommandID.launchApp(app.bundleID),
                    title: app.name,
                    pluginName: LauncherPlugin.name,
                    icon: "app",
                    isInvocationEnabled: true,
                    keycaps: nil,
                    keywords: [app.name]
                )
                results.append((binding: binding, score: score))
            }
        }

        // 按 (pluginName, title) 去重；分数相同时优先取具体功能命令（而非 plugin.open.*）
        let sorted = results.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            let lhsIsOpen = CommandID.openedPluginID(in: $0.binding.id) != nil
            let rhsIsOpen = CommandID.openedPluginID(in: $1.binding.id) != nil
            if lhsIsOpen != rhsIsOpen { return !lhsIsOpen }
            return false
        }
        var seenKeys = Set<String>()
        var deduped: [SettingsCommandBinding] = []
        for item in sorted {
            let key = "\(item.binding.pluginName.lowercased()):\(item.binding.title.lowercased())"
            if seenKeys.insert(key).inserted {
                deduped.append(item.binding)
            }
        }
        return Array(deduped.prefix(8))
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
        guard let plugin = core.pluginsByID[pluginID] else { return [] }
        return type(of: plugin).commands.map { bindingRow(for: $0) }
    }

    /// 把命令 id 解析成设置行。应用和终端命令不在静态声明里，要单独认前缀
    func describe(commandID: String) -> SettingsCommandBinding {
        if let ownerID = core.pluginID(owningCommand: commandID),
            let command = core.commandDescriptor(of: commandID, in: ownerID)
        {
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
        let plugins = pluginEntries.map { plugin in
            SettingsSearchSource(
                id: plugin.id,
                title: plugin.name,
                // 统一说明在页脚；逐行重复同一句话只会拉长列表
                subtitle: "",
                icon: plugin.icon,
                isEnabled: core.settingsStore.isSearchSourceEnabled(plugin.id)
            )
        }
        // 文件搜索是宿主自己的来源，不在插件列表里，但同样允许单独关闭
        let files = SettingsSearchSource(
            id: FileSearchSource.sourceIdentifier,
            title: "文件搜索",
            subtitle: "关闭后，输入 f / file / 文件 前缀不再查找本机文件。",
            icon: "folder",
            isEnabled: core.settingsStore.isSearchSourceEnabled(FileSearchSource.sourceIdentifier)
        )
        return plugins + [files]
    }

    func setSearchSourceEnabled(_ pluginID: String, enabled: Bool) {
        core.settingsStore.setSearchSourceEnabled(pluginID, enabled: enabled)
        core.rebuildCommandCatalog()
    }

    func bindingRow(for command: CommandDescriptor) -> SettingsCommandBinding {
        var seen = Set<String>()
        var dedupedKeywords: [String] = []
        let rawKeywords = command.keywords.isEmpty ? [command.title] : command.keywords
        for word in rawKeywords {
            let key = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !key.isEmpty && seen.insert(key).inserted {
                dedupedKeywords.append(word)
            }
        }
        return SettingsCommandBinding(
            id: command.id,
            title: command.title,
            subtitle: command.subtitle,
            pluginName: command.pluginName,
            icon: command.icon,
            isInvocationEnabled: core.settingsStore.isCommandEnabled(command.id),
            keycaps: core.hotKeyService.binding(for: command.id)?.keycaps,
            keywords: dedupedKeywords
        )
    }
}
