// AppCore+SuperPanel.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Carbon.HIToolbox
import PluginTranslator
import Foundation
import QuickCore
import QuickPlatform
import QuickUI
import SwiftUI

/// 超级面板：系统能力注入与鼠标触发
///
/// 从 `AppCore.swift` 按职责拆出的扩展：状态仍然只属于 `AppCore`（唯一所有者），
/// 这里只放行为。拆文件是为了让每个文件能一次读完，不是为了拆出新的所有者。
extension AppCore {

    // MARK: - 超级面板

    /// 接线超级面板：系统能力注入 + 鼠标唤出 + 默认快捷键
    ///
    /// 超级面板不认识 `QuickPlatform`（依赖方向），所以抓选区、合成粘贴、解析最近使用
    /// 都由这里注入进去。鼠标监听也归宿主：它是一项系统能力，不该跟着某个插件生死。
    func wireSuperPanel() {
        let controller = superPanelController
        controller.captureSelection = { await SelectionCapture.captureText() }
        controller.canPaste = { [weak self] in self?.pasteService.canSynthesize ?? false }
        controller.paste = { [weak self] in _ = self?.pasteService.paste() }
        controller.recentItems = { [weak self] in self?.resolveRecentItems() ?? [] }
        controller.openSettings = { [weak self] in
            self?.settingsWindowController.show(tab: .superPanel)
        }
        controller.translate = { [weak self] text in
            guard let self, let translator = self.plugin(withID: TranslatorPlugin.id) as? TranslatorPlugin else {
                return nil
            }
            return await translator.translateOrLookup(text)
        }

        mouseTriggerMonitor.onTrigger = { [weak self] kind in
            Task { @MainActor in
                QuickLog.app.notice(
                    "鼠标触发超级面板：\(String(describing: kind), privacy: .public)")
                self?.paletteCoordinator.hide(restoreFocus: false)
                self?.superPanelController.toggle()
            }
        }
        syncMouseTriggerConfiguration()

        if superPanelDefaultsObserver == nil {
            superPanelDefaultsObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: UserDefaults.standard,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.syncMouseTriggerConfiguration()
                }
            }
        }

        // 默认 ⌥C（对齐 Fasty）。用户清空后不再自动补回。
        if hotKeyService.binding(for: CommandID.superPanel) == nil {
            let shortcut = KeyShortcut(carbonKeyCode: kVK_ANSI_C, carbonModifiers: optionKey)
            _ = hotKeyService.setBinding(shortcut, for: CommandID.superPanel, registerNow: true)
        }
        controller.prewarm()
        log.notice("超级面板已接线")
    }

    /// 把鼠标偏好同步到监听器
    func syncMouseTriggerConfiguration() {
        let config = SuperPanelPreferences.mouseConfiguration()
        mouseTriggerMonitor.apply(
            MouseTriggerMonitor.Configuration(
                rightLongPressEnabled: config.rightLongPressEnabled,
                middleClickEnabled: config.middleClickEnabled,
                thresholdMilliseconds: UInt64(config.thresholdMilliseconds)
            )
        )
    }

    /// 把「最近使用」的条目 id 解析成可展示的行（最多 4 条，对齐 Fasty）
    func resolveRecentItems() -> [SuperPanelRecentItem] {
        guard let ids = usageHistory?.recentItemIDs(limit: 12) else { return [] }
        var items: [SuperPanelRecentItem] = []
        for id in ids {
            if let item = resolveRecentItem(id) {
                items.append(item)
            }
            if items.count >= 4 { break }
        }
        return items
    }

    /// 单个 id 的解析：应用、插件入口、插件命令
    func resolveRecentItem(_ id: String) -> SuperPanelRecentItem? {
        if id.hasPrefix(CommandID.launchAppPrefix) {
            let bundleID = String(id.dropFirst(CommandID.launchAppPrefix.count))
            guard let app = appIndex.apps.first(where: { $0.bundleID == bundleID }) else { return nil }
            return SuperPanelRecentItem(
                id: id, title: app.name, subtitle: app.path, icon: "app",
                kind: .app, launchPath: app.path)
        }
        // 文件搜索结果：条目 id 里编码了路径，文件还在才算有效「最近」
        if let path = FileSearchQuery.path(fromItemID: id) {
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            let url = URL(fileURLWithPath: path)
            return SuperPanelRecentItem(
                id: id, title: url.lastPathComponent, subtitle: path,
                icon: FileIconMapper.icon(forFileName: url.lastPathComponent),
                kind: .file, launchPath: path)
        }
        if let pluginID = CommandID.openedPluginID(in: id),
            let plugin = pluginsByID[pluginID]
        {
            return SuperPanelRecentItem(
                id: id, title: type(of: plugin).name, icon: type(of: plugin).icon,
                kind: .plugin, pluginID: pluginID)
        }
        // 功能命令：走命令归属表，与执行路径用的是同一份索引
        if let ownerID = commandOwners[id], let plugin = pluginsByID[ownerID] {
            return SuperPanelRecentItem(
                id: id, title: type(of: plugin).name, icon: type(of: plugin).icon,
                kind: .plugin, pluginID: ownerID)
        }
        return nil
    }
}
