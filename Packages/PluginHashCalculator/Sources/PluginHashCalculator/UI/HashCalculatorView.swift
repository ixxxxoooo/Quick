// HashCalculatorView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct HashCalculatorView: View {
    /// 输入文本归插件所有：主面板与分离窗口共享同一份，分离时内容自然带过去
    @Bindable var buffer: TextBuffer

    private var input: String {
        get { buffer.text }
        nonmutating set { buffer.text = newValue }
    }
    @State private var results: [(algorithm: HashCalculatorLogic.Algorithm, value: String)] = []
    /// HMAC 密钥：非空即改算 HMAC。仅存内存，不落盘、不进剪贴板历史
    @State private var hmacKey = ""
    @State private var copiedAlgorithm: HashCalculatorLogic.Algorithm?
    @AppStorage(PluginSettingKey.HashCalculator.uppercase) private var uppercase = false
    @AppStorage(PluginSettingKey.HashCalculator.autoCopy) private var autoCopy = false
    /// 自动复制的「停手」计时；每次结果变化都会取消重来
    @State private var autoCopyTask: Task<Void, Never>?
    /// 大输入走防抖 + 后台计算，小输入同步算（见 `Debouncer`）
    @State private var debouncer = Debouncer()

    var body: some View {
        VStack(spacing: 0) {
            // 输入区
            TextEditor(text: $buffer.text)
                .font(DesignTokens.Typography.code)
                .scrollContentBackground(.hidden)
                .frame(height: DesignTokens.Size.hashInputHeight)
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.top, DesignTokens.Spacing.md)
                .overlay(alignment: .topLeading) {
                    if input.isEmpty {
                        Text("输入要计算哈希的文本…")
                            .font(DesignTokens.Typography.code)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .padding(.horizontal, DesignTokens.Spacing.lg + 5)
                            .padding(.top, DesignTokens.Spacing.md + 8)
                            .allowsHitTesting(false)
                    }
                }

            // HMAC 密钥
            HStack(spacing: DesignTokens.Spacing.md) {
                Text("HMAC 密钥")
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                SecureField("留空则计算普通哈希", text: $hmacKey)
                    .textFieldStyle(.plain)
                    .font(DesignTokens.Typography.code)
                    .padding(DesignTokens.Spacing.sm)
                    .background(DesignTokens.Colors.cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.row))
                    .frame(width: DesignTokens.Size.hmacKeyFieldWidth)
                    .accessibilityLabel("HMAC 密钥")
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)

            Divider().opacity(DesignTokens.Opacity.divider).padding(.horizontal, DesignTokens.Spacing.lg)

            // 结果列表
            if !results.isEmpty {
                HStack {
                    Text(hmacKey.isEmpty ? "计算结果" : "HMAC 结果")
                        .font(DesignTokens.Typography.sectionHeader)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    Spacer()
                    Button {
                        copyAll()
                    } label: {
                        Label("全部复制", systemImage: "doc.on.doc")
                    }.buttonStyle(.bordered).controlSize(.small)
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.top, DesignTokens.Spacing.md)

                ScrollView {
                    VStack(spacing: DesignTokens.Spacing.xs) {
                        ForEach(results, id: \.algorithm) { item in
                            HStack(spacing: DesignTokens.Spacing.md) {
                                Text(item.algorithm.rawValue)
                                    .font(DesignTokens.Typography.code).fontWeight(.medium)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: DesignTokens.Size.hashLabelWidth, alignment: .leading)

                                Text(shown(item.value))
                                    .font(DesignTokens.Typography.code)
                                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                                    .textSelection(.enabled)
                                    .lineLimit(1)

                                Spacer()

                                Button {
                                    EventBus.shared.post(CopyToClipboardEvent(text: shown(item.value)))
                                    copiedAlgorithm = item.algorithm
                                    Task { @MainActor in
                                        try? await Task.sleep(for: .seconds(1.5))
                                        if copiedAlgorithm == item.algorithm { copiedAlgorithm = nil }
                                    }
                                } label: {
                                    Image(
                                        systemName: copiedAlgorithm == item.algorithm
                                            ? "checkmark" : "doc.on.doc"
                                    )
                                    .font(DesignTokens.Typography.inlineIcon)
                                    .foregroundStyle(
                                        copiedAlgorithm == item.algorithm
                                            ? DesignTokens.Colors.success : DesignTokens.Colors.textTertiary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, DesignTokens.Spacing.lg)
                            .padding(.vertical, DesignTokens.Spacing.sm)
                            .background(DesignTokens.Colors.cardFill)
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.row))
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                }
            } else if input.isEmpty {
                VStack(spacing: DesignTokens.Spacing.md) {
                    Text("输入文本后自动计算哈希值")
                        .font(DesignTokens.Typography.keyCap)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: input) { _, _ in calculate() }
        .onChange(of: hmacKey) { _, _ in calculate() }
        .onChange(of: uppercase) { _, _ in scheduleAutoCopy() }
        .onChange(of: autoCopy) { _, _ in scheduleAutoCopy() }
        .onDisappear {
            debouncer.cancel()
            autoCopyTask?.cancel()
        }
    }

    private func shown(_ value: String) -> String {
        HashCalculatorLogic.display(value, uppercase: uppercase)
    }

    private func calculate() {
        let text = input
        let key = hmacKey
        debouncer.schedule(
            weight: text.utf8.count,
            work: { HashCalculatorLogic.digests(of: text, hmacKey: key) },
            apply: {
                results = $0
                scheduleAutoCopy()
            })
    }

    /// 结果稳定一小会儿之后复制一次 SHA256；关掉设置或清空输入就不复制
    private func scheduleAutoCopy() {
        autoCopyTask?.cancel()
        guard autoCopy, !results.isEmpty else { return }
        autoCopyTask = Task { @MainActor in
            try? await Task.sleep(for: HashCalculatorLogic.autoCopyDelay)
            guard !Task.isCancelled,
                let value = HashCalculatorLogic.autoCopyValue(in: results, uppercase: uppercase)
            else { return }
            EventBus.shared.post(CopyToClipboardEvent(text: value))
        }
    }

    private func copyAll() {
        let text = results.map { "\($0.algorithm.rawValue): \(shown($0.value))" }.joined(separator: "\n")
        EventBus.shared.post(CopyToClipboardEvent(text: text))
    }
}
