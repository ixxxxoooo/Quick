// SelectionCapture.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import ApplicationServices
import CoreGraphics

/// 通过合成 ⌘C 抓取当前选区文本（对齐 Fasty `get_selected_text`）
///
/// 流程：备份剪贴板 → 清空 → ⌘C → 短轮询 → 有新文本则返回并**保留**在剪贴板
/// （超级面板读剪贴板做上下文）；无新内容则恢复备份。
public enum SelectionCapture {

    /// ANSI C 虚拟键码
    private static let cKeyCode: CGKeyCode = 0x08

    /// 尝试抓取选区；失败或无选区返回 `nil`
    /// - Parameter timeoutMilliseconds: 轮询上限（默认 70ms，与 Fasty 一致）
    public static func captureText(timeoutMilliseconds: Int = 70) -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let board = NSPasteboard.general
        let saved = board.string(forType: .string)
        board.clearContents()

        guard synthesizeCommandC() else {
            restore(saved, onto: board)
            return nil
        }

        let deadline = Date().addingTimeInterval(Double(timeoutMilliseconds) / 1000)
        var selected = ""
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
            if let text = board.string(forType: .string), !text.isEmpty {
                selected = text
                break
            }
        }

        if selected.isEmpty {
            restore(saved, onto: board)
            return nil
        }
        // 有选区：留给超级面板读剪贴板，不恢复旧内容
        return selected
    }

    private static func synthesizeCommandC() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: false)
        else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private static func restore(_ text: String?, onto board: NSPasteboard) {
        board.clearContents()
        if let text, !text.isEmpty {
            board.setString(text, forType: .string)
        }
    }
}
