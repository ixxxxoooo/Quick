// AIWebViewWindowTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Carbon.HIToolbox
import Foundation
import QuickCore
import Testing

@testable import PluginAI

/// AI 聚合窗口配置测试
///
/// 验证聚合窗口的基本配置与交互行为
@Suite("AI 聚合窗口配置")
@MainActor
struct AIWebViewWindowTests {

    private func makePanel() throws -> AIWebViewPanel {
        let provider = try #require(AIProviderRegistry.provider(for: "deepseek"))
        return AIWebViewWindowManager.makePanel(
            provider: provider,
            size: NSSize(width: 800, height: 600)
        )
    }

    /// 非激活面板不参与应用激活时的窗口排序，也就不会出现在 ⌘Tab / Mission Control 里
    @Test("不是非激活面板")
    func isNotNonactivatingPanel() throws {
        let panel = try makePanel()
        #expect(panel.styleMask.contains(.nonactivatingPanel) == false)
    }

    @Test("是普通窗口：能成为 key，也能成为 main")
    func canBecomeKeyAndMain() throws {
        let panel = try makePanel()
        #expect(panel.canBecomeKey)
        #expect(panel.canBecomeMain)
    }

    /// 切到别的应用时窗口要留在屏幕上，切回来才找得到它
    @Test("失活时不隐藏")
    func staysVisibleWhenInactive() throws {
        let panel = try makePanel()
        #expect(panel.hidesOnDeactivate == false)
    }

    @Test("窗口标识带着 Provider id")
    func identifierCarriesProviderID() throws {
        let panel = try makePanel()
        #expect(panel.identifier?.rawValue == "quick.ai.deepseek")
    }

    @Test("标题就是 Provider 显示名，且关闭窗口背景拖拽以免拦截 WebView 点击")
    func titleIsProviderName() throws {
        let panel = try makePanel()
        #expect(panel.title == "DeepSeek")
        #expect(panel.isMovableByWindowBackground == false)
    }

    @Test("WebView 使用原生 Safari User-Agent（不含 Chrome 伪装，避免 Kimi Lexical 编辑器输入失效）")
    func usesNativeSafariUserAgent() {
        let ua = AIWebViewWindowManager.safariUserAgent
        #expect(ua.contains("AppleWebKit/"))
        #expect(ua.contains("Safari/"))
        #expect(!ua.contains("Chrome/"))
    }

