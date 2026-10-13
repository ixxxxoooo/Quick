// ActionMenuTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import Testing

@testable import QuickUI

@Suite("⌘K 操作菜单")
@MainActor
struct ActionMenuTests {

    private func item(iconType: SearchableItem.IconType = .symbol) -> SearchableItem {
        SearchableItem(
            id: "x", pluginID: "p", title: "Safari", icon: "star", iconType: iconType, action: {})
    }

    private func action(_ id: String, _ onRun: @escaping @MainActor () -> Void = {}) -> ResultAction {
        ResultAction(id: id, title: id, icon: "star", perform: onRun)
    }

    // MARK: - 操作目录

    @Test("应用结果有执行 / 访达显示 / 复制路径 / 复制名称")
    func appItemKinds() {
        let kinds = ResultActionCatalog.kinds(for: item(iconType: .appIcon("/Applications/Safari.app")))
        #expect(
            kinds == [
                .run, .reveal(path: "/Applications/Safari.app"),
                .copyPath(path: "/Applications/Safari.app"), .copyTitle,
            ])
    }

    @Test("普通结果只有执行与复制名称")
    func plainItemKinds() {
        #expect(ResultActionCatalog.kinds(for: item()) == [.run, .copyTitle])
    }

    @Test("空路径的应用图标不给访达操作")
    func emptyPathHasNoReveal() {
        #expect(ResultActionCatalog.kinds(for: item(iconType: .appIcon(""))) == [.run, .copyTitle])
    }

    @Test("执行永远是第一项")
    func runIsFirst() {
        let actions = ResultActionCatalog.makeActions(for: item()) {}
        #expect(actions.first?.id == "run")
    }

    // MARK: - 状态

    @Test("没有操作时不打开")
    func emptyDoesNotOpen() {
        let menu = ActionMenuState()
        menu.open(actions: [])
        #expect(!menu.isOpen)
    }

    @Test("上下移动夹在边界内")
    func moveClamps() {
        let menu = ActionMenuState()
        menu.open(actions: [action("a"), action("b"), action("c")])
        menu.move(-1)
        #expect(menu.index == 0)
        menu.move(5)
        #expect(menu.index == 2)
    }

    @Test("回车执行选中项并关闭")
    func runSelectedClosesAndRuns() {
        let menu = ActionMenuState()
        var ran: [String] = []
        menu.open(actions: [action("a") { ran.append("a") }, action("b") { ran.append("b") }])
        menu.move(1)
        #expect(menu.runSelected())
        #expect(ran == ["b"])
        #expect(!menu.isOpen)
    }

    @Test("关闭状态下 runSelected 不执行")
    func runWhenClosed() {
        let menu = ActionMenuState()
        #expect(!menu.runSelected())
    }

    @Test("悬停选中越界被忽略")
    func selectOutOfRange() {
        let menu = ActionMenuState()
        menu.open(actions: [action("a")])
        menu.select(3)
        #expect(menu.index == 0)
    }

    // MARK: - 协调器路由

    @Test("菜单打开时上下键与回车属于菜单，Esc 只关菜单")
    func coordinatorRouting() {
        let coordinator = PaletteCoordinator()
        var ran = false
        coordinator.actionMenu.open(actions: [action("a"), action("b") { ran = true }])
        #expect(coordinator.routeMove(1))
        #expect(coordinator.actionMenu.index == 1)
        #expect(coordinator.routeCancel())
        #expect(!coordinator.actionMenu.isOpen)

        coordinator.actionMenu.open(actions: [action("a"), action("b") { ran = true }])
        _ = coordinator.routeMove(1)
        #expect(coordinator.routeSubmit())
        #expect(ran)
    }

    @Test("没有选中结果时 ⌘K 不消费")
    func toggleWithoutSelection() {
        let coordinator = PaletteCoordinator()
        #expect(!coordinator.toggleActionMenu())
    }

    @Test("菜单打开时导航键被吞掉，不动背后的列表")
    func navigationSwallowedWhileOpen() {
        let coordinator = PaletteCoordinator()
        coordinator.selection.update(count: 5) { _ in }
        coordinator.actionMenu.open(actions: [action("a")])
        #expect(coordinator.routeNavigation(.page(1)))
        #expect(coordinator.selection.index == 0)
    }
}
