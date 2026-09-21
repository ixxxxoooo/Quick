// AppEntryMatchTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import Testing

@testable import QuickPlatform

@Suite("应用条目的匹配形态")
struct AppEntryMatchTests {

    private func entry(named name: String) -> AppEntry {
        AppEntry(
            id: "com.example.app",
            name: name,
            bundleID: "com.example.app",
            path: "/Applications/\(name).app",
            isSystemApp: false
        )
    }

    /// 条目在构造时就把拼音算好了 —— 这是「每次按键不重复转写」的落点
    @Test("中文应用名能按拼音搜到")
    func chineseNameMatchesByPinyin() {
        let weChat = entry(named: "微信")
        #expect(MatchQuery("wx").matches(weChat.matchText))
        #expect(MatchQuery("weixin").matches(weChat.matchText))
        #expect(!MatchQuery("wz").matches(weChat.matchText))
    }

    /// 拉丁名字照常模糊命中
    @Test("拉丁应用名照常模糊命中")
    func latinNameStillMatches() {
        let code = entry(named: "Visual Studio Code")
        #expect(MatchQuery("vsc").matches(code.matchText))
        #expect(MatchQuery("studio").matches(code.matchText))
        #expect(!MatchQuery("xyz").matches(code.matchText))
    }
}
