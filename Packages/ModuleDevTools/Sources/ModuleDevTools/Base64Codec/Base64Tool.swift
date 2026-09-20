// Base64Tool.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// Base64 编解码工具
///
/// 参考 Fasty base64-codec 布局：
/// 工具栏（模式切换 + 操作按钮）→ 编辑区 → 状态栏
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
    @State private var mode: Mode = .encode
    @State private var errorMessage: String?

    enum Mode: String, CaseIterable {
        case encode = "编码"
        case decode = "解码"
    }

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack(spacing: DesignTokens.Spacing.sm) {
                // 模式切换
                Picker("模式", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }.pickerStyle(.segmented).frame(width: 140)

                Button {
                    transform()
                } label: {
                    Label(mode == .encode ? "编码" : "解码", systemImage: "arrow.right")
                }.buttonStyle(.borderedProminent).controlSize(.small)

                Button {
                    swap()
                } label: {
                    Label("互换", systemImage: "arrow.left.arrow.right")
                }.buttonStyle(.bordered).controlSize(.small)

                Button {
                    EventBus.shared.post(CopyToClipboardEvent(text: output))
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }.buttonStyle(.bordered).controlSize(.small)

                Button {
                    input = ""; output = ""; errorMessage = nil
                } label: {
                    Label("清空", systemImage: "trash")
                }.buttonStyle(.bordered).controlSize(.small)

                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)

            Divider().opacity(0.3)

            // 编辑区
            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(mode == .encode ? "原文" : "Base64")
                        .font(.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, DesignTokens.Spacing.xs)
                    TextEditor(text: $input)
                        .font(DesignTokens.Typography.code)
                        .scrollContentBackground(.hidden)
                }
                .frame(minWidth: 200)

                VStack(alignment: .leading, spacing: 0) {
                    Text(mode == .encode ? "Base64" : "原文")
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
                if !input.isEmpty {
                    Text("\(input.utf8.count) B")
                        .font(.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                if let error = errorMessage {
                    Text(error)
                        .font(.caption).foregroundStyle(DesignTokens.Colors.destructive)
                } else if !output.isEmpty {
                    Text(mode == .encode ? "已编码" : "已解码")
                        .font(.caption).foregroundStyle(.green)
                }
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.xs)
        }
        .onChange(of: input) { _, _ in transform() }
    }

    private func transform() {
        guard !input.isEmpty else { output = ""; errorMessage = nil; return }
        if mode == .encode {
            guard let data = input.data(using: .utf8) else { return }
            output = data.base64EncodedString()
            errorMessage = nil
        } else {
            guard let data = Data(base64Encoded: input),
                let decoded = String(data: data, encoding: .utf8)
            else {
                output = ""
                errorMessage = "无效的 Base64"
                return
            }
            output = decoded
            errorMessage = nil
        }
    }

    private func swap() {
        let temp = input
        input = output
        output = temp
        mode = mode == .encode ? .decode : .encode
    }
}
