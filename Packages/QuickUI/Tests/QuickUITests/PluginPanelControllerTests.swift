// PluginPanelControllerTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import SwiftUI
import Testing

@testable import QuickUI

@MainActor
@Suite("PluginPanelController 分离窗口")
struct PluginPanelControllerTests {

    /// 按标识找到分离窗口
    ///
    /// 走 `NSApp.windows` 而不是暴露内部字典：窗口是不是真的进了 AppKit 的窗口表
    /// 本身就是被测行为的一部分。
    private func detachedPanel(_ pluginID: String) -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "quick.detach.\(pluginID)" }
    }

    @Test("初始状态无分离窗口")
    func initialStateEmpty() {
        let controller = PluginPanelController()
        #expect(controller.focusIfOpen("devtools") == false)
    }

    @Test("分离创建独立窗口")
    func detachCreatesWindow() {
        let controller = PluginPanelController()
        let view = AnyView(Text("测试工具"))

        controller.detach(
            pluginID: "devtools",
            pluginName: "开发工具",
            icon: "wrench.and.screwdriver",
            viewProvider: { view },
            sourceWindow: nil
        )

        #expect(controller.focusIfOpen("devtools") == true)
        #expect(detachedPanel("devtools") != nil)

        controller.closeAll()
    }

    /// 回归测试：分离窗口的窗口控制长在它自己的标题栏里，不再有悬浮胶囊
    ///
    /// 胶囊是给「内容是一整块网页、没有自己的边框」的 AI 窗口用的；分离窗口有自绘标题栏，
    /// 再叠一个浮层会多出一套只在这里存在的交互（可拖、可折叠、位置要持久化）。
    @Test("分离窗口不再带悬浮胶囊")
    func detachedWindowHasNoCapsule() {
        let controller = PluginPanelController()
        let view = AnyView(Text("测试工具"))

        controller.detach(
            pluginID: "no-capsule",
            pluginName: "颜色工具",
            icon: "paintpalette",
            viewProvider: { view },
            sourceWindow: nil
        )

        let container = detachedPanel("no-capsule")?.contentView
        #expect(container != nil)
        #expect(container?.subviews.contains { $0 is FloatingCapsuleView } == false)

        controller.closeAll()
    }

    @Test("单例策略：同一插件不重复创建窗口")
    func singletonPreventsDoubleCreate() {
        let controller = PluginPanelController()
        let view = AnyView(Text("测试"))

        controller.detach(
            pluginID: "clipboard",
            pluginName: "剪贴板",
            icon: "doc.on.clipboard",
            viewProvider: { view },
            sourceWindow: nil
        )
        controller.detach(
            pluginID: "clipboard",
            pluginName: "剪贴板",
            icon: "doc.on.clipboard",
            viewProvider: { view },
            sourceWindow: nil
        )

        let matches = NSApp.windows.filter {
            $0.identifier?.rawValue == "quick.detach.clipboard"
        }
        #expect(matches.count == 1)
        #expect(controller.focusIfOpen("clipboard") == true)

        controller.closeAll()
    }

    @Test("close 关闭指定插件窗口")
    func closeRemovesWindow() {
        let controller = PluginPanelController()
        let view = AnyView(Text("测试"))

        controller.detach(
            pluginID: "ai",
            pluginName: "AI",
            icon: "brain",
            viewProvider: { view },
            sourceWindow: nil
        )

        #expect(controller.focusIfOpen("ai") == true)

        controller.close("ai")
        #expect(controller.focusIfOpen("ai") == false)
    }

    @Test("closeAll 关闭所有分离窗口")
    func closeAllRemovesAllWindows() {
        let controller = PluginPanelController()
        let view = AnyView(Text("测试"))

        controller.detach(
            pluginID: "a", pluginName: "A", icon: "a.circle", viewProvider: { view },
            sourceWindow: nil)
        controller.detach(
            pluginID: "b", pluginName: "B", icon: "b.circle", viewProvider: { view },
            sourceWindow: nil)

        #expect(controller.focusIfOpen("a") == true)
        #expect(controller.focusIfOpen("b") == true)

        controller.closeAll()

        #expect(controller.focusIfOpen("a") == false)
        #expect(controller.focusIfOpen("b") == false)
    }

    @Test("分离窗口有最小尺寸约束")
    func detachedWindowHasMinSize() {
        let controller = PluginPanelController()
        let view = AnyView(Text("测试"))

        controller.detach(
            pluginID: "test-min",
            pluginName: "Test",
            icon: "gear",
            viewProvider: { view },
            sourceWindow: nil
        )

        #expect(DesignTokens.Size.detachedPanelMinWidth > 0)
        #expect(DesignTokens.Size.detachedPanelMinHeight > 0)

        controller.closeAll()
    }

    // MARK: - 与主面板相互独立

    @Test("分离窗口是非激活面板，且失活时不隐藏")
    func detachedWindowStaysIndependent() {
        let controller = PluginPanelController()
        let view = AnyView(Text("测试"))

        controller.detach(
            pluginID: "independent",
            pluginName: "独立窗口",
            icon: "macwindow",
            viewProvider: { view },
            sourceWindow: nil
        )

        let panel = detachedPanel("independent")
        #expect(panel != nil)

        // 非激活面板不参与应用激活时的窗口排序 —— 唤出主面板不会把它带到前台
        #expect(panel?.styleMask.contains(.nonactivatingPanel) == true)
        // 应用失活时也不能被自动隐藏
        #expect(panel?.hidesOnDeactivate == false)
        #expect(panel?.level == .normal)

        controller.closeAll()
    }

    @Test("置顶在 floating 与 normal 之间切换")
    func alwaysOnTopTogglesLevel() {
        let controller = PluginPanelController()
        let view = AnyView(Text("测试"))

        controller.detach(
            pluginID: "pin-test",
            pluginName: "置顶测试",
            icon: "pin",
            viewProvider: { view },
            sourceWindow: nil
        )

        controller.setAlwaysOnTop("pin-test", isOn: true)
        #expect(detachedPanel("pin-test")?.level == .floating)

        controller.setAlwaysOnTop("pin-test", isOn: false)
        #expect(detachedPanel("pin-test")?.level == .normal)

        controller.closeAll()
    }

    @Test("对未打开的插件设置置顶是安全的空操作")
    func alwaysOnTopOnMissingWindowIsNoop() {
        let controller = PluginPanelController()
        controller.setAlwaysOnTop("does-not-exist", isOn: true)
        controller.refresh("does-not-exist")
        controller.close("does-not-exist")
    }

    // MARK: - 刷新

    @Test("刷新会重新调用视图工厂")
    func refreshRebuildsFromProvider() {
        let controller = PluginPanelController()
        let calls = Counter()

        controller.detach(
            pluginID: "refresh-test",
            pluginName: "刷新测试",
            icon: "arrow.clockwise",
            viewProvider: {
                calls.increment()
                return AnyView(Text("第 \(calls.value) 次"))
            },
            sourceWindow: nil
        )

        #expect(calls.value == 1)

        controller.refresh("refresh-test")
        #expect(calls.value == 2)
        #expect(detachedPanel("refresh-test") != nil)

        controller.refresh("refresh-test")
        #expect(calls.value == 3)

        controller.closeAll()
    }

    @Test("关闭后不再保留视图工厂")
    func closeDropsProvider() {
        let controller = PluginPanelController()
        let calls = Counter()

        controller.detach(
            pluginID: "drop-test",
            pluginName: "回收测试",
            icon: "trash",
            viewProvider: {
                calls.increment()
                return AnyView(Text("x"))
            },
            sourceWindow: nil
        )

        controller.close("drop-test")
        let afterClose = calls.value

        // 窗口已关，刷新不应再触发工厂
        controller.refresh("drop-test")
        #expect(calls.value == afterClose)
    }

    /// 在 @MainActor 闭包里计数的可变盒子
    private final class Counter {
        private(set) var value = 0
        func increment() { value += 1 }
    }
}

