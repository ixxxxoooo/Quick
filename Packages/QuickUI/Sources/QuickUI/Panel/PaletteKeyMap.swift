// PaletteKeyMap.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Carbon.HIToolbox

/// 主搜索列表的「导航类」按键翻译
///
/// 纯函数、不碰窗口：`PalettePanel.sendEvent` 把按键三元组丢进来，拿回一个语义动作，
/// 这样键位表可以脱离 `NSPanel` 单测。
///
/// 键位取舍：
/// - **PageUp / PageDown** 在输入框里没有别的用途，任何时候都翻页。
/// - **Home / End** 在输入框里是「光标到行首 / 行尾」，只有输入框为空时才当成跳首尾
///   （`requiresEmptyField`），否则会抢走用户编辑文本的光标键。
/// - **⌘↑ / ⌘↓** 是任何时候的跳首尾（macOS 里「到文档开头 / 结尾」的惯用键位）。
/// - **⌘1…⌘9** 直达第 n 个结果（Alfred / Raycast 同款）。
enum PaletteKeyMap {

    enum Navigation: Equatable {
        /// 翻页：`-1` 上翻、`+1` 下翻
        case page(Int)
        /// 跳首 / 末；`requiresEmptyField` 为真时只在输入框为空才生效
        case jump(PaletteSelection.JumpTarget, requiresEmptyField: Bool)
        /// 直达第 n 个结果（从 1 开始）
        case quickSelect(Int)
    }

    /// 翻译一次按键；不是导航键返回 `nil`
    ///
    /// - Parameters:
    ///   - keyCode: 虚拟键码
    ///   - modifiers: 修饰键（只看 ⌘ ⌥ ⌃ ⇧，忽略 Caps Lock / fn / 数字键盘位）
    ///   - characters: `charactersIgnoringModifiers`
    static func navigation(
        keyCode: Int, modifiers: NSEvent.ModifierFlags, characters: String?
    ) -> Navigation? {
        let relevant = modifiers.intersection([.command, .option, .control, .shift])

        if relevant.isEmpty {
            switch keyCode {
            case kVK_PageUp: return .page(-1)
            case kVK_PageDown: return .page(1)
            case kVK_Home: return .jump(.first, requiresEmptyField: true)
            case kVK_End: return .jump(.last, requiresEmptyField: true)
            default: return nil
            }
        }

        guard relevant == [.command] else { return nil }

        switch keyCode {
        case kVK_UpArrow: return .jump(.first, requiresEmptyField: false)
        case kVK_DownArrow: return .jump(.last, requiresEmptyField: false)
        default: break
        }

        if let characters, characters.count == 1, let digit = Int(characters),
            (1...PaletteSelection.quickSelectLimit).contains(digit)
        {
            return .quickSelect(digit)
        }
        return nil
    }
}
