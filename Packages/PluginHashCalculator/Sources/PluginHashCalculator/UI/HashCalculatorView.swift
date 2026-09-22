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
    @State private var copiedAlgorithm: HashCalculatorLogic.Algorithm?

    var body: some View {
        VStack(spacing: 0) {
            // 输入区
            TextEditor(text: $buffer.text)
                .font(DesignTokens.Typography.code)
                .scrollContentBackground(.hidden)
                .frame(height: 100)
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

            Divider().opacity(0.3).padding(.horizontal, DesignTokens.Spacing.lg)

            // 结果列表
            if !results.isEmpty {
                HStack {
                    Text("计算结果")
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
                                    .frame(width: 55, alignment: .leading)

                                Text(item.value)
                                    .font(DesignTokens.Typography.code)
                                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                                    .textSelection(.enabled)
                                    .lineLimit(1)

                                Spacer()

                                Button {
                                    EventBus.shared.post(CopyToClipboardEvent(text: item.value))
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
    }

    private func calculate() {
        results = HashCalculatorLogic.digests(of: input)
    }

    private func copyAll() {
        let text = results.map { "\($0.algorithm.rawValue): \($0.value)" }.joined(separator: "\n")
        EventBus.shared.post(CopyToClipboardEvent(text: text))
    }
}
