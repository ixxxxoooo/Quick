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
    @State private var isCopied = false

    /// 编解码规则与设置页共用同一个键：那边改了这边立即生效
    @AppStorage(PluginSettingKey.Base64Codec.urlSafe) private var urlSafe = false
    @AppStorage(PluginSettingKey.Base64Codec.wrapLines) private var wrapLines = false

    private var options: Base64CodecLogic.Options {
        .init(isURLSafe: urlSafe, wrapsLines: wrapLines)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack(spacing: DesignTokens.Spacing.md) {
                // 模式切换
                Picker("模式", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: DesignTokens.Size.segmentedControl)

                Toggle("URL-Safe", isOn: $urlSafe)
                    .controlSize(.small)
                    .help("使用 -_ 替代 +/ 并省略尾部 = 填充")

                Toggle("折行", isOn: $wrapLines)
                    .controlSize(.small)
                    .help("编码结果每 64 个字符自动换行")

                Spacer()

                Button {
                    swap()
                } label: {
                    Label("互换", systemImage: "arrow.left.arrow.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(output.isEmpty)
                .help("将右侧转换结果移入左侧并切换编解码模式")

                Button {
                    copyOutput()
                } label: {
                    Label(
                        isCopied ? "已复制" : "复制",
                        systemImage: isCopied ? "checkmark" : "doc.on.doc"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(output.isEmpty)

                Button {
                    clear()
                } label: {
                    Label("清空", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(input.isEmpty && output.isEmpty)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)

            Divider().opacity(0.3)

            // 编辑区
            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(mode == .encode ? "原文" : "Base64")
                            .font(DesignTokens.Typography.keyCap)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        Spacer()
                        if !input.isEmpty {
                            Text("\(input.utf8.count) B")
                                .font(DesignTokens.Typography.compactKeyCap)
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.top, DesignTokens.Spacing.xs)

                    TextEditor(text: $buffer.text)
                        .font(DesignTokens.Typography.code)
                        .scrollContentBackground(.hidden)
                        .overlay(alignment: .topLeading) {
                            if input.isEmpty {
                                Text(mode == .encode ? "输入或粘贴要编码的文本…" : "输入或粘贴要解码的 Base64…")
                                    .font(DesignTokens.Typography.code)
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                                    .padding(.horizontal, DesignTokens.Spacing.sm)
                                    .padding(.top, DesignTokens.Spacing.xs)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                .frame(minWidth: DesignTokens.Size.editorMinWidth)

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(mode == .encode ? "Base64" : "原文")
                            .font(DesignTokens.Typography.keyCap)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        Spacer()
                        if !output.isEmpty {
                            Text("\(output.utf8.count) B")
                                .font(DesignTokens.Typography.compactKeyCap)
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.top, DesignTokens.Spacing.xs)

                    TextEditor(text: .constant(output))
                        .font(DesignTokens.Typography.code)
                        .scrollContentBackground(.hidden)
                        .overlay(alignment: .topLeading) {
                            if output.isEmpty {
                                Text(errorMessage ?? "编解码结果将实时显示在这里")
                                    .font(DesignTokens.Typography.code)
                                    .foregroundStyle(
                                        errorMessage == nil
                                            ? DesignTokens.Colors.textTertiary
                                            : DesignTokens.Colors.destructive
                                    )
                                    .padding(.horizontal, DesignTokens.Spacing.sm)
                                    .padding(.top, DesignTokens.Spacing.xs)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                .frame(minWidth: DesignTokens.Size.editorMinWidth)
            }

            Divider().opacity(0.3)

            // 状态栏
            HStack(spacing: DesignTokens.Spacing.lg) {
                if !input.isEmpty {
                    Text(
                        output.isEmpty
                            ? "\(input.utf8.count) B"
                            : "\(input.utf8.count) B → \(output.utf8.count) B"
                    )
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                if let error = errorMessage {
                    Text(error)
                        .font(DesignTokens.Typography.keyCap)
                        .foregroundStyle(DesignTokens.Colors.destructive)
                } else if !output.isEmpty {
                    Text(mode == .encode ? "已编码" : "已解码")
                        .font(DesignTokens.Typography.keyCap)
                        .foregroundStyle(DesignTokens.Colors.success)
                }
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.xs)
        }
        .onAppear { transform() }
        .onChange(of: input) { _, _ in transform() }
        .onChange(of: mode) { _, _ in transform() }
        .onChange(of: urlSafe) { _, _ in transform() }
        .onChange(of: wrapLines) { _, _ in transform() }
    }

    private func transform() {
        guard !input.isEmpty else {
            output = ""
            errorMessage = nil
            return
        }
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
        let nextInput = output
        guard !nextInput.isEmpty else { return }
        mode = mode == .encode ? .decode : .encode
        input = nextInput
        transform()
    }

    private func copyOutput() {
        guard !output.isEmpty else { return }
        EventBus.shared.post(CopyToClipboardEvent(text: output))
        isCopied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            isCopied = false
        }
    }

    private func clear() {
        input = ""
        output = ""
        errorMessage = nil
    }
}
