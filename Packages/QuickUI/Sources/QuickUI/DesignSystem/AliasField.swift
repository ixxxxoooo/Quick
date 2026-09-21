// AliasField.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import SwiftUI

/// 别名录入组件（参考 Tinycast DesignSystem/SettingsComponents.swift 中的 AliasField）
///
/// 严格 120 × 24 pt，圆角 6 pt，内部为无边框无 label 的单行 TextField。
/// 支持按下 Enter 或失去焦点自动提交保存，非空时展示清除按钮。
public struct AliasField: View {
    public let placeholder: String
    @Binding public var text: String
    public let onChange: ((String) -> Void)?

    @FocusState private var focused: Bool

    public init(
        placeholder: String = "设置别名",
        text: Binding<String>,
        onChange: ((String) -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.onChange = onChange
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
        let promptText = Text(placeholder).foregroundStyle(DesignTokens.Colors.textTertiary)

        HStack(spacing: DesignTokens.Spacing.xs) {
            TextField("", text: $text, prompt: promptText)
                .textFieldStyle(.plain)
                .labelsHidden()
                .font(DesignTokens.Typography.keyCap)
                .focused($focused)
                .focusEffectDisabled()
                .onSubmit {
                    onChange?(text)
                }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused {
                        onChange?(text)
                    }
                }

            if !text.isEmpty {
                Button {
                    text = ""
                    onChange?("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignTokens.Typography.compactIcon)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .frame(width: DesignTokens.Size.shortcutRecorder, height: 24)
        .background(shape.fill(DesignTokens.Colors.cardFill))
        .overlay(
            shape.strokeBorder(
                focused ? Color.accentColor : DesignTokens.Colors.cardStroke, lineWidth: 1)
        )
        .clipShape(shape)
    }
}
