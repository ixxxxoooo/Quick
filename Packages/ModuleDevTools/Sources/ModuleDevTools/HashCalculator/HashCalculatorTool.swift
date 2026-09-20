// HashCalculatorTool.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import CryptoKit
import QuickCore
import QuickUI
import SwiftUI

/// Hash 计算器
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
    @State private var results: [(String, String)] = []

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            HStack {
                Text("Hash 计算器")
                    .font(DesignTokens.Typography.panelTitle)
                Spacer()
                Button("计算") { calculate() }.buttonStyle(.borderedProminent)
            }

            TextField("输入要计算哈希的文本…", text: $input)
                .textFieldStyle(.plain)
                .font(DesignTokens.Typography.code)
                .padding(DesignTokens.Spacing.md)
                .background(DesignTokens.Colors.cardFill)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
                .onSubmit { calculate() }

            ScrollView {
                LazyVStack(spacing: DesignTokens.Spacing.xs) {
                    ForEach(results, id: \.0) { name, value in
                        HStack {
                            Text(name)
                                .font(DesignTokens.Typography.sectionHeader)
                                .frame(width: 60, alignment: .leading)
                            Text(value)
                                .font(DesignTokens.Typography.code)
                                .textSelection(.enabled)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                EventBus.shared.post(CopyToClipboardEvent(text: value))
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        .padding(.vertical, DesignTokens.Spacing.sm)
                        .background(DesignTokens.Colors.cardFill)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.row))
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.xl)
    }

    private func calculate() {
        guard let data = input.data(using: .utf8) else { return }
        results = [
            ("MD5", Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()),
            ("SHA1", Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()),
            ("SHA256", SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()),
            ("SHA512", SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()),
        ]
    }
}
