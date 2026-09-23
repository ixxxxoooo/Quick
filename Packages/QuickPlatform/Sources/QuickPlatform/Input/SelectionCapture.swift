// SelectionCapture.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import ApplicationServices
import CoreGraphics
import QuickCore

/// 通过合成 ⌘C 抓取当前选区文本（对齐 Fasty `get_selected_text`）
///
/// 流程：备份剪贴板**全部内容** → 清空 → ⌘C → 短轮询 → 无论是否抓到都**恢复备份**，抓到则返回文本。
///
/// 备份是逐个 item、逐个 type 存 data，而不是只存 string：用户剪贴板里可能是图片或文件，
/// 只备份文本会在恢复时把它们静默清掉。恢复时用 `NSPasteboardItem` 原样重建再 `writeObjects`。
///
/// **恢复剪贴板是对 Fasty 的一处有意优化。** Fasty 抓到选区后把它留在剪贴板里，
/// 于是每次右键唤出都会顶掉用户原本的剪贴板内容。选区文本已经通过返回值交给超级面板，
/// 不需要借剪贴板传这一手，所以这里恢复原内容，让唤出没有副作用。
public enum SelectionCapture {

    /// ANSI C 虚拟键码
    private static let cKeyCode: CGKeyCode = 0x08
    private static let log = QuickLog.platform

    /// 尝试抓取选区；失败或无选区返回 `nil`
    /// - Parameter timeoutMilliseconds: 轮询上限（默认 70ms，与 Fasty 一致）
    public static func captureText(timeoutMilliseconds: Int = 70) async -> String? {
        guard AXIsProcessTrusted() else {
            log.warning("抓取选区失败：未授予辅助功能权限")
            return nil
        }

        let board = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: board)
        board.clearContents()

        guard synthesizeCommandC() else {
            log.error("抓取选区失败：无法合成 ⌘C 键盘事件")
            snapshot.restore(onto: board)
            return nil
        }

        let deadline = Date().addingTimeInterval(Double(timeoutMilliseconds) / 1000)
        var selected = ""
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
            if let text = board.string(forType: .string), !text.isEmpty {
                selected = text
                break
            }
        }

        // 无论抓到没有都恢复备份：抓到的话文本已经通过返回值交出去了
        snapshot.restore(onto: board)
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
}
