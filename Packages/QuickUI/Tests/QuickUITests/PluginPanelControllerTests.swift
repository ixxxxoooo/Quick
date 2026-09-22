// PluginPanelControllerTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Carbon.HIToolbox
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

    // MARK: - 标题栏

    /// 回归：分离窗口必须拖得动
    ///
    /// `isMovableByWindowBackground` 在 SwiftUI 内容上靠不住（理由见 `WindowDragArea`），
    /// 所以标题栏里挂了一个真实的拖拽视图。它被删掉、或者被铺到按钮上面（那样会把点击吃掉），
    /// 表现都是「窗口拖不动 / 按钮点不动」—— 而这两种都只有靠手试才发现。
    @Test("标题栏挂了拖拽区")
    func titleBarHasDragArea() {
        let controller = PluginPanelController()
        let view = AnyView(Text("测试"))

        controller.detach(
            pluginID: "drag-test",
            pluginName: "拖拽测试",
            icon: "hand.draw",
            viewProvider: { view },
            sourceWindow: nil
        )

        let container = detachedPanel("drag-test")?.contentView
        container?.layoutSubtreeIfNeeded()

        #expect(container?.firstDescendant(of: WindowDragView.self) != nil)

        // 窗口没被激活时第一次按下也要能拖起来，否则用户得先点一下窗口再拖
        #expect(WindowDragView().acceptsFirstMouse(for: nil))

        controller.closeAll()
    }

    /// 回归：标题栏那两个按钮要比底栏按钮小一档
    @Test("窗口控制按钮比底栏按钮小")
    func windowControlButtonIsSmaller() {
        #expect(DesignTokens.Size.windowControlButton < DesignTokens.Size.barButtonHeight)
    }

    // MARK: - 插件内搜索

    /// 分离窗口的搜索框归属与主面板一致：只有声明 `supportsPanelSearch` 的插件才有。
    @Test("分离窗口按 supportsSearch 决定是否保留搜索框")
    func detachedSearchFollowsSupportsPanelSearch() {
        let controller = PluginPanelController()
        let view = AnyView(Text("测试"))

        controller.detach(
            pluginID: "search-off",
            pluginName: "无搜索",
            icon: "doc",
            viewProvider: { view },
            sourceWindow: nil
        )
        controller.detach(
            pluginID: "search-on",
            pluginName: "有搜索",
            icon: "doc.on.clipboard",
            supportsSearch: true,
            viewProvider: { view },
            sourceWindow: nil
        )

        #expect((detachedPanel("search-off") as? DetachedPluginPanel)?.search?.hasHeaderField == false)
        #expect((detachedPanel("search-on") as? DetachedPluginPanel)?.search?.hasHeaderField == true)

        // 搜索框放进标题栏后，标题栏仍要留着拖拽区（否则窗口拖不动）
        let onContainer = detachedPanel("search-on")?.contentView
        onContainer?.layoutSubtreeIfNeeded()
        #expect(onContainer?.firstDescendant(of: WindowDragView.self) != nil)

        controller.closeAll()
    }

    /// 带搜索框的标题栏必须比普通标题栏高，且容得下标准搜索框
    @Test("带搜索的分离窗口标题栏高度放得下搜索框")
    func detachedSearchTitleBarFitsSearchField() {
        #expect(DesignTokens.Size.detachedSearchTitleBarHeight >= DesignTokens.Size.headerHeight)
        #expect(DesignTokens.Size.detachedSearchTitleBarHeight > DesignTokens.Size.detachedTitleBarHeight)
    }

    /// 回归：分离窗口里声明了要吃方向键的插件，必须由窗口在 AppKit 层转成 `PluginSearchQuery` 请求。
    ///
    /// 没有这段路由时，搜索框一拿到焦点，field editor 就把方向键与回车吃掉，插件列表一个键都收不到 ——
    /// 这正是主搜索踩过的坑（见 docs/ui.md §2b）。
    @Test("分离窗口把导航键转成插件内搜索请求")
    func detachedRoutesNavigationToPluginSearch() {
        let controller = PluginPanelController()
        let view = AnyView(Text("测试"))

        controller.detach(
            pluginID: "route-test",
            pluginName: "路由",
            icon: "list.bullet",
            supportsSearch: true,
            viewProvider: { view },
            sourceWindow: nil
        )

        guard let panel = detachedPanel("route-test") as? DetachedPluginPanel,
            let search = panel.search
        else {
            Issue.record("没有拿到分离面板或其搜索对象")
            controller.closeAll()
            return
        }

        // 插件没声明要吃按键时，三个键都必须放行
        #expect(panel.onMove?(1) == false)
        #expect(panel.onSubmit?() == false)
        #expect(search.lastCommand == nil)

        search.wantsNavigation = true
        #expect(panel.onMove?(1) == true)
        #expect(search.lastCommand == .move(1))
        #expect(panel.onTab?(-1) == true)
        #expect(search.lastCommand == .tab(-1))
        #expect(panel.onSubmit?() == true)
        #expect(search.lastCommand == .submit)

        // ⌘F 只有真正有搜索框时才消费
        let before = search.focusToken
        #expect(panel.onSearchFocus?() == true)
        #expect(search.focusToken == before + 1)

        controller.closeAll()
    }

    /// 回车（含小键盘回车）在分离窗口里也走同一条搜索请求
    @Test("分离窗口拦截回车并交给插件内搜索")
    func detachedConsumesReturnKey() {
        let controller = PluginPanelController()
        let view = AnyView(Text("测试"))

        controller.detach(
            pluginID: "return-test",
            pluginName: "回车",
            icon: "return",
            supportsSearch: true,
            viewProvider: { view },
            sourceWindow: nil
        )

        guard let panel = detachedPanel("return-test") as? DetachedPluginPanel,
            let search = panel.search
        else {
            Issue.record("没有拿到分离面板或其搜索对象")
            controller.closeAll()
            return
        }

        search.wantsNavigation = true
        guard
            let returnKey = Self.keyDown(
                keyCode: kVK_Return, modifiers: [], characters: "\r")
        else {
            Issue.record("无法构造合成按键事件")
            controller.closeAll()
            return
        }

        panel.sendEvent(returnKey)
        #expect(search.lastCommand == .submit)

        controller.closeAll()
    }

    /// 合成一个按下事件（与 PalettePanelTests 同款：返回 nil 时由调用方记一条失败，而不是崩掉）
    private static func keyDown(
        keyCode: Int,
        modifiers: NSEvent.ModifierFlags,
        characters: String
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: UInt16(keyCode)
        )
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

// MARK: - 视图树查找

extension NSView {
    /// 在子树里找第一个指定类型的视图（含自身）
    func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        if let match = self as? T { return match }
        for subview in subviews {
            if let found = subview.firstDescendant(of: type) { return found }
        }
        return nil
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
