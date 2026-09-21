// FuzzyMatchTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Testing
@testable import QuickCore

@Suite("模糊匹配测试")
struct FuzzyMatchTests {

    /// 空查询应匹配任意字符串
    @Test("空查询始终匹配")
    func emptyQueryMatches() {
        #expect("Safari".fuzzyMatch(""))
        #expect("".fuzzyMatch(""))
    }

    /// 连续子串应匹配
    @Test("前缀与包含匹配")
    func prefixAndContains() {
        #expect("Safari".fuzzyMatch("Saf"))
        #expect("Safari".fuzzyMatch("ari"))
        #expect("Visual Studio Code".fuzzyMatch("VSC") || "Visual Studio Code".fuzzyMatch("vsc"))
        // 模糊：按顺序取字母即可
        #expect("Safari".fuzzyMatch("sfi"))
    }

    /// 乱序字符不应匹配
    @Test("乱序不匹配")
    func outOfOrderFails() {
        #expect(!"Safari".fuzzyMatch("ifaS"))
    }

    /// 评分优先级：完全 > 前缀 > 包含 > 模糊
    @Test("相关度评分排序")
    func scoreOrdering() {
        #expect("Safari".fuzzyScore("Safari") == 1.0)
        #expect("Safari".fuzzyScore("Saf") == 0.9)
        #expect("MySafariApp".fuzzyScore("Safari") == 0.7)
        #expect("Calculator".fuzzyScore("xyz") == 0)
    }

    /// 子序列命中夹在「不匹配」和「包含」之间 —— 一旦越过 0.7，模糊匹配就会压过真正的子串命中
    @Test("子序列命中的分数区间")
    func subsequenceIsBanded() {
        let score = "Visual Studio Code".fuzzyScore("vsc")
        #expect(score > 0)
        #expect(score > 0.35)
        #expect(score < 0.7)
    }

    /// 词首命中要比词中命中靠前：`vsc` 打出来指的是 Visual Studio Code，不是 Viscosity
    @Test("词首命中排在词中命中之前")
    func wordStartsOutrankMidWord() {
        #expect("Visual Studio Code".fuzzyScore("vsc") > "Viscosity".fuzzyScore("vsc"))
        #expect("System File Index".fuzzyScore("sfi") > "Safari".fuzzyScore("sfi"))
    }

    /// 不匹配就是 0，`fuzzyMatch` 与 `fuzzyScore` 必须一致
    @Test("不匹配得 0")
    func noMatchScoresZero() {
        #expect("Calculator".fuzzyScore("xyz") == 0)
        #expect(!"Calculator".fuzzyMatch("xyz"))
        #expect("".fuzzyScore("a") == 0)
    }

    /// 只有空白的查询词等于「没有筛选条件」，不该命中任何东西
    @Test("空白查询不命中")
    func whitespaceQueryMatchesNothing() {
        #expect("Safari".fuzzyScore("   ") == 0)
        #expect(!"Safari".fuzzyMatch("   "))
    }

    /// 变音符号不再区分
    @Test("变音符号折叠")
    func diacriticsAreFolded() {
        #expect("Café".fuzzyScore("cafe") == 1.0)
        #expect("Café".fuzzyScore("café") == 1.0)
    }

    /// 预处理形态与 String 便捷入口必须是同一套打分 —— 否则「预热的那个」和「随手用的那个」会给出不同排序
    @Test("预处理形态与便捷入口一致")
    func preparedFormsAgreeWithConvenienceAPI() {
        let query = MatchQuery("vsc")
        #expect(
            query.score(MatchText("Visual Studio Code")) == "Visual Studio Code".fuzzyScore("vsc")
        )
        #expect(query.matches(MatchText("Visual Studio Code")))
        #expect(query.score(MatchText("Calculator")) == "Calculator".fuzzyScore("vsc"))
        #expect(!query.matches(MatchText("Calculator")))
    }
}
