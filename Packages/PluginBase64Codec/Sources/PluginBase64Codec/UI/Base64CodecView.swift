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
    /// 大输入走防抖 + 后台计算，小输入同步算（见 `Debouncer`）
    @State private var debouncer = Debouncer()

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
                }.pickerStyle(.segmented).frame(width: DesignTokens.Size.segmentedControl)

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

            Divider().opacity(DesignTokens.Opacity.divider)

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
                .frame(minWidth: DesignTokens.Size.editorMinWidth)

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
                .frame(minWidth: DesignTokens.Size.editorMinWidth)
            }

            Divider().opacity(DesignTokens.Opacity.divider)

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
        .onChange(of: mode) { _, _ in transform() }
        .onDisappear { debouncer.cancel() }
    }

    private func transform() {
        guard !input.isEmpty else {
            debouncer.cancel()
            output = ""
            errorMessage = nil
            return
        }
        // 把要用的值拷成局部常量：计算在后台线程跑，闭包不能碰视图状态
        let text = input
        let currentMode = mode
        let currentOptions = options
        debouncer.schedule(
            weight: text.utf8.count,
            work: {
                Result {
                    currentMode == .encode
                        ? try Base64CodecLogic.encode(text, options: currentOptions)
                        : try Base64CodecLogic.decode(text, options: currentOptions)
                }
            },
            apply: { result in
                switch result {
                case .success(let value):
                    output = value
                    errorMessage = nil
                case .failure:
                    output = ""
                    errorMessage = "无效的 Base64"
                }
            })
    }

    private func swap() {
        let temp = input
        input = output
        output = temp
        mode = mode == .encode ? .decode : .encode
    }
}
