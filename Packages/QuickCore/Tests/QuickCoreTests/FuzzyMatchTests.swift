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
}
