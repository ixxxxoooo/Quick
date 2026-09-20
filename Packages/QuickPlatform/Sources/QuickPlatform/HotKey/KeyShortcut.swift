// KeyShortcut.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Carbon.HIToolbox

/// 快捷键组合（Carbon 编码）
public struct KeyShortcut: Hashable, Sendable, Codable {

    public let carbonKeyCode: Int
    public let carbonModifiers: Int

    private static let allModifiers = cmdKey | optionKey | controlKey | shiftKey

    public init(carbonKeyCode: Int, carbonModifiers: Int) {
        self.carbonKeyCode = carbonKeyCode
        self.carbonModifiers = carbonModifiers & Self.allModifiers
    }

    /// 从按键事件构建快捷键
    public init?(keyCode: Int, modifierFlags: NSEvent.ModifierFlags) {
        let flags = modifierFlags.intersection([.command, .option, .control, .shift])
        let hasModifier = !flags.isDisjoint(with: [.command, .option, .control])
        guard hasModifier || Self.isFunctionKey(keyCode) else { return nil }
        self.init(carbonKeyCode: keyCode, carbonModifiers: Self.carbonModifiers(from: flags))
    }

    public var modifierFlags: NSEvent.ModifierFlags {
        Self.modifierFlags(from: carbonModifiers)
    }

    /// 获取修饰符和键位组成的字符数组（按 ⌃⌥⇧⌘ + 按键 顺序）
    @MainActor
    public var keycaps: [String] {
        Self.modifierSymbols(from: modifierFlags) + [keyGlyph]
    }

    public var displayString: String {
        MainActor.assumeIsolated {
            keycaps.joined()
        }
    }

    public static func modifierFlags(from carbonModifiers: Int) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & controlKey != 0 { flags.insert(.control) }
        if carbonModifiers & optionKey != 0 { flags.insert(.option) }
        if carbonModifiers & shiftKey != 0 { flags.insert(.shift) }
        if carbonModifiers & cmdKey != 0 { flags.insert(.command) }
        return flags
    }

    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var carbon = 0
        if flags.contains(.control) { carbon |= controlKey }
        if flags.contains(.option) { carbon |= optionKey }
        if flags.contains(.shift) { carbon |= shiftKey }
        if flags.contains(.command) { carbon |= cmdKey }
        return carbon
    }

    public static func modifierSymbols(from flags: NSEvent.ModifierFlags) -> [String] {
        var symbols: [String] = []
        if flags.contains(.control) { symbols.append("⌃") }
        if flags.contains(.option) { symbols.append("⌥") }
        if flags.contains(.shift) { symbols.append("⇧") }
        if flags.contains(.command) { symbols.append("⌘") }
        return symbols
    }

    public static func isFunctionKey(_ keyCode: Int) -> Bool {
        functionKeyNames[keyCode] != nil
    }

    // MARK: - 按键字符

    @MainActor
    private var keyGlyph: String {
        if let special = Self.specialKeyGlyphs[carbonKeyCode] { return special }
        if let name = Self.functionKeyNames[carbonKeyCode] { return name }
        return ASCIIKeyboardLayout.character(for: carbonKeyCode)?.uppercased() ?? "?"
    }

    private static let specialKeyGlyphs: [Int: String] = [
        kVK_Return: "↵",
        kVK_ANSI_KeypadEnter: "⌤",
        kVK_Tab: "⇥",
        kVK_Space: "Space",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_Home: "↖",
        kVK_End: "↘",
        kVK_PageUp: "⇞",
        kVK_PageDown: "⇟",
        kVK_Help: "?"
    ]

    private static let functionKeyNames: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
        kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20"
    ]
}
