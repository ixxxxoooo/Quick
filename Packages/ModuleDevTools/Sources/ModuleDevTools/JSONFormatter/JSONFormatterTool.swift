// JSONFormatterTool.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// JSON 格式化工具
struct JSONFormatterTool: DevTool {
    let id = "json"
    let name = "JSON 格式化"
    let icon = "curlybraces"
    let keywords = ["json", "格式化", "美化", "json formatter", "json格式化"]
    let description = "格式化/压缩 JSON，语法高亮"

    func makeView() -> AnyView {
        AnyView(JSONFormatterView())
    }
}

struct JSONFormatterView: View {
    @State private var input = ""
    @State private var output = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            HStack {
                Text("JSON 格式化")
                    .font(DesignTokens.Typography.panelTitle)
                Spacer()
                Button("格式化") { format() }
                    .buttonStyle(.borderedProminent)
                Button("压缩") { compact() }
                    .buttonStyle(.bordered)
                Button("复制") {
                    EventBus.shared.post(CopyToClipboardEvent(text: output))
                }
                .buttonStyle(.bordered)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.destructive)
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

    private func format() {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let formatted = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        else {
            errorMessage = "无效的 JSON"
            return
        }
        errorMessage = nil
        output = String(data: formatted, encoding: .utf8) ?? ""
    }

    private func compact() {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let compacted = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        else {
            errorMessage = "无效的 JSON"
            return
        }
        errorMessage = nil
        output = String(data: compacted, encoding: .utf8) ?? ""
    }
}