    @Test("WebView 外部链接与新窗口链接使用默认浏览器打开，同站点导航保持在 WebView 内")
    func externalAndNewWindowLinksOpenInDefaultBrowser() throws {
        let kimiCurrent = try #require(URL(string: "https://kimi.moonshot.cn/chat/abc"))
        let externalURL = try #require(URL(string: "https://github.com/apple/swift"))
        let sameSiteURL = try #require(URL(string: "https://kimi.moonshot.cn/chat/def"))
        let sameFamilyURL = try #require(URL(string: "https://www.kimi.com/chat/xyz"))
        let mailtoURL = try #require(URL(string: "mailto:support@example.com"))
        let blankURL = try #require(URL(string: "about:blank"))

        // 1. target="_blank" 或 window.open 触发的新窗口请求应由默认浏览器打开
        #expect(
            AIWebViewNavigationHandler.shouldOpenInDefaultBrowser(
                targetURL: externalURL,
                currentURL: kimiCurrent,
                isNewWindow: true,
                isLinkActivated: true
            )
        )
        #expect(
            AIWebViewNavigationHandler.shouldOpenInDefaultBrowser(
                targetURL: sameSiteURL,
                currentURL: kimiCurrent,
                isNewWindow: true,
                isLinkActivated: false
            )
        )

        // 2. 当前帧点击跨域链接应由默认浏览器打开
        #expect(
            AIWebViewNavigationHandler.shouldOpenInDefaultBrowser(
                targetURL: externalURL,
                currentURL: kimiCurrent,
                isNewWindow: false,
                isLinkActivated: true
            )
        )

        // 3. 当前帧点击同域或同品牌域名家族链接保持在 WebView 内打开
        #expect(
            AIWebViewNavigationHandler.shouldOpenInDefaultBrowser(
                targetURL: sameSiteURL,
                currentURL: kimiCurrent,
                isNewWindow: false,
                isLinkActivated: true
            ) == false
        )
        #expect(
            AIWebViewNavigationHandler.shouldOpenInDefaultBrowser(
                targetURL: sameFamilyURL,
                currentURL: kimiCurrent,
                isNewWindow: false,
                isLinkActivated: true
            ) == false
        )

        // 4. 非用户点击的自动重定向（如 OAuth / SSO 跳转）保持在 WebView 内
        #expect(
            AIWebViewNavigationHandler.shouldOpenInDefaultBrowser(
                targetURL: externalURL,
                currentURL: kimiCurrent,
                isNewWindow: false,
                isLinkActivated: false
            ) == false
        )

        // 5. mailto: 等系统协议走外部打开，about:blank 不走外部打开
        #expect(
            AIWebViewNavigationHandler.shouldOpenInDefaultBrowser(
                targetURL: mailtoURL,
                currentURL: kimiCurrent,
                isNewWindow: false,
                isLinkActivated: true
            )
        )
        #expect(
            AIWebViewNavigationHandler.shouldOpenInDefaultBrowser(
                targetURL: blankURL,
                currentURL: kimiCurrent,
                isNewWindow: true,
                isLinkActivated: false
            ) == false
        )
    }

    /// 主菜单刻意不放 ⌘W（留给主面板），所以这个普通窗口得自己接住它。
    @Test("⌘W 被接住并触发关闭回调")
    func commandWCloses() throws {
        let panel = try makePanel()
        var closed = 0
        panel.onClose = { closed += 1 }

        guard
            let commandW = Self.keyDown(
                keyCode: kVK_ANSI_W, modifiers: .command, characters: "w")
        else {
            Issue.record("无法构造合成按键事件")
            return
        }

        #expect(panel.performKeyEquivalent(with: commandW))
        #expect(closed == 1)
    }

    /// 快捷键再按一次必须关掉：只 openOrFocus 的话窗口会一直留着，用户以为热键坏了。
    @Test("toggle 在窗口可见时隐藏，不可见时打开")
    func toggleHidesVisibleWindow() {
        let key = PluginSettingKey.AIPortal.providerEnabled("deepseek")
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.removeObject(forKey: key)

        let manager = AIWebViewWindowManager()
        #expect(manager.toggle(providerId: "deepseek"), "第一次应打开")

        #expect(manager.toggle(providerId: "deepseek") == false, "第二次应隐藏")

        #expect(manager.toggle(providerId: "deepseek"), "第三次再打开")

        manager.closeAll()
    }

    /// 其余按键必须放行，否则窗口会吃掉所有键盘输入
    @Test("普通按键不被窗口消费")
    func otherKeysFallThrough() throws {
        let panel = try makePanel()
        guard
            let commandR = Self.keyDown(
                keyCode: kVK_ANSI_R, modifiers: .command, characters: "r")
        else {
            Issue.record("无法构造合成按键事件")
            return
        }
        #expect(panel.performKeyEquivalent(with: commandR) == false)
    }

    // MARK: - 标题栏标签栏与操作按钮测试

    @Test("标题栏标签栏支持添加/删除标签，加号按钮始终在末尾")
    func titleTabBarAddRemoveTabs() {
        let bar = AITitleTabBarView(
            onSelect: { _ in },
            onClose: { _ in },
            onAddProvider: { _ in },
            onTogglePin: { },
            onReload: { },
            onOpenExternal: { },
            onCloseActive: { }
        )

        #expect(bar.tabCount == 0)
        #expect(bar.mouseDownCanMoveWindow)
        #expect(bar.stackView.arrangedSubviews.last === bar.addButton)

        bar.addTab(id: "deepseek", title: "DeepSeek", icon: "brain")
        bar.addTab(id: "chatgpt", title: "ChatGPT", icon: "bubble.left.and.bubble.right")

        #expect(bar.tabCount == 2)
        #expect(bar.tabIDs == ["deepseek", "chatgpt"])
        #expect(bar.stackView.arrangedSubviews.last === bar.addButton)

        bar.removeTab("deepseek")
        #expect(bar.tabCount == 1)
        #expect(bar.tabIDs == ["chatgpt"])
        #expect(bar.stackView.arrangedSubviews.last === bar.addButton)
    }

    @Test("选择标签时操作按钮状态更新，无选中标签时禁用页面操作")
    func titleTabBarSelectionUpdatesActions() {
        let bar = AITitleTabBarView(
            onSelect: { _ in },
            onClose: { _ in },
            onAddProvider: { _ in },
            onTogglePin: { },
            onReload: { },
            onOpenExternal: { },
            onCloseActive: { }
        )

        bar.addTab(id: "deepseek", title: "DeepSeek", icon: "brain")

        bar.selectTab("deepseek")
        #expect(bar.selectedID == "deepseek")
        #expect(bar.reloadButton.isEnabled)
        #expect(bar.externalButton.isEnabled)
        #expect(bar.closeButton.isEnabled)

        bar.selectTab(nil)
        #expect(bar.selectedID == nil)
        #expect(bar.reloadButton.isEnabled == false)
        #expect(bar.externalButton.isEnabled == false)
        #expect(bar.closeButton.isEnabled == false)
    }

    @Test("置顶状态切换更新按钮提示文本")
    func titleTabBarPinStatusUpdatesTooltip() {
        let bar = AITitleTabBarView(
            onSelect: { _ in },
            onClose: { _ in },
            onAddProvider: { _ in },
            onTogglePin: { },
            onReload: { },
            onOpenExternal: { },
            onCloseActive: { }
        )

        bar.setPinned(true)
        #expect(bar.pinButton.toolTip == "取消置顶")

        bar.setPinned(false)
        #expect(bar.pinButton.toolTip == "窗口置顶")
    }

    @Test("标题栏操作按钮点击触发对应回调")
    func titleTabBarActionButtonsTriggerCallbacks() {
        var pinToggled = false
        var reloaded = false
        var openedExternal = false
        var closedActive = false

        let bar = AITitleTabBarView(
            onSelect: { _ in },
            onClose: { _ in },
            onAddProvider: { _ in },
            onTogglePin: { pinToggled = true },
            onReload: { reloaded = true },
            onOpenExternal: { openedExternal = true },
            onCloseActive: { closedActive = true }
        )

        bar.pinButton.performClick(nil)
        #expect(pinToggled)

        bar.reloadButton.performClick(nil)
        #expect(reloaded)

        bar.externalButton.performClick(nil)
        #expect(openedExternal)

        bar.closeButton.performClick(nil)
        #expect(closedActive)
    }

    @Test("标题栏图标按钮保持正圆形且边距为零")
    func titleBarIconButtonIsCircular() {
        let btn = AITitleBarIconButton(symbol: "pin", tooltip: "置顶") { }
        #expect(btn.alignmentRectInsets.top == 0)
        #expect(btn.alignmentRectInsets.bottom == 0)
        #expect(btn.alignmentRectInsets.left == 0)
        #expect(btn.alignmentRectInsets.right == 0)

        btn.frame = NSRect(x: 0, y: 0, width: 24, height: 24)
        btn.layout()
        #expect(btn.layer?.cornerRadius == 12)
    }

    // MARK: - 聚合窗口与标签状态保持测试

    @Test("openOrFocusMergedWindow 打开聚合窗口并保持选中标签状态")
    func openOrFocusMergedWindowMaintainsTabState() {
        let manager = AIWebViewWindowManager()
        defer { manager.closeAll() }

        #expect(manager.openOrFocusMergedWindow(), "应当成功打开聚合窗口")
        #expect(manager.isMergedWindowOpen(), "聚合窗口应当处于打开状态")

        // 切换到 chatgpt
        #expect(manager.openOrFocus(providerId: "chatgpt"))
        #expect(manager.activeProviderID == "chatgpt")

        // 隐藏窗口
        manager.hideWindow(for: "chatgpt")
        #expect(manager.isMergedWindowOpen() == false, "隐藏后聚合窗口应当不可见")

        // 再次调用 openOrFocusMergedWindow，应当恢复显示且保持在 chatgpt 标签页
        #expect(manager.openOrFocusMergedWindow())
        #expect(manager.isMergedWindowOpen())
        #expect(manager.activeProviderID == "chatgpt", "重新打开后应保持当时的标签页状态")
    }

    @Test("toggleMergedWindow 在聚合窗口可见时隐藏，不可见时打开")
    func toggleMergedWindowTogglesVisibility() {
        let manager = AIWebViewWindowManager()
        defer { manager.closeAll() }

        #expect(manager.toggleMergedWindow(), "第一次应当打开聚合窗口")
        #expect(manager.isMergedWindowOpen(), "聚合窗口应当可见")

        #expect(manager.toggleMergedWindow() == false, "第二次应当隐藏聚合窗口")
        #expect(manager.isMergedWindowOpen() == false, "聚合窗口应当隐藏")

        #expect(manager.toggleMergedWindow(), "第三次应当再次打开聚合窗口")
        #expect(manager.isMergedWindowOpen(), "聚合窗口应当再次可见")
    }

    @Test("聚合窗口从偏好中恢复已打开的标签列表与最后活动标签")
    func mergedWindowRestoresSavedTabsFromUserDefaults() {
        let openTabsKey = PluginSettingKey.AIPortal.openTabs
        let lastActiveKey = PluginSettingKey.AIPortal.lastActiveTab
        let savedOpenTabs = UserDefaults.standard.object(forKey: openTabsKey)
        let savedLastActive = UserDefaults.standard.object(forKey: lastActiveKey)
        defer {
            if let savedOpenTabs {
                UserDefaults.standard.set(savedOpenTabs, forKey: openTabsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: openTabsKey)
            }
            if let savedLastActive {
                UserDefaults.standard.set(savedLastActive, forKey: lastActiveKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastActiveKey)
            }
        }

        UserDefaults.standard.set(["deepseek", "chatgpt"], forKey: openTabsKey)
        UserDefaults.standard.set("chatgpt", forKey: lastActiveKey)

        let manager = AIWebViewWindowManager()
        defer { manager.closeAll() }

        #expect(manager.openOrFocusMergedWindow())
        #expect(manager.isMergedWindowOpen())
        #expect(manager.activeProviderID == "chatgpt", "应当恢复上次选中的标签页")
        let activeIDs = manager.activeProviderIDs()
        #expect(activeIDs.contains("deepseek"), "应当恢复已打开的 deepseek 标签")
        #expect(activeIDs.contains("chatgpt"), "应当恢复已打开的 chatgpt 标签")
    }

    @Test("AI 聚合窗口命令声明与快捷键关键字匹配")
    func mergedWindowCommandDeclarationAndMatching() {
        let commandID = AIPlugin.mergedWindowCommandID
        #expect(commandID == "ai.mergedWindow")
        #expect(AIPlugin.functionCommands.contains { $0.id == commandID }, "functionCommands 必须包含聚合窗口命令")
        #expect(AIPlugin.providerID(fromCommandID: commandID) == nil, "聚合窗口命令不能被误解析为 provider id")

        let matchedByTitle = KeywordResolver.match(query: "AI 聚合窗口", commands: AIPlugin.commands)
        #expect(matchedByTitle?.id == commandID, "按标题应当解出聚合窗口命令")

        let matchedByKeyword = KeywordResolver.match(query: "聚合窗口", commands: AIPlugin.commands)
        #expect(matchedByKeyword?.id == commandID, "按别名应当解出聚合窗口命令")

        let plugin = AIPlugin()
        defer { plugin.deactivate() }
        plugin.perform(commandID: commandID)
        // 应当能够通过 perform 打开/切换窗口
    }

    /// 合成一个按下事件
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
}
