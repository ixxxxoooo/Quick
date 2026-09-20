// ASCIIKeyboardLayout.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// ASCII 键盘布局键位转换工具
///
/// 将 Carbon keyCode / NSEvent 映射到对应的 ASCII 字符（如 "A", "Space", "↵" 等），
/// 确保在不同键盘布局下快捷键符号显示正确。
public enum ASCIIKeyboardLayout {

    /// 获取物理按键对应的无修饰基础字符
    @MainActor
    public static func character(for keyCode: Int, modifiers: UInt32 = 0) -> String? {
        guard
            let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layoutDataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let layoutData = unsafeBitCast(layoutDataPointer, to: CFData.self)
        let keyLayout = unsafeBitCast(
            CFDataGetBytePtr(layoutData),
            to: UnsafePointer<UCKeyboardLayout>.self
        )
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)

        let error = UCKeyTranslate(
            keyLayout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            modifiers,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard error == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }

    /// 获取事件对应的字符
    @MainActor
    public static func character(for event: NSEvent) -> String? {
        character(
            for: Int(event.keyCode),
            modifiers: event.modifierFlags.contains(.command) ? UInt32(cmdKey >> 8) : 0
        )
    }
}
