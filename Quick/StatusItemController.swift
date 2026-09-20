// StatusItemController.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore

/// 菜单栏状态项控制器
///
/// 使用 AppKit `NSStatusItem` 替代 SwiftUI `MenuBarExtra`，
/// 避免与面板窗口产生主菜单死循环。
@MainActor
final class StatusItemController {

    private var statusItem: NSStatusItem?

    private let log = QuickLog.app

    /// 安装菜单栏图标与菜单
    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "macwindow.on.rectangle",
                accessibilityDescription: "Quick"
            )
            button.toolTip = "Quick"
        }

        let menu = NSMenu()
        menu.addItem(makeItem(title: "显示 Quick", action: #selector(showPalette)))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(makeItem(title: "重启 Quick", action: #selector(restart)))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "退出 Quick", action: #selector(quit), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
    }

    /// 移除菜单栏图标
    func remove() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    /// 造一个指向自己的菜单项
    ///
    /// 逐个建而不是循环补 `target`：分隔线不该被赋 target，
    /// 而漏掉一个 target 会让那一项在菜单里变灰不可点。
    private func makeItem(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    // MARK: - 动作

    @objc private func showPalette() {
        AppCore.shared.paletteCoordinator.toggle()
    }

    @objc private func openSettings() {
        AppCore.shared.paletteCoordinator.hide(restoreFocus: false)
        AppCore.shared.settingsWindowController.show()
    }

    /// 重启应用
    ///
    /// 必须**先退出再启动**：新实例起来时旧实例还占着 ⌥Space，新实例注册会失败，
    /// 结果就是重启完快捷键失灵。
    ///
    /// AppKit 没有「等我退出之后再启动我」的 API，所以起一个脱离的 shell 等本进程
    /// 消失后再重新打开。这是少数几个非用 shell 不可的地方。
    @objc private func restart() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let bundlePath = Bundle.main.bundlePath

        let waiter = Process()
        waiter.executableURL = URL(fileURLWithPath: "/bin/sh")
        // 用位置参数传值，不做字符串拼接：路径里有空格或引号也不会出错。
        waiter.arguments = [
            "-c",
            "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; exec /usr/bin/open -n \"$2\"",
            "quick-restart",
            String(pid),
            bundlePath
        ]

        do {
            try waiter.run()
            log.notice("正在重启：等待进程 \(pid, privacy: .public) 退出后重新打开")
        } catch {
            // 等待进程起不来时退化成「先开新的再退」：会和旧实例短暂重叠，
            // 但总比点了重启却什么都没发生要好。
            log.error("重启的等待进程启动失败，改为直接重新打开：\(error.localizedDescription, privacy: .public)")
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) {
                _, error in
                if let error {
                    QuickLog.app.error("重新打开失败：\(error.localizedDescription, privacy: .public)")
                }
                Task { @MainActor in NSApp.terminate(nil) }
            }
            return
        }

        NSApp.terminate(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
