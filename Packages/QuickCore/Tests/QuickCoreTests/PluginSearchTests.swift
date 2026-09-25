// PluginSearchTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Testing

@testable import QuickCore

@MainActor
@Suite("插件内搜索桥接")
struct PluginSearchTests {

    /// 每次导航请求都递增令牌并记录命令
    @Test("每次导航请求都递增令牌并记录命令")
    func requestIncrementsToken() {
        let search = PluginSearchQuery()
        #expect(search.commandToken == 0)
        #expect(search.lastCommand == nil)

        search.request(.move(1))
        #expect(search.commandToken == 1)
        #expect(search.lastCommand == .move(1))

        search.request(.tab(-1))
        #expect(search.commandToken == 2)
        #expect(search.lastCommand == .tab(-1))

        search.request(.submit)
        #expect(search.commandToken == 3)
        #expect(search.lastCommand == .submit)
    }

    /// `wantsNavigation` 是插件自己维护的开关：为假时面板必须放行按键
    @Test("默认不吃按键，插件置真后才吃")
    func navigationOptIn() {
        let search = PluginSearchQuery()
        #expect(search.wantsNavigation == false)
        search.wantsNavigation = true
        #expect(search.wantsNavigation)
    }

    /// 离开插件时不清掉会让下一个插件莫名吃掉方向键
    @Test("reset 清空文本、导航开关与请求")
    func resetClearsEverything() {
        let search = PluginSearchQuery()
        search.text = "abc"
        search.wantsNavigation = true
        search.request(.submit)

        search.reset()

        #expect(search.text == "")
        #expect(search.wantsNavigation == false)
        #expect(search.lastCommand == nil)
    }

    /// 同插件二次 show 时 onAppear 不会再跑，靠 shownToken 重新声明导航
    @Test("notifyShown 递增 shownToken 且不影响 wantsNavigation")
    func notifyShownIncrementsToken() {
        let search = PluginSearchQuery()
        #expect(search.shownToken == 0)
        search.wantsNavigation = true
        search.notifyShown()
        #expect(search.shownToken == 1)
        #expect(search.wantsNavigation)
        search.reset()
        #expect(search.wantsNavigation == false)
        #expect(search.shownToken == 1, "reset 不碰 shownToken")
        search.notifyShown()
        #expect(search.shownToken == 2)
    }

    /// 分离窗口注入的是没有头部搜索框的兜底对象
    @Test("hasHeaderField 区分面板与分离窗口")
    func headerFieldFlag() {
        #expect(PluginSearchQuery().hasHeaderField)
        #expect(PluginSearchQuery(hasHeaderField: false).hasHeaderField == false)
    }
}
