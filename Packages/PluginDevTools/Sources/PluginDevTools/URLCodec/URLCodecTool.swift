// URLCodecTool.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// URL 编解码工具
///
/// 参考 Fasty url-codec 布局：
/// 工具栏（模式切换 + 操作按钮）→ 编辑区 → 状态栏
struct URLCodecTool: DevTool {
    let id = "url"
    let name = "URL 编解码"
    let icon = "link"
    let keywords = ["url", "编码", "解码", "urlencode", "urldecode", "链接"]
    let description = "URL 百分号编码和解码"

    func makeView() -> AnyView {
        AnyView(URLCodecView())
    }
}

struct URLCodecView: View {
    @State private var input = ""
    @State private var output = ""
    @State private var mode: Mode = .encode

    enum Mode: String, CaseIterable {
        case encode = "编码"
        case decode = "解码"
    }

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack(spacing: DesignTokens.Spacing.sm) {
                Picker("模式", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }.pickerStyle(.segmented).frame(width: 140)

                Button {
                    transform()
                } label: {
                    Label(mode.rawValue, systemImage: "arrow.right")
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
                    input = ""; output = ""
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
                    Text(mode == .encode ? "原文" : "已编码")
                        .font(.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, DesignTokens.Spacing.xs)
                    TextEditor(text: $input)
                        .font(DesignTokens.Typography.code)
                        .scrollContentBackground(.hidden)
                }
                .frame(minWidth: 200)

                VStack(alignment: .leading, spacing: 0) {
                    Text(mode == .encode ? "已编码" : "原文")
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
                if !output.isEmpty {
                    Text("已\(mode.rawValue)")
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
        guard !input.isEmpty else { output = ""; return }
        if mode == .encode {
            output = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
        } else {
            output = input.removingPercentEncoding ?? input
        }
    }

    private func swap() {
        let temp = input
        input = output
        output = temp
        mode = mode == .encode ? .decode : .encode
    }
}
