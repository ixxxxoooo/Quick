// MainMenu.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore

/// 应用主菜单
///
/// ## 为什么一个 accessory 应用也需要主菜单
///
/// Quick 没有 Dock 图标，菜单栏也不显示自己的菜单（`LSUIElement`），所以这个菜单
/// **用户看不见** —— 但它必须存在，因为 **⌘A / ⌘C / ⌘V / ⌘X / ⌘Z 不是文本框自己实现的**：
/// 它们是主菜单里 Edit 菜单项的 key equivalent，由 AppKit 通过响应链把
/// `selectAll:` / `copy:` / `paste:` 派发给当前第一响应者。
///
/// 没有主菜单，这些组合键就完全没人处理 —— 表现是「全选、复制、粘贴在任何输入框里都没反应」，
/// 而且看起来像输入框的 bug。这个项目真的这样运行过一段时间。
///
/// 与 `QuickApp` 注释里提到的 `makeMainMenu` 死循环无关：那是 SwiftUI 的 `App` +
/// `MenuBarExtra` 组合在 macOS 26 上的问题；这里是纯 AppKit，手工建一次菜单。
///
/// 菜单项一律 `target = nil`：让它们沿响应链找到当前第一响应者（也就是正在编辑的文本框），
/// 而不是被菜单自己吃掉。
@MainActor
public enum MainMenu {

    /// 是否已经装过
    private static var isInstalled = false

    /// 安装主菜单（应用启动时调用一次；重复调用是安全的空操作）
    public static func install() {
        guard !isInstalled else { return }
        isInstalled = true
        let mainMenu = NSMenu()

        mainMenu.addItem(makeAppMenuItem())
        mainMenu.addItem(makeEditMenuItem())
        mainMenu.addItem(makeWindowMenuItem())

        NSApplication.shared.mainMenu = mainMenu

        // 留一条日志：菜单栏在 accessory 模式下不可见，出问题时「菜单到底装上没有」
        // 是第一个要回答的问题，而这件事从界面上看不出来
        let editItems = mainMenu.item(at: 1)?.submenu?.items.map(\.title) ?? []
        QuickLog.app.notice(
            "主菜单已安装：\(mainMenu.items.count, privacy: .public) 个菜单，编辑菜单 \(editItems.joined(separator: "/"), privacy: .public)"
        )
    }

    // MARK: - 应用菜单

    private static func makeAppMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: appName)

        menu.addItem(
            withTitle: "关于 \(appName)",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        menu.addItem(.separator())

        menu.addItem(
            withTitle: "隐藏 \(appName)",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h")

        let hideOthers = menu.addItem(
            withTitle: "隐藏其他",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]

        menu.addItem(
            withTitle: "显示全部",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: "")
        menu.addItem(.separator())

        menu.addItem(
            withTitle: "退出 \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")

        item.submenu = menu
        return item
    }

    // MARK: - 编辑菜单

    /// 编辑菜单：标准编辑快捷键全靠它
    static func makeEditMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "编辑")

        // `undo:` / `redo:` 是 NSTextView 与 NSUndoManager 约定的选择器，
        // 不是 `UndoManager.undo`（没有冒号），所以只能按字符串构造。
        menu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")

        let redo = menu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]

        menu.addItem(.separator())

        menu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")

        let pastePlain = menu.addItem(
            withTitle: "粘贴并匹配样式",
            action: #selector(NSTextView.pasteAsPlainText(_:)),
            keyEquivalent: "v")
        pastePlain.keyEquivalentModifierMask = [.command, .shift, .option]

        menu.addItem(.separator())
        menu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        item.submenu = menu
        return item
    }

    // MARK: - 窗口菜单

    private static func makeWindowMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "窗口")

        // ⌘M 最小化；**刻意不放 ⌘W**：面板自己把 ⌘W 当作「返回上一层 / 关闭面板」，
        // 放进菜单会被菜单先吃掉，面板就再也收不到它了。
        menu.addItem(
            withTitle: "最小化",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m")
        menu.addItem(
            withTitle: "缩放",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: "")

        item.submenu = menu
        NSApplication.shared.windowsMenu = menu
        return item
    }

    /// 显示名取自 bundle（Debug 是「Quick Dev」）
    private static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Quick"
    }
}
