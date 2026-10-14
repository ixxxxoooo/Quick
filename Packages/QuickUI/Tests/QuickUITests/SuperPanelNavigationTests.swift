// SuperPanelNavigationTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickPlatform
import Testing

@testable import QuickUI

@Suite("超级面板键盘导航")
struct SuperPanelNavigationTests {

    // MARK: - 直达键

    @Test("键位表：数字 1–9 之后接字母 a–z")
    func keyLabels() {
        #expect(SuperPanelKeys.label(at: 0) == "1")
        #expect(SuperPanelKeys.label(at: 8) == "9")
        #expect(SuperPanelKeys.label(at: 9) == "A")
        #expect(SuperPanelKeys.label(at: 34) == "Z")
        #expect(SuperPanelKeys.label(at: 35) == nil)
        #expect(SuperPanelKeys.label(at: -1) == nil)
    }

    @Test("按键字符映射回序号，大小写等价，超出条目数不命中")
    func keyIndex() {
        #expect(SuperPanelKeys.index(forKey: "1", count: 3) == 0)
        #expect(SuperPanelKeys.index(forKey: "3", count: 3) == 2)
        #expect(SuperPanelKeys.index(forKey: "4", count: 3) == nil)
        #expect(SuperPanelKeys.index(forKey: "a", count: 12) == 9)
        #expect(SuperPanelKeys.index(forKey: "A", count: 12) == 9)
        #expect(SuperPanelKeys.index(forKey: "a", count: 9) == nil)
        #expect(SuperPanelKeys.index(forKey: "0", count: 12) == nil)
        #expect(SuperPanelKeys.index(forKey: "-", count: 12) == nil)
    }

    // MARK: - 列表移动

    @Test("列表上下移动到头后回绕")
    func listWraps() {
        #expect(SuperPanelListNavigator.move(from: 0, delta: 1, count: 3) == 1)
        #expect(SuperPanelListNavigator.move(from: 2, delta: 1, count: 3) == 0)
        #expect(SuperPanelListNavigator.move(from: 0, delta: -1, count: 3) == 2)
        #expect(SuperPanelListNavigator.move(from: 0, delta: 1, count: 0) == 0)
        // 越界的当前值先夹回区间
        #expect(SuperPanelListNavigator.move(from: 9, delta: 0, count: 3) == 2)
    }

    // MARK: - 工作台网格

    private func move(
        _ index: Int, _ direction: SuperPanelDockNavigator.Direction,
        tools: Int = 8, recents: Int = 3, columns: Int = 4
    ) -> Int? {
        SuperPanelDockNavigator.move(
            from: index, direction, toolCount: tools, recentCount: recents, columns: columns)
    }

    @Test("网格内左右移动，行首 ← 与行尾 → 走不动")
    func gridHorizontal() {
        #expect(move(1, .right) == 2)
        #expect(move(1, .left) == 0)
        #expect(move(0, .left) == nil)
        #expect(move(3, .right) == nil)
        #expect(move(4, .left) == nil)
        // 最后一行不满：行内最后一项不能再往右
        #expect(move(6, .right, tools: 7) == nil)
    }

    @Test("网格内上下移动，最上一行 ↑ 走不动")
    func gridVertical() {
        #expect(move(1, .down) == 5)
        #expect(move(5, .up) == 1)
        #expect(move(1, .up) == nil)
    }

    @Test("下一行不满时落到最后一个工具")
    func gridDownIntoShortRow() {
        // 7 个工具：第二行只有 4、5、6；从第 3 列往下没有正下方，落到 6
        #expect(move(3, .down, tools: 7) == 6)
    }

    @Test("从网格最后一行往下进入最近使用，再往上回到最后一个工具")
    func gridToRecents() {
        #expect(move(5, .down) == 8)
        #expect(move(8, .down) == 9)
        #expect(move(10, .down) == nil)
        #expect(move(9, .up) == 8)
        #expect(move(8, .up) == 7)
    }

    @Test("没有最近使用时，最后一行往下走不动")
    func gridNoRecents() {
        #expect(move(5, .down, recents: 0) == nil)
    }

    @Test("最近使用段不响应左右；空工作台与越界序号返回 nil")
    func recentsAndEdges() {
        #expect(move(9, .left) == nil)
        #expect(move(9, .right) == nil)
        #expect(move(0, .down, tools: 0, recents: 0) == nil)
        #expect(move(99, .down) == nil)
        #expect(move(0, .down, columns: 0) == nil)
    }

    @Test("只有最近使用（没有工具）时，第一项往上走不动")
    func recentsOnly() {
        #expect(move(0, .up, tools: 0, recents: 3) == nil)
        #expect(move(0, .down, tools: 0, recents: 3) == 1)
    }

    // MARK: - 动作整理

    @MainActor
    private func action(_ id: String) -> SuperPanelAction {
        SuperPanelAction(id: id, title: id, subtitle: "", icon: "circle", execute: {})
    }

    @MainActor
    @Test("动作整理：同 id 保留先出现的，兜底搜索沉底")
    func plannerDedupesAndSinksFallback() {
        let planned = SuperPanelActionPlanner.plan([
            action("a"), action(SuperPanelActionPlanner.fallbackID), action("b"), action("a"),
        ])
        #expect(planned.map(\.id) == ["a", "b", SuperPanelActionPlanner.fallbackID])
    }

