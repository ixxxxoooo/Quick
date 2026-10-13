// CodecWorkbench.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 「编码 / 解码」类小工具共用的双栏工作台
///
/// Base64 与 URL 编解码原来各抄了一份一模一样的界面：工具栏（模式 · 转换 · 互换 · 复制 · 清空）、
/// 左右两个等宽编辑区、底部状态栏。改一处忘一处，所以收成这一个组件。
///
/// 组件只管**界面与不带逻辑的按钮**（互换、复制、清空）；真正的转换由调用方在自己的
/// `@State` 变化里触发 —— 这样 `Debouncer`、选项、错误文案仍归各插件，工作台不认识任何编码规则。
public struct CodecWorkbench: View {

    /// `true` 为编码，`false` 为解码
    @Binding private var isEncode: Bool
    @Binding private var input: String
    @Binding private var output: String
    @Binding private var error: String?

    private let plainTitle: String
    private let encodedTitle: String
    private let onTransform: () -> Void

    /// - Parameters:
    ///   - isEncode: 当前模式
    ///   - input: 输入文本（插件持有，主面板与分离窗口共享）
    ///   - output: 输出文本
    ///   - error: 上一次转换的失败原因；`nil` 表示成功
    ///   - plainTitle: 「原文」一侧的标题
    ///   - encodedTitle: 「已编码」一侧的标题
    ///   - onTransform: 点「编码 / 解码」按钮时重新转换
    public init(
        isEncode: Binding<Bool>,
        input: Binding<String>,
        output: Binding<String>,
        error: Binding<String?>,
        plainTitle: String = "原文",
        encodedTitle: String,
        onTransform: @escaping () -> Void
    ) {
        _isEncode = isEncode
        _input = input
        _output = output
        _error = error
        self.plainTitle = plainTitle
        self.encodedTitle = encodedTitle
        self.onTransform = onTransform
    }

    private var modeName: String { isEncode ? "编码" : "解码" }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(DesignTokens.Opacity.divider)
            panes
            Divider().opacity(DesignTokens.Opacity.divider)
            statusBar
        }
    }

    // MARK: - 工具栏

    private var toolbar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Picker("模式", selection: $isEncode) {
                Text("编码").tag(true)
                Text("解码").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: DesignTokens.Size.segmentedControl)

            Button(action: onTransform) {
                Label(modeName, systemImage: "arrow.right")
            }
            .buttonStyle(.borderedProminent).controlSize(.small)

            Button(action: swap) {
                Label("互换", systemImage: "arrow.left.arrow.right")
            }
            .buttonStyle(.bordered).controlSize(.small)

            Button {
                EventBus.shared.post(CopyToClipboardEvent(text: output))
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered).controlSize(.small)
            .disabled(output.isEmpty)

            Button(action: clear) {
                Label("清空", systemImage: "trash")
            }
            .buttonStyle(.bordered).controlSize(.small)

            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    // MARK: - 编辑区

    private var panes: some View {
        HSplitView {
            pane(title: isEncode ? plainTitle : encodedTitle, text: $input, isEditable: true)
            pane(title: isEncode ? encodedTitle : plainTitle, text: .constant(output), isEditable: false)
        }
    }

    private func pane(title: String, text: Binding<String>, isEditable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(DesignTokens.Typography.keyCap)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.top, DesignTokens.Spacing.xs)
            TextEditor(text: text)
                .font(DesignTokens.Typography.code)
                .scrollContentBackground(.hidden)
                .accessibilityLabel(isEditable ? "输入：\(title)" : "输出：\(title)")
        }
        .frame(minWidth: DesignTokens.Size.editorMinWidth)
    }

    // MARK: - 状态栏

    private var statusBar: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            if !input.isEmpty {
                Text("\(input.utf8.count) B")
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            if let error {
                Text(error)
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.destructive)
            } else if !output.isEmpty {
                Text("已\(modeName)")
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.success)
            }
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.xs)
    }

    // MARK: - 动作

    /// 输入输出互换并翻转模式：把结果当成下一轮的输入，往返验证最常用
    private func swap() {
        let previousInput = input
        input = output
        output = previousInput
        isEncode.toggle()
    }

    private func clear() {
        input = ""
        output = ""
        error = nil
    }
}
