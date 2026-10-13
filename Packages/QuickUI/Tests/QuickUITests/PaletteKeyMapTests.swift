// PaletteKeyMapTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Carbon.HIToolbox
import Testing

@testable import QuickUI

@Suite("面板导航键位表")
struct PaletteKeyMapTests {

    private func map(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags = [], _ chars: String? = nil)
        -> PaletteKeyMap.Navigation?
    {
        PaletteKeyMap.navigation(keyCode: keyCode, modifiers: modifiers, characters: chars)
    }

    @Test("PageUp / PageDown 翻页")
    func paging() {
        #expect(map(kVK_PageUp) == .page(-1))
        #expect(map(kVK_PageDown) == .page(1))
    }

    @Test("Home / End 只在输入框为空时才跳首尾")
    func homeEndRequireEmptyField() {
        #expect(map(kVK_Home) == .jump(.first, requiresEmptyField: true))
        #expect(map(kVK_End) == .jump(.last, requiresEmptyField: true))
    }

    @Test("⌘↑ / ⌘↓ 任何时候都跳首尾")
    func commandArrows() {
        #expect(map(kVK_UpArrow, .command) == .jump(.first, requiresEmptyField: false))
        #expect(map(kVK_DownArrow, .command) == .jump(.last, requiresEmptyField: false))
    }

    @Test("⌘1…⌘9 直达，⌘0 与带其他修饰键的不算")
    func quickSelect() {
        #expect(map(kVK_ANSI_1, .command, "1") == .quickSelect(1))
        #expect(map(kVK_ANSI_9, .command, "9") == .quickSelect(9))
        #expect(map(kVK_ANSI_0, .command, "0") == nil)
        #expect(map(kVK_ANSI_1, [.command, .shift], "1") == nil)
        #expect(map(kVK_ANSI_1, [], "1") == nil)
        #expect(map(kVK_ANSI_1, .command, "11") == nil)
    }

    @Test("Caps Lock 等无关修饰键不影响判定")
    func irrelevantModifiersIgnored() {
        #expect(map(kVK_PageDown, .capsLock) == .page(1))
    }

    @Test("带 Shift / ⌥ 的翻页键留给系统文本选择")
    func modifiedPagingIgnored() {
        #expect(map(kVK_PageDown, .shift) == nil)
        #expect(map(kVK_Home, .option) == nil)
    }

    @Test("普通字符键不是导航键")
    func plainKeysIgnored() {
        #expect(map(kVK_ANSI_A, [], "a") == nil)
        #expect(map(kVK_ANSI_A, .command, "a") == nil)
    }
}