    @MainActor
    @Test("动作整理：超出上限时裁掉普通项而保住兜底搜索")
    func plannerKeepsFallbackWhenTrimming() {
        let many = (0..<20).map { action("x\($0)") } + [action(SuperPanelActionPlanner.fallbackID)]
        let planned = SuperPanelActionPlanner.plan(many)
        #expect(planned.count == SuperPanelActionPlanner.maxVisible)
        #expect(planned.last?.id == SuperPanelActionPlanner.fallbackID)
        #expect(planned.first?.id == "x0")
    }

    @MainActor
    @Test("动作整理：上限不超过键位表，保证每一项都有直达键")
    func plannerFitsKeyTable() {
        #expect(SuperPanelActionPlanner.maxVisible <= SuperPanelKeys.labels.count)
    }

    // MARK: - 高度

    @Test("高度夹进区间；未知高度不动窗口")
    func heightPolicy() {
        #expect(SuperPanelHeightPolicy.resolve(contentHeight: 0, minHeight: 96, maxHeight: 620) == nil)
        #expect(SuperPanelHeightPolicy.resolve(contentHeight: 40, minHeight: 96, maxHeight: 620) == 96)
        #expect(SuperPanelHeightPolicy.resolve(contentHeight: 300, minHeight: 96, maxHeight: 620) == 300)
        #expect(SuperPanelHeightPolicy.resolve(contentHeight: 900, minHeight: 96, maxHeight: 620) == 620)
    }

    // MARK: - 阈值口径

    @Test("长按阈值的上下限与鼠标监听器是同一份常量")
    func thresholdBoundsMatchMonitor() {
        #expect(
            UInt64(SuperPanelPreferences.maxThresholdMs)
                == MouseTriggerMonitor.Configuration.maxThresholdMilliseconds)
        #expect(
            UInt64(SuperPanelPreferences.minThresholdMs)
                == MouseTriggerMonitor.Configuration.minThresholdMilliseconds)
        // 设置页能选到的最大值，监听器必须原样接受
        let top = UInt64(SuperPanelPreferences.clampedThreshold(.max))
        #expect(MouseTriggerMonitor.Configuration.clampedThreshold(top) == top)
    }
}

@MainActor
@Suite("超级面板状态容器")
struct SuperPanelModelNavigationTests {

    private func tool(_ id: String) -> SuperPanelQuickTool {
        SuperPanelQuickTool(id: id, title: id, icon: "circle", pluginID: id)
    }

    private func recent(_ id: String) -> SuperPanelRecentItem {
        SuperPanelRecentItem(id: id, title: id, icon: "circle", kind: .command)
    }

    private func makeModel(tools: Int, recents: Int, text: String = "") -> SuperPanelModel {
        let model = SuperPanelModel()
        model.apply(
            sourceText: text,
            previews: [],
            actions: [],
            recentItems: (0..<recents).map { recent("r\($0)") },
            latestClipboard: "",
            quickTools: (0..<tools).map { tool("t\($0)") },
            showRecents: true,
            showClipboard: false,
            appearance: SuperPanelAppearance(opacity: 1, material: .solid)
        )
        return model
    }

    @Test("工作台条目序号：工具在前、最近使用在后")
    func dockItemOrdering() {
        let model = makeModel(tools: 2, recents: 2)
        #expect(model.dockItemCount == 4)
        guard case .tool(let first)? = model.dockItem(at: 0), case .recent(let third)? = model.dockItem(at: 2)
        else {
            Issue.record("条目类型与序号不符")
            return
        }
        #expect(first.id == "t0")
        #expect(third.id == "r0")
        #expect(model.dockItem(at: 4) == nil)
    }

    @Test("关闭「最近使用」后，最近使用不参与序号")
    func hiddenRecentsExcluded() {
        let model = makeModel(tools: 2, recents: 2)
        model.showRecents = false
        #expect(model.dockItemCount == 2)
        #expect(model.dockItem(at: 2) == nil)
    }

    @Test("工作台：← 在行首回到上下文，没有上下文时被消费但不动")
    func leftAtRowStart() {
        let withContext = makeModel(tools: 8, recents: 0, text: "hello")
        #expect(withContext.activeTab == .context)
        withContext.select(.dock)
        #expect(withContext.moveHorizontal(-1))
        #expect(withContext.activeTab == .context)

        let noContext = makeModel(tools: 8, recents: 0)
        #expect(noContext.activeTab == .dock)
        #expect(noContext.moveHorizontal(-1))
        #expect(noContext.activeTab == .dock)
        #expect(noContext.selectedIndex == 0)
    }

    @Test("工作台：→ 在网格里右移，↓ 下移，↑ 在顶行不动但消费按键")
    func dockArrows() {
        let model = makeModel(tools: 8, recents: 2)
        #expect(model.moveHorizontal(1))
        #expect(model.selectedIndex == 1)
        #expect(model.moveSelection(1))
        #expect(model.selectedIndex == 5)
        #expect(model.moveSelection(1))
        #expect(model.selectedIndex == 8)
        #expect(model.moveSelection(-1))
        #expect(model.selectedIndex == 7)
    }

    @Test("直达键按当前标签的条目数解析")
    func itemIndexForKey() {
        let model = makeModel(tools: 3, recents: 1)
        #expect(model.itemIndex(forKey: "4") == 3)
        #expect(model.itemIndex(forKey: "5") == nil)
        #expect(model.itemIndex(forKey: "a") == nil)
    }

    @Test("空动作列表不消费上下键")
    func emptyActionsDoNotConsume() {
        let model = makeModel(tools: 3, recents: 0, text: "hello")
        #expect(model.activeTab == .context)
        #expect(!model.moveSelection(1))
    }
}