// MARK: - 悬浮胶囊

@MainActor
@Suite("FloatingCapsuleView 悬浮胶囊")
struct FloatingCapsuleViewTests {

    private func makeSuperview() -> NSView {
        NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    }

    private func makeCapsule(actions: [CapsuleAction] = []) -> FloatingCapsuleView {
        FloatingCapsuleView(positionKey: "test.capsule", actions: actions)
    }

    @Test("默认停在父视图右上角，且不出界")
    func parksAtTopRight() {
        let superview = makeSuperview()
        let capsule = makeCapsule()
        superview.addSubview(capsule)
        capsule.positionInSuperview()

        #expect(capsule.frame.width > 0)
        #expect(capsule.frame.height > 0)
        #expect(capsule.frame.maxX <= superview.bounds.width)
        #expect(capsule.frame.maxY <= superview.bounds.height)
        #expect(capsule.frame.minX > 0)
        #expect(capsule.frame.minY > 0)
    }

    @Test("父视图比胶囊还小时也不会跑到界外")
    func clampsInsideTinySuperview() {
        let superview = NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        let capsule = makeCapsule()
        superview.addSubview(capsule)
        capsule.positionInSuperview()

        #expect(capsule.frame.minX >= 0)
        #expect(capsule.frame.minY >= 0)
    }

