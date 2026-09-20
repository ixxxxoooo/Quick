// TriggerMatchingTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import QuickCore

@Suite("触发词匹配")
struct TriggerMatchingTests {

    // MARK: - 不该命中（这是这套规则存在的理由）

    @Test("拉丁触发词按整词匹配，不会被子串误触发")
    func latinTriggersRequireWholeWord() {
        // 这些曾经都是真实缺陷：用 contains 判断时全部会误命中
        #expect("email".matchesAnyTrigger(["ai"]) == false, "email 不该命中 ai")
        #expect("clipboard".matchesAnyTrigger(["ip"]) == false, "clipboard 不该命中 ip")
        #expect("export".matchesAnyTrigger(["port"]) == false, "export 不该命中 port")
        #expect("memory".matchesAnyTrigger(["memo"]) == false, "memory 不该命中 memo")
        #expect("description".matchesAnyTrigger(["ip"]) == false)
        #expect("support".matchesAnyTrigger(["port"]) == false)
        #expect("import".matchesAnyTrigger(["port"]) == false)
        #expect("wait".matchesAnyTrigger(["ai"]) == false, "wait 不该命中 ai")
        #expect("task".matchesAnyTrigger(["ask"]) == false, "task 不该命中 ask")
    }

    @Test("单个字母不会误触发")
    func singleLettersDoNotFire() {
        // systemcontrol 曾经完全没有触发词闸门，打一个 l 就冒出「锁定屏幕」
        #expect("l".matchesAnyTrigger(["锁屏", "lock"]) == false)
        #expect("o".matchesAnyTrigger(["锁屏", "lock"]) == false)
        #expect("s".matchesAnyTrigger(["睡眠", "sleep"]) == false)
    }

    // MARK: - 该命中

    @Test("拉丁触发词作为独立词可以命中")
    func latinTriggersMatchAsWords() {
        #expect("ai".matchesAnyTrigger(["ai"]))
        #expect("ai chat".matchesAnyTrigger(["ai"]))
        #expect("chat with ai".matchesAnyTrigger(["ai"]))
        #expect("ip".matchesAnyTrigger(["ip"]))
        #expect("port".matchesAnyTrigger(["port"]))
        #expect("memo".matchesAnyTrigger(["memo"]))
    }

    @Test("中文触发词按前缀或子串命中")
    func cjkTriggersMatchByPrefixOrSubstring() {
        // 中文没有词边界，`天气北京` 必须能命中 `天气`
        #expect("天气".matchesAnyTrigger(["天气"]))
        #expect("天气北京".matchesAnyTrigger(["天气"]))
        #expect("北京天气".matchesAnyTrigger(["天气"]))
        #expect("剪贴板".matchesAnyTrigger(["剪贴板"]))
        #expect("看下天气".matchesAnyTrigger(["天气"]))
    }

    @Test("空查询不命中任何触发词")
    func emptyQueryMatchesNothing() {
        #expect("".matchesAnyTrigger(["ai", "天气"]) == false)
        #expect("   ".matchesAnyTrigger(["ai", "天气"]) == false)
    }

    // MARK: - 剥离

    @Test("剥离触发词后剩下真正的查询词")
    func removingTriggerLeavesTheQuery() {
        #expect("天气 北京".removingTrigger(["天气"]) == "北京")
        #expect("笔记 会议".removingTrigger(["笔记"]) == "会议")
        #expect("notes meeting".removingTrigger(["notes"]) == "meeting")
        #expect("ai 写首诗".removingTrigger(["ai"]) == "写首诗")
    }

    @Test("只有触发词时剩下空串")
    func triggerAloneLeavesEmpty() {
        // 这是「列出全部」的信号，不是「拿触发词去过滤数据」——
        // 后者永远匹配不到任何东西，是 Notes / DevTools 曾经的缺陷。
        #expect("天气".removingTrigger(["天气"]).isEmpty)
        #expect("笔记".removingTrigger(["笔记"]).isEmpty)
        #expect("notes".removingTrigger(["notes"]).isEmpty)
    }

    @Test("没有触发词时原样返回")
    func noTriggerReturnsQueryUnchanged() {
        #expect("北京".removingTrigger(["天气"]) == "北京")
    }

    @Test("优先剥离更长的触发词")
    func longerTriggerWins() {
        // 否则 `lock` 会先命中，把 `screen` 留在查询词里
        #expect("lock screen".removingTrigger(["lock", "lock screen"]).isEmpty)
        #expect("lock screen now".removingTrigger(["lock", "lock screen"]) == "now")
    }

    @Test("命中项可以被查出来")
    func matchedTriggerIsReported() {
        #expect("天气 北京".matchedTrigger(in: ["天气", "weather"]) == "天气")
        #expect("weather beijing".matchedTrigger(in: ["天气", "weather"]) == "weather")
        #expect("北京".matchedTrigger(in: ["天气", "weather"]).isEmpty)
    }

    // MARK: - CJK 判定

    @Test("CJK 判定覆盖中日韩")
    func cjkDetection() {
        #expect("天气".containsCJK)
        #expect("ひらがな".containsCJK)
        #expect("한글".containsCJK)
        #expect("weather".containsCJK == false)
        #expect("天气 weather".containsCJK)
    }
}
