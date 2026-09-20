// JSONFormatterView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct JSONFormatterView: View {
    @State private var input = ""
    @State private var output = ""
    @State private var errorMessage: String?
    /// 缩进风格持久化：设置页里的「JSON 缩进」改的就是它
    @AppStorage(PluginSettingKey.JSONFormatter.indent) private var indent = 2
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
                    Text(JSONFormatterLogic.byteSize(input))
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
        guard let result = try? JSONFormatterLogic.prettyPrint(input, indent: indent) else {
            errorMessage = "无效的 JSON"; nodeCount = 0; return
        }
        errorMessage = nil
        nodeCount = result.nodeCount
        output = result.text
    }

    private func compact() {
        guard let text = try? JSONFormatterLogic.minify(input) else {
            errorMessage = "无效的 JSON"; return
        }
        errorMessage = nil
        output = text
    }
}
