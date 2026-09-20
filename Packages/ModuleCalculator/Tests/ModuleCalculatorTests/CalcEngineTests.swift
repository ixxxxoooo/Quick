// CalcEngineTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Testing
@testable import ModuleCalculator

@MainActor
@Suite("计算器引擎")
struct CalcEngineTests {

    /// 基础四则运算
    @Test("四则运算")
    func basicArithmetic() {
        let engine = CalcEngine()
        #expect(engine.evaluate("1+1")?.formatted == "2")
        #expect(engine.evaluate("10*3")?.formatted == "30")
        #expect(engine.evaluate("100/4")?.formatted == "25")
    }

    /// 非法表达式应返回 nil
    @Test("非法表达式")
    func invalidExpression() {
        let engine = CalcEngine()
        #expect(engine.evaluate("") == nil)
        #expect(engine.evaluate("not-a-math") == nil)
    }
}
