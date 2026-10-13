// AccessibilityAdaptationTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Testing

@testable import QuickUI

@Suite("无障碍适配")
struct AccessibilityAdaptationTests {

    // MARK: - 增强对比度

    @Test("默认对比度下不透明度原样返回")
    func normalContrastUnchanged() {
        #expect(ContrastBoost.alpha(0.1, highContrast: false) == 0.1)
    }

    @Test("高对比度下按倍数抬高")
    func highContrastScales() {
        #expect(abs(ContrastBoost.alpha(0.2, highContrast: true) - 0.36) < 0.0001)
    }

    @Test("高对比度下很淡的线条抬到下限")
    func highContrastFloor() {
        #expect(ContrastBoost.alpha(0.02, highContrast: true) == ContrastBoost.floor)
    }

    @Test("高对比度下不超过 1")
    func highContrastCapped() {
        #expect(ContrastBoost.alpha(0.8, highContrast: true) == 1)
    }

    @Test("完全透明保持透明，不被下限抬起来")
    func zeroStaysZero() {
        #expect(ContrastBoost.alpha(0, highContrast: true) == 0)
    }

    @Test("开启增强对比度后深浅色判断不变：深色白墨、浅色黑墨")
    func inkDirectionUnchangedUnderHighContrast() throws {
        let aqua = try #require(NSAppearance(named: .aqua))
        let darkAqua = try #require(NSAppearance(named: .darkAqua))
        let light = DesignTokens.Colors.resolveRamp(
            dark: 0.1, light: 0.1, appearance: aqua, systemIncreaseContrast: true)
        let dark = DesignTokens.Colors.resolveRamp(
            dark: 0.1, light: 0.1, appearance: darkAqua, systemIncreaseContrast: true)
        #expect((light.usingColorSpace(.sRGB) ?? light).redComponent < 0.5)
        #expect((dark.usingColorSpace(.sRGB) ?? dark).redComponent > 0.5)
    }

    @Test("系统「增强对比度」开关开启时不透明度被抬升")
    func systemSwitchBoosts() throws {
        let aqua = try #require(NSAppearance(named: .aqua))
        let off = DesignTokens.Colors.resolveRamp(
            dark: 0.1, light: 0.1, appearance: aqua, systemIncreaseContrast: false)
        let on = DesignTokens.Colors.resolveRamp(
            dark: 0.1, light: 0.1, appearance: aqua, systemIncreaseContrast: true)
        #expect(on.alphaComponent > off.alphaComponent)
    }

    // MARK: - 减弱动态效果

    @Test("减弱动态效果时时长为 0")
    func reducedMotionZeroDuration() {
        #expect(Motion.duration(0.2, reduced: true) == 0)
        #expect(Motion.duration(0.2, reduced: false) == 0.2)
    }
}
