// MainMenuTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Testing

@testable import QuickUI

/// 主菜单
///
/// 这一组测的不是「菜单长什么样」——accessory 模式下用户根本看不见菜单栏 ——
/// 而是**⌘A / ⌘C / ⌘V 这类编辑快捷键有没有人处理**。
///
/// 它们不是文本框自己实现的：它们是主菜单里 Edit 菜单项的 key equivalent，
/// 由 AppKit 沿响应链把 `selectAll:` / `copy:` / `paste:` 派发给第一响应者。
/// 没有主菜单，这些组合键完全没人处理，表现就是「在任何输入框里全选、复制、粘贴都没反应」。
///
/// 所以这里断言三件事：**快捷键在不在**、**选择器对不对**、**target 是不是 nil**。
/// 第三件最容易被写坏：target 一旦写死，事件就送不到当前正在编辑的文本框。
///
/// 至于「按下去真的选中了」那一步，是 AppKit 自己的响应链行为，需要真实的 key window
/// 与事件循环；无头测试进程里造不出来（建窗口 + 造 NSEvent 会让测试宿主段错误），
/// 所以不在这里假装验证它。
@Suite("主菜单与编辑快捷键")
@MainActor
struct MainMenuTests {

    /// 编辑菜单里必须有的快捷键 → 选择器
    private static let requiredShortcuts:
        [(key: String, selector: String, modifiers: NSEvent.ModifierFlags)] = [
            ("a", "selectAll:", [.command]),
            ("c", "copy:", [.command]),
            ("v", "paste:", [.command]),
            ("x", "cut:", [.command]),
            ("z", "undo:", [.command])
        ]

    @Test("编辑菜单包含全部标准快捷键，且选择器正确")
    func editMenuHasStandardShortcuts() {
        let menu = MainMenu.makeEditMenuItem().submenu
        #expect(menu != nil)

        for (key, selector, modifiers) in Self.requiredShortcuts {
            let item = menu?.items.first {
                $0.keyEquivalent == key && $0.keyEquivalentModifierMask == modifiers
            }
            #expect(item != nil, "缺少 ⌘\(key.uppercased())")
            #expect(
                item?.action == Selector(selector),
                "⌘\(key.uppercased()) 应派发 \(selector)，实际是 \(String(describing: item?.action))")
        }
    }

    @Test("重做是 ⇧⌘Z，与撤销区分开")
    func redoUsesShiftCommandZ() {
        let items = MainMenu.makeEditMenuItem().submenu?.items ?? []
        let redo = items.first { $0.action == Selector(("redo:")) }
        #expect(redo != nil)
        #expect(redo?.keyEquivalent == "z")
        #expect(redo?.keyEquivalentModifierMask == [.command, .shift])
    }

    @Test("编辑菜单项没有固定 target —— 必须沿响应链走")
    func editItemsTargetNil() {
        let editItems = MainMenu.makeEditMenuItem().submenu?.items ?? []
        let actionable = editItems.filter { $0.action != nil }
        #expect(!actionable.isEmpty)
        #expect(
            actionable.allSatisfy { $0.target == nil },
            "写死 target 会让 ⌘C 只作用在固定对象上，而不是当前编辑的文本框")
    }

    @Test("安装后主菜单就位：应用 / 编辑 / 窗口三个菜单")
    func installsMainMenu() {
        MainMenu.install()

        let mainMenu = NSApplication.shared.mainMenu
        #expect(mainMenu != nil)
        #expect(mainMenu?.items.count == 3)
        // 第一项是应用菜单，里面要有退出
        #expect(mainMenu?.items.first?.submenu?.items.contains { $0.keyEquivalent == "q" } == true)
        // 第二项是编辑菜单，⌘A 就在这里
        #expect(
            mainMenu?.items[1].submenu?.items.contains {
                $0.keyEquivalent == "a" && $0.action == #selector(NSText.selectAll(_:))
            } == true)
    }

    @Test("重复安装是安全的空操作")
    func installIsIdempotent() {
        MainMenu.install()
        let first = NSApplication.shared.mainMenu
        MainMenu.install()
        #expect(NSApplication.shared.mainMenu === first)
    }

    @Test("窗口菜单不含 ⌘W")
    func windowMenuDoesNotStealCommandW() {
        // 面板自己把 ⌘W 当「返回上一层 / 关闭面板」。菜单的 key equivalent 会**先于**
        // 窗口的 sendEvent 被处理，所以放进菜单，面板就再也收不到它了。
        MainMenu.install()
        let windowMenu = NSApplication.shared.windowsMenu
        #expect(windowMenu != nil)
        #expect(
            windowMenu?.items.contains { $0.keyEquivalent == "w" } == false,
            "⌘W 必须留给面板自己处理")
    }
}
