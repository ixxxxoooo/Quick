// Base64CodecView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct Base64CodecView: View {

    /// 模式类型归 Model 所有（视图与逻辑共用同一份定义，避免两处各写一个）
    private typealias Mode = Base64CodecLogic.Mode

    /// 输入文本归插件所有：主面板与分离窗口共享同一份，分离时内容自然带过去
    @Bindable var buffer: TextBuffer

    private var input: String {
        get { buffer.text }
        nonmutating set { buffer.text = newValue }
    }
    @State private var output = ""
    @State private var mode: Mode = .encode
    @State private var errorMessage: String?

    /// 编解码规则与设置页共用同一个键：那边改了这边立即生效
    @AppStorage(PluginSettingKey.Base64Codec.urlSafe) private var urlSafe = false
    @AppStorage(PluginSettingKey.Base64Codec.wrapLines) private var wrapLines = false

    private var options: Base64CodecLogic.Options {
        .init(isURLSafe: urlSafe, wrapsLines: wrapLines)
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
                        .font(DesignTokens.Typography.keyCap).foregroundStyle(
                            DesignTokens.Colors.textTertiary
                        )
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, DesignTokens.Spacing.xs)
                    TextEditor(text: $buffer.text)
                        .font(DesignTokens.Typography.code)
                        .scrollContentBackground(.hidden)
                }
                .frame(minWidth: 200)

                VStack(alignment: .leading, spacing: 0) {
                    Text(mode == .encode ? "Base64" : "原文")
                        .font(DesignTokens.Typography.keyCap).foregroundStyle(
                            DesignTokens.Colors.textTertiary
                        )
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
                        .font(DesignTokens.Typography.keyCap).foregroundStyle(
                            DesignTokens.Colors.textTertiary)
                }
                if let error = errorMessage {
                    Text(error)
                        .font(DesignTokens.Typography.keyCap).foregroundStyle(DesignTokens.Colors.destructive)
                } else if !output.isEmpty {
                    Text(mode == .encode ? "已编码" : "已解码")
                        .font(DesignTokens.Typography.keyCap).foregroundStyle(DesignTokens.Colors.success)
                }
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.xs)
        }
        .onChange(of: input) { _, _ in transform() }
        .onChange(of: urlSafe) { _, _ in transform() }
        .onChange(of: wrapLines) { _, _ in transform() }
    }

    private func transform() {
        guard !input.isEmpty else { output = ""; errorMessage = nil; return }
        do {
            output =
                mode == .encode
                ? try Base64CodecLogic.encode(input, options: options)
                : try Base64CodecLogic.decode(input, options: options)
            errorMessage = nil
        } catch {
            output = ""
            errorMessage = "无效的 Base64"
        }
    }

    private func swap() {
        let temp = input
        input = output
        output = temp
        mode = mode == .encode ? .decode : .encode
    }
}
