// ShortcutRecorder.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import SwiftUI

/// 快捷键录制组件
///
/// 参考 Tinycast 设计：
/// - 未设置时显示 "点击录制" / "未设置" 占位
/// - 点击后进入 "按下快捷键…" 监听状态，边框高亮
/// - 按下带修饰键的按键组合（或功能键）即完成绑定并触发 `onRecord`
/// - 按 Escape 键取消录制
/// - 悬停提供清除按钮（xmark）并触发 `onClear`
public struct ShortcutRecorder: View {

    public let keycaps: [String]?
    public let onRecord: (_ keyCode: Int, _ carbonModifiers: Int) -> Void
    public let onClear: () -> Void

    @State private var isRecording = false
    @State private var isHovered = false
    @State private var eventMonitor: Any?

    public init(
        keycaps: [String]?,
        onRecord: @escaping (_ keyCode: Int, _ carbonModifiers: Int) -> Void,
        onClear: @escaping () -> Void
    ) {
        self.keycaps = keycaps
        self.onRecord = onRecord
        self.onClear = onClear
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)

        Group {
            if isRecording {
                Text("按下快捷键…")
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(Color.accentColor)
            } else if let keycaps, !keycaps.isEmpty {
                HStack(spacing: DesignTokens.Spacing.xxs) {
                    ForEach(Array(keycaps.enumerated()), id: \.offset) { _, cap in
                        Text(cap)
                            .font(DesignTokens.Typography.keyCap)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .padding(.horizontal, DesignTokens.Spacing.xs)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                            )
                    }
                }
                .frame(maxWidth: .infinity)
                .overlay(alignment: .trailing) {
                    if isHovered {
                        Button {
                            onClear()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(DesignTokens.Typography.compactIcon)
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .help("清除快捷键")
                    }
                }
            } else {
                Text("点击录制")
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(
                        isHovered ? DesignTokens.Colors.textSecondary : DesignTokens.Colors.textTertiary
                    )
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .frame(width: DesignTokens.Size.shortcutRecorder, height: 24)
        .background(shape.fill(DesignTokens.Colors.cardFill))
        .overlay(
            shape.strokeBorder(
                isRecording ? Color.accentColor : DesignTokens.Colors.cardStroke, lineWidth: 1)
        )
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture {
            if !isRecording {
                startRecording()
            }
        }
        .onHover { isHovered = $0 }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        isRecording = true

        // 录制期间暂停全局快捷键，否则 Carbon 会先截获按键
        ShortcutRecorderCoordinator.shared.pauseGlobalHotKeys()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            // Escape 键取消录制
            if event.type == .keyDown, Int(event.keyCode) == 53 {
                self.stopRecording()
                return nil
            }

            // 忽略纯修饰键变化（flagsChanged），等待实际按键
            guard event.type == .keyDown else { return event }

            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let hasCmdModifier = !flags.isDisjoint(with: [.command, .option, .control])

            // 功能键检测（F1~F20，keyCode 范围：96~111, 118~126）
            let kc = Int(event.keyCode)
            let isFunctionKey = (kc >= 96 && kc <= 111) || (kc >= 118 && kc <= 126)

            if hasCmdModifier || isFunctionKey {
                var carbon = 0
                if flags.contains(.control) { carbon |= 0x1000 }
                if flags.contains(.option) { carbon |= 0x0800 }
                if flags.contains(.shift) { carbon |= 0x0200 }
                if flags.contains(.command) { carbon |= 0x0100 }

                self.onRecord(Int(event.keyCode), carbon)
                self.stopRecording()
                return nil
            }

            return event
        }
    }

    private func stopRecording() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        isRecording = false

        // 恢复全局快捷键监听
        ShortcutRecorderCoordinator.shared.resumeGlobalHotKeys()
    }
}

/// 快捷键录制协调器
///
/// 在 ShortcutRecorder 录制期间暂停/恢复全局快捷键。
/// 使用引用计数支持多个录制组件同时存在。
@MainActor
public final class ShortcutRecorderCoordinator {

    public static let shared = ShortcutRecorderCoordinator()

    /// 暂停/恢复全局快捷键的回调（由 AppCore 注入）
    public var onPause: (() -> Void)?
    public var onResume: (() -> Void)?

    private var pauseCount = 0

    private init() {}

    func pauseGlobalHotKeys() {
        pauseCount += 1
        if pauseCount == 1 {
            onPause?()
        }
    }

    func resumeGlobalHotKeys() {
        pauseCount = max(0, pauseCount - 1)
        if pauseCount == 0 {
            onResume?()
        }
    }
}
