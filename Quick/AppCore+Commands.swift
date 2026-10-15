// AppCore+Commands.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Carbon.HIToolbox
import PluginAI
import Foundation
import QuickCore
import QuickPlatform
import QuickUI
import SwiftUI

/// 命令调度：自定义命令存储、快捷键恢复、命令目录
///
/// 从 `AppCore.swift` 按职责拆出的扩展：状态仍然只属于 `AppCore`（唯一所有者），
/// 这里只放行为。拆文件是为了让每个文件能一次读完，不是为了拆出新的所有者。
extension AppCore {

    // MARK: - 自定义命令存储辅助

    func loadCustomCommands() -> [CustomCommand] {
        guard let data = settingsStore.customCommandsData else { return [] }
        do {
            return try JSONDecoder().decode([CustomCommand].self, from: data)
        } catch {
            // 解码失败时返回空数组，下一次保存会把坏数据覆盖掉 —— 所以必须留下证据
            log.error("自定义命令数据无法解析，按空列表处理：\(error)")
            return []
        }
    }

    /// 保存自定义命令
    ///
    /// - Returns: 是否写入成功；失败时已记日志并弹 HUD，调用方不必再提示
    @discardableResult
    func saveCustomCommands(_ commands: [CustomCommand]) -> Bool {
        do {
            let data = try JSONEncoder().encode(commands)
            settingsStore.setCustomCommandsData(data)
            cachedCustomCommands = nil
            return true
        } catch {
            log.error("自定义命令编码失败，未保存：\(error)")
            hudController.show(message: "自定义命令保存失败", tone: .danger)
            return false
        }
    }

    // MARK: - 快捷键恢复

    /// 执行一条命令。热键和搜索共用这一条路径
    func invoke(commandID: String) {
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
        // plugin.open.* 已在上面处理，这里兜住 clipboard.clear 这类「只会 Navigate 回本插件」的热键。
        // AI Provider（ai.<id>）与聚合窗口（ai.mergedWindow）除外：它们开的是窗口，切换语义在 perform 的 toggle 里；
        // 若在这里按「面板正显示 ai」直接 hide，快捷键在门户开着时只会关面板、打不开窗口。
        let ownerPluginID = type(of: plugin).id
        let isAIWindowCommand =
            AIPlugin.providerID(fromCommandID: commandID) != nil || commandID == AIPlugin.mergedWindowCommandID
        if paletteCoordinator.isVisible,
            paletteCoordinator.activePluginID == ownerPluginID,
            !isAIWindowCommand
        {
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
    func plugin(forCommand commandID: String) -> (any QuickPlugin)? {
        if let ownerID = commandOwners[commandID] {
            return pluginsByID[ownerID]
        }
        // 动态命令（如 `launcher.app.*`、`launcher.shell.*`）不在静态 `commands` 里，
        // 没有映射条目，只能按插件 id 前缀回退。前缀匹配天然只能遍历，但这类命令
        // 只在执行时问一次，不在按键热路径上。
        // 命令 id 的约定是 `<插件 id>.<后缀>`，插件 id 本身不含「.」，所以取第一段直接查字典，
        // 不必再扫描全部插件
        let prefix = commandID.prefix { $0 != "." }
        return pluginsByID[String(prefix)]
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
