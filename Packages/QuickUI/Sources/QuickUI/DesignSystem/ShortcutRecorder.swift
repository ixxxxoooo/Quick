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
                Text("Listening…")
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
                                .font(.system(size: 11))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .help("清除快捷键")
                    }
                }
            } else {
                Text(isHovered ? "Record" : "Record")
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
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape 键取消录制
            if Int(event.keyCode) == 53 {
                stopRecording()
                return nil
            }

            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let hasCmdModifier = !flags.isDisjoint(with: [.command, .option, .control])
            let isFn =
                (event.keyCode >= 122 && event.keyCode <= 120)
                || (event.keyCode >= 96 && event.keyCode <= 111)

            if hasCmdModifier || isFn {
                var carbon = 0
                if flags.contains(.control) { carbon |= 0x1000 }
                if flags.contains(.option) { carbon |= 0x0800 }
                if flags.contains(.shift) { carbon |= 0x0200 }
                if flags.contains(.command) { carbon |= 0x0100 }

                onRecord(Int(event.keyCode), carbon)
                stopRecording()
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
    }
}
