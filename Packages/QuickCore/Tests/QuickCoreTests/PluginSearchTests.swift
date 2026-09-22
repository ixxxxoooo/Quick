// PluginSearchTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Testing

@testable import QuickCore

@MainActor
@Suite("插件内搜索桥接")
struct PluginSearchTests {

    /// 面板按键后插件靠 `commandToken` 变化来取走请求，所以每次 request 都必须递增
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

    /// 分离窗口注入的是没有头部搜索框的兜底对象
    @Test("hasHeaderField 区分面板与分离窗口")
    func headerFieldFlag() {
        #expect(PluginSearchQuery().hasHeaderField)
        #expect(PluginSearchQuery(hasHeaderField: false).hasHeaderField == false)
    }
}
