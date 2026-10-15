// AIChatShortcut.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// AI 对话里的键盘动作
///
/// 键位判定放在纯函数里：`PalettePanel` 把按键三元组丢进来，拿回语义动作，
/// 这样键位表可以脱离窗口单测（与 `PaletteKeyMap` 同一思路）。
public enum AIChatShortcut: Equatable, Sendable {
    case newChat
    case previousSession
    case nextSession
    /// 删除当前会话（输入框有内容时让位给文本编辑，由控制器判断）
    case deleteSession
    case toggleSidebar
    case focusFilter
    case regenerate
    case copyLastReply
    case togglePin
    case renameSession

    /// 翻译一次按键；不是对话快捷键返回 `nil`
    ///
    /// - Parameters:
    ///   - characters: `charactersIgnoringModifiers`
    ///   - keyCode: 虚拟键码（退格键没有可打印字符，只能靠它）
    public static func resolve(
        characters: String?, keyCode: Int,
        command: Bool, shift: Bool, option: Bool, control: Bool
    ) -> AIChatShortcut? {
        guard command, !option, !control else { return nil }
        let backspaceKeyCode = 51
        if keyCode == backspaceKeyCode { return shift ? nil : .deleteSession }

        guard let key = characters?.lowercased(), key.count == 1 else { return nil }
        if shift {
            switch key {
            case "c": return .copyLastReply
            case "p": return .togglePin
            default: return nil
            }
        }
        switch key {
        case "n": return .newChat
        case "[": return .previousSession
        case "]": return .nextSession
        case "b": return .toggleSidebar
        case "f": return .focusFilter
        case "r": return .regenerate
        case "e": return .renameSession
        default: return nil
        }
    }
}
