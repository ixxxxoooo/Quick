// HashCalculatorTool.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import CryptoKit
import QuickCore
import QuickUI
import SwiftUI

/// Hash 计算器
///
/// 参考 Fasty hash-calculator 布局：
/// 输入区 → 结果列表（自动计算）→ 空状态提示
struct HashCalculatorTool: DevTool {
    let id = "hash"
    let name = "Hash 计算器"
    let icon = "number.square"
    let keywords = ["hash", "md5", "sha", "sha256", "哈希", "散列", "摘要"]
    let description = "计算 MD5 / SHA1 / SHA256 / SHA512 哈希值"

    func makeView() -> AnyView {
        AnyView(HashCalculatorView())
    }
}

struct HashCalculatorView: View {
    @State private var input = ""
    @State private var results: [(algorithm: String, value: String)] = []
    @State private var copiedAlgorithm: String?

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
                                Text(item.algorithm)
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
        guard let data = input.data(using: .utf8), !input.isEmpty else { results = []; return }
        results = [
            ("MD5", Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()),
            ("SHA1", Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()),
            ("SHA256", SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()),
            ("SHA512", SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined())
        ]
    }

    private func copyAll() {
        let text = results.map { "\($0.algorithm): \($0.value)" }.joined(separator: "\n")
        EventBus.shared.post(CopyToClipboardEvent(text: text))
    }
}
