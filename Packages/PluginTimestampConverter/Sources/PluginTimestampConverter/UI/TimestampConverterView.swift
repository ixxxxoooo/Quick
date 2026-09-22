// TimestampConverterView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Combine
import QuickCore
import QuickUI
import SwiftUI

struct TimestampConverterView: View {
    /// 输入文本归插件所有：主面板与分离窗口共享同一份，分离时内容自然带过去
    @Bindable var buffer: TextBuffer

    private var input: String {
        get { buffer.text }
        nonmutating set { buffer.text = newValue }
    }
    @State private var results: [TimestampConverterLogic.Row] = []
    @State private var inputType: TimestampConverterLogic.InputType = .empty
    @State private var now = Date()
    @State private var copiedKey: String?

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = .current
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // 输入区
            HStack(spacing: DesignTokens.Spacing.md) {
                TextField("输入时间戳或日期…", text: $buffer.text)
                    .textFieldStyle(.plain)
                    .font(DesignTokens.Typography.code)
                    .padding(DesignTokens.Spacing.md)
                    .background(DesignTokens.Colors.cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))

                if inputType != .empty {
                    Text(inputType == .timestamp ? "时间戳" : "日期")
                        .font(DesignTokens.Typography.keyCap)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.keyCap))
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.md)

            Divider().opacity(0.3).padding(.horizontal, DesignTokens.Spacing.lg)

            // 结果卡片
            if !results.isEmpty {
                ScrollView {
                    VStack(spacing: DesignTokens.Spacing.xs) {
                        ForEach(results, id: \.key) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.label)
                                        .font(DesignTokens.Typography.keyCap)
                                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                                    Text(item.value)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                                        .textSelection(.enabled)
                                }
                                Spacer()
                                Button {
                                    EventBus.shared.post(CopyToClipboardEvent(text: item.value))
                                    copiedKey = item.key
                                    Task { @MainActor in
                                        try? await Task.sleep(for: .seconds(1.5))
                                        if copiedKey == item.key { copiedKey = nil }
                                    }
                                } label: {
                                    Image(
                                        systemName: copiedKey == item.key ? "checkmark" : "doc.on.doc"
                                    )
                                    .font(DesignTokens.Typography.inlineIcon)
                                    .foregroundStyle(
                                        copiedKey == item.key
                                            ? DesignTokens.Colors.success : DesignTokens.Colors.textTertiary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(DesignTokens.Spacing.md)
                            .background(DesignTokens.Colors.cardFill)
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                }
            } else if !input.isEmpty {
                Text("无法识别的时间格式")
                    .font(DesignTokens.Typography.keyCap).foregroundStyle(DesignTokens.Colors.destructive)
                    .padding(DesignTokens.Spacing.lg)
            } else {
                VStack(spacing: DesignTokens.Spacing.md) {
                    Text("输入时间戳或日期后自动转换")
                        .font(DesignTokens.Typography.keyCap)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer(minLength: 0)

            Divider().opacity(0.3)

            // 底部当前时间
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "clock")
                    .font(DesignTokens.Typography.compactIcon)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text("当前时间")
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text(dateFormatter.string(from: now))
                    .font(DesignTokens.Typography.code)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Spacer()
                Button {
                    input = TimestampConverterLogic.currentTimestamp(now: Date())
                } label: {
                    Label("填入当前", systemImage: "arrow.down.to.line")
                }.buttonStyle(.bordered).controlSize(.mini)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)
        }
        .onChange(of: input) { _, newVal in convert(newVal) }
        .onReceive(timer) { now = $0 }
    }

    /// 转换逻辑整体在模型层，视图只把结果搬进 `@State`
    private func convert(_ text: String) {
        let conversion = TimestampConverterLogic.convert(text, timeZone: .current)
        results = conversion.rows
        inputType = conversion.inputType
    }
}
