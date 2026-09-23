// SelectionCapture.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import ApplicationServices
import CoreGraphics

/// 通过合成 ⌘C 抓取当前选区文本（对齐 Fasty `get_selected_text`）
///
/// 流程：备份剪贴板 → 清空 → ⌘C → 短轮询 → 无论是否抓到都**恢复备份**，抓到则返回文本。
///
/// **恢复剪贴板是对 Fasty 的一处有意优化。** Fasty 抓到选区后把它留在剪贴板里，
/// 于是每次右键唤出都会顶掉用户原本的剪贴板内容。选区文本已经通过返回值交给超级面板，
/// 不需要借剪贴板传这一手，所以这里恢复原内容，让唤出没有副作用。
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

        // 无论抓到没有都恢复备份：抓到的话文本已经通过返回值交出去了
        restore(saved, onto: board)
        return selected.isEmpty ? nil : selected
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
