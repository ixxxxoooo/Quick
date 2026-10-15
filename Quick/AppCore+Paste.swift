// AppCore+Paste.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Carbon.HIToolbox
import Foundation
import QuickCore
import QuickPlatform
import QuickUI
import SwiftUI

/// 粘贴回上一个应用
///
/// 从 `AppCore.swift` 按职责拆出的扩展：状态仍然只属于 `AppCore`（唯一所有者），
/// 这里只放行为。拆文件是为了让每个文件能一次读完，不是为了拆出新的所有者。
extension AppCore {

    // MARK: - 粘贴回上一个应用

    /// 最大等待前台应用激活时长（兜底）
    static let maxPasteSettleDelay = Duration.milliseconds(120)

    /// 目标应用成为前台后再等一小段，才合成 ⌘V
    ///
    /// 目标应用刚被激活时它的 key window 可能还没就绪，⌘V 会丢，所以要留一点缓冲。
    /// 但这一段是**「目标已经在前台」之后**的纯附加延迟：原来固定 25 ms，实测占粘贴总延迟
    /// 三分之一以上，而它换来的只是「事件队列排空」，8 ms 足够。
    static let pasteSettleBuffer = Duration.milliseconds(8)

    /// 等前一个应用回到前台，再合成一次 ⌘V；没有辅助功能权限就只提示
    ///
    /// `NSRunningApplication.activate()` 是异步的：立刻发 ⌘V 会打在被切走的面板或还没回到
    /// 前台的旧应用上。所以这里轮询 `frontmostApplication`（系统没有「应用成为前台」的通知式
    /// 并发 API），**目标一成为前台就只剩 `pasteSettleBuffer` 那 8 ms**；目标始终没响应时由
    /// `maxPasteSettleDelay` 兜底，避免一直不发。
    func schedulePasteIntoPreviousApp(
        targetApp: NSRunningApplication? = nil,
        requestedAt: ContinuousClock.Instant = .now
    ) {
        let canPaste = pasteService.canSynthesize
        pendingPasteTask?.cancel()
        pendingPasteTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard canPaste else {
                // 面板已隐藏，剪贴板里已经有内容了 —— 告诉用户为什么没自动粘贴
                self.hudController.show(
                    message: "已复制，开启辅助功能权限后可自动粘贴",
                    tone: .warning
                )
                return
            }

            let start = ContinuousClock.now
            // 任务体真正开始执行时已经过去了多久。这一段是主线程在收尾上一轮事件
            // （键盘事件派发、面板隐藏后的 SwiftUI 更新），必须单独打出来 ——
            // 否则它会被算进「等待目标应用」，让人以为是在等别的应用。
            let schedulingMS = requestedAt.duration(to: start).invokeMS

            var activationMS = 0.0
            if let targetApp, !targetApp.isTerminated {
                let targetPID = targetApp.processIdentifier

                // 快速轮询等待目标应用成为 frontmostApplication
                if NSWorkspace.shared.frontmostApplication?.processIdentifier != targetPID {
                    let deadline = start + Self.maxPasteSettleDelay
                    while ContinuousClock.now < deadline {
                        if NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID {
                            break
                        }
                        try? await Task.sleep(for: .milliseconds(8))
                    }
                }
                activationMS = start.duration(to: .now).invokeMS

                // 已成为前台，再留一点让目标窗口拿到 key window
                try? await Task.sleep(for: Self.pasteSettleBuffer)
            } else {
                // 没有明确目标应用时（例如上一应用已退出或未知），使用短固定延时
                try? await Task.sleep(for: .milliseconds(40))
            }

            guard !Task.isCancelled else { return }
            let total = requestedAt.duration(to: .now).invokeMS
            self.log.notice(
                """
                准备合成 ⌘V：自收到粘贴请求起 \(total, format: .fixed(precision: 1)) ms\
                [等主线程收尾 \(schedulingMS, format: .fixed(precision: 1))，\
                等目标应用成为前台 \(activationMS, format: .fixed(precision: 1))，\
                就绪缓冲 \(Self.pasteSettleBuffer.invokeMS, format: .fixed(precision: 1))]，\
                目标应用=\(targetApp.map { "\($0.localizedName ?? "?")" } ?? "无", privacy: .public)
                """)
            self.pasteService.paste()
        }
    }

    /// 取消尚未发出的合成粘贴（再次唤出面板时调用）
    func cancelPendingPaste() {
        pendingPasteTask?.cancel()
        pendingPasteTask = nil
    }
}
