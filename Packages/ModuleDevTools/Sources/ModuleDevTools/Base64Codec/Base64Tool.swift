// Base64Tool.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// Base64 编解码工具
struct Base64Tool: DevTool {
    let id = "base64"
    let name = "Base64 编解码"
    let icon = "lock.rectangle"
    let keywords = ["base64", "编码", "解码", "encode", "decode"]
    let description = "Base64 编码和解码"

    func makeView() -> AnyView {
        AnyView(Base64View())
    }
}

struct Base64View: View {
    @State private var input = ""
    @State private var output = ""

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            HStack {
                Text("Base64 编解码")
                    .font(DesignTokens.Typography.panelTitle)
                Spacer()
                Button("编码") { encode() }.buttonStyle(.borderedProminent)
                Button("解码") { decode() }.buttonStyle(.bordered)
                Button("复制") {
                    EventBus.shared.post(CopyToClipboardEvent(text: output))
                }.buttonStyle(.bordered)
            }

            HSplitView {
                TextEditor(text: $input)
                    .font(DesignTokens.Typography.code)
                    .scrollContentBackground(.hidden)
                    .frame(minWidth: 200)
                TextEditor(text: .constant(output))
                    .font(DesignTokens.Typography.code)
                    .scrollContentBackground(.hidden)
                    .frame(minWidth: 200)
            }
        }
        .padding(DesignTokens.Spacing.xl)
    }

    private func encode() {
        guard let data = input.data(using: .utf8) else { return }
        output = data.base64EncodedString()
    }

    private func decode() {
        guard let data = Data(base64Encoded: input),
            let decoded = String(data: data, encoding: .utf8)
        else {
            output = "无效的 Base64 字符串"
            return
        }
        output = decoded
    }
}