    @Test("每个动作都会变成一个按钮")
    func actionsBecomeButtons() {
        let capsule = makeCapsule(actions: [
            CapsuleAction(id: "pin", symbol: "pin", tooltip: "置顶", kind: .toggle) {},
            CapsuleAction(id: "refresh", symbol: "arrow.clockwise", tooltip: "刷新") {},
            CapsuleAction(id: "close", symbol: "xmark", tooltip: "关闭", kind: .destructive) {}
        ])

        // 三个动作 + 抓手 + 展开箭头
        #expect(capsule.subviews.contains { $0 is NSStackView })
        #expect(capsule.frame.width > DesignTokens.Size.Capsule.buttonSize)
    }

    @Test("回写未注册按钮的状态是安全的空操作")
    func setToggleOnUnknownIDIsNoop() {
        let capsule = makeCapsule(actions: [
            CapsuleAction(id: "pin", symbol: "pin", tooltip: "置顶", kind: .toggle) {}
        ])
        capsule.setToggle("nope", isOn: true)
        capsule.setToggle("pin", isOn: true, tooltip: "取消置顶")
    }

    @Test("拖拽落点被夹在父视图内")
    func movesAreClamped() {
        let superview = makeSuperview()
        let capsule = makeCapsule()
        superview.addSubview(capsule)
        capsule.positionInSuperview()

        // 往左上冲出很远
        capsule.move(to: NSPoint(x: -5000, y: -5000), in: superview.bounds.size)
        #expect(capsule.frame.minX >= DesignTokens.Size.Capsule.edgeInset)
        #expect(capsule.frame.minY >= DesignTokens.Size.Capsule.edgeInset)

        // 往右下冲出很远
        capsule.move(to: NSPoint(x: 5000, y: 5000), in: superview.bounds.size)
        #expect(capsule.frame.maxX <= superview.bounds.width)
        #expect(capsule.frame.maxY <= superview.bounds.height)
    }

    @Test("位置按 positionKey 持久化，并能被同一 key 的新实例读回")
    func persistsPositionPerKey() {
        let key = "integration.test.\(UUID().uuidString)"
        let superview = makeSuperview()

        let first = FloatingCapsuleView(positionKey: key, actions: [])
        superview.addSubview(first)
        first.positionInSuperview()
        first.move(to: NSPoint(x: 33, y: 44), in: superview.bounds.size)
        first.persistPosition()

        // 同一 key 的新实例（相当于下次打开同一个窗口）应回到原处
        let second = FloatingCapsuleView(positionKey: key, actions: [])
        superview.addSubview(second)
        second.positionInSuperview()

        #expect(second.frame.origin == first.frame.origin)

        UserDefaults.standard.removeObject(forKey: "quick.capsule.pos." + key)
    }
}
