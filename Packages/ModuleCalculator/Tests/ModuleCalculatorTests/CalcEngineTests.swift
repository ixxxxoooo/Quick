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
        #expect(engine.evaluate("2+3*4")?.formatted == "14")
        #expect(engine.evaluate("(2+3)*4")?.formatted == "20")
        #expect(engine.evaluate("2^3")?.formatted == "8")
        #expect(engine.evaluate("sqrt(16)")?.formatted == "4")
    }

    /// 不完整表达式输入时绝不崩溃，安全返回 nil
    @Test("不完整与非法表达式零崩溃")
    func incompleteExpressionsDoNotCrash() {
        let engine = CalcEngine()
        #expect(engine.evaluate("") == nil)
        #expect(engine.evaluate("1+") == nil)
        #expect(engine.evaluate("1-") == nil)
        #expect(engine.evaluate("1*") == nil)
        #expect(engine.evaluate("1/") == nil)
        #expect(engine.evaluate("(1+2") == nil)
        #expect(engine.evaluate("(") == nil)
        #expect(engine.evaluate(")") == nil)
        #expect(engine.evaluate("sqrt(") == nil)
        #expect(engine.evaluate("1/0") == nil)
        #expect(engine.evaluate("not-a-math") == nil)
    }
}
