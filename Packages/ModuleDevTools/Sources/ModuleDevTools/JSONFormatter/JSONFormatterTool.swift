// JSONFormatterTool.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// JSON 格式化工具
///
/// 参考 Fasty json-formatter 布局：
/// 工具栏（格式化/压缩/复制/清空 + 缩进选择）→ 编辑区 → 状态栏
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
    @State private var indent = 2
    @State private var nodeCount = 0

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack(spacing: DesignTokens.Spacing.sm) {
                Button {
                    format()
                } label: {
                    Label("格式化", systemImage: "text.alignleft")
                }.buttonStyle(.borderedProminent).controlSize(.small)

                Button {
                    compact()
                } label: {
                    Label("压缩", systemImage: "arrow.down.right.and.arrow.up.left")
                }.buttonStyle(.bordered).controlSize(.small)

                Button {
                    EventBus.shared.post(CopyToClipboardEvent(text: output.isEmpty ? input : output))
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }.buttonStyle(.bordered).controlSize(.small)

                Button {
                    input = ""; output = ""; errorMessage = nil; nodeCount = 0
                } label: {
                    Label("清空", systemImage: "trash")
                }.buttonStyle(.bordered).controlSize(.small)

                Spacer()

                Picker("缩进", selection: $indent) {
                    Text("2 空格").tag(2)
                    Text("4 空格").tag(4)
                }.pickerStyle(.segmented).frame(width: 140)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)

            Divider().opacity(0.3)

            // 编辑区（左右双栏）
            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("输入")
                        .font(.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, DesignTokens.Spacing.xs)
                    TextEditor(text: $input)
                        .font(DesignTokens.Typography.code)
                        .scrollContentBackground(.hidden)
                }
                .frame(minWidth: 200)

                VStack(alignment: .leading, spacing: 0) {
                    Text("输出")
                        .font(.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, DesignTokens.Spacing.xs)
                    TextEditor(text: .constant(output))
                        .font(DesignTokens.Typography.code)
                        .scrollContentBackground(.hidden)
                }
                .frame(minWidth: 200)
            }

            Divider().opacity(0.3)

            // 状态栏
            HStack(spacing: DesignTokens.Spacing.lg) {
                if nodeCount > 0 {
                    Text("\(nodeCount) 个节点")
                        .font(.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                if !input.isEmpty {
                    Text(byteSize(input))
                        .font(.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                if let error = errorMessage {
                    Text(error)
                        .font(.caption).foregroundStyle(DesignTokens.Colors.destructive)
                } else if !output.isEmpty {
                    Text("有效 JSON")
                        .font(.caption).foregroundStyle(.green)
                }
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.xs)
        }
        .onChange(of: input) { _, _ in autoFormat() }
    }

    private func autoFormat() {
        guard !input.isEmpty else {
            output = ""; errorMessage = nil; nodeCount = 0; return
        }
        format()
    }

    private func format() {
        guard let data = input.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data)
        else {
            errorMessage = "无效的 JSON"; nodeCount = 0; return
        }
        errorMessage = nil
        nodeCount = countNodes(json)
        let options: JSONSerialization.WritingOptions =
            indent == 4
            ? [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
            : [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
        if let formatted = try? JSONSerialization.data(withJSONObject: json, options: options) {
            var text = String(data: formatted, encoding: .utf8) ?? ""
            if indent == 4 {
                // JSONSerialization 默认 2 空格，手动替换为 4
                text = text.replacingOccurrences(
                    of: "  ", with: "    ", options: [], range: nil)
            }
            output = text
        }
    }

    private func compact() {
        guard let data = input.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data),
            let compacted = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        else {
            errorMessage = "无效的 JSON"; return
        }
        errorMessage = nil
        output = String(data: compacted, encoding: .utf8) ?? ""
    }

    private func countNodes(_ obj: Any) -> Int {
        if let dict = obj as? [String: Any] {
            return 1 + dict.values.reduce(0) { $0 + countNodes($1) }
        }
        if let arr = obj as? [Any] {
            return 1 + arr.reduce(0) { $0 + countNodes($1) }
        }
        return 1
    }

    private func byteSize(_ text: String) -> String {
        let bytes = text.utf8.count
        if bytes < 1024 { return "\(bytes) B" }
        return String(format: "%.1f KB", Double(bytes) / 1024)
    }
}
