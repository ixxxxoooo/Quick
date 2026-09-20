// HashCalculatorView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct HashCalculatorView: View {
    @State private var input = ""
    @State private var results: [(algorithm: HashCalculatorLogic.Algorithm, value: String)] = []
    @State private var copiedAlgorithm: HashCalculatorLogic.Algorithm?

    var body: some View {
        VStack(spacing: 0) {
            // 输入区
            TextEditor(text: $input)
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
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 55, alignment: .leading)

                                Text(item.value)
                                    .font(.system(size: 11, design: .monospaced))
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
                                    .font(.system(size: 11))
                                    .foregroundStyle(
                                        copiedAlgorithm == item.algorithm
                                            ? .green : DesignTokens.Colors.textTertiary)
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
                        .font(.caption)
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
