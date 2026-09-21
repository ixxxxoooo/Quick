// SettingsFilterField.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 长列表上方的筛选框
///
/// 造型像搜索框而不是表单文本框：无边框、左侧放大镜、有内容时右侧出现清除按钮。
/// 参考实现里同样是这个形状，理由是它出现在「列表上方」而不是「表单里的一行」——
/// 带 bezel 的输入框在分组卡片里会显得像又一个设置项。
struct SettingsFilterField: View {

    let prompt: String
    @Binding var query: String

    /// 焦点由调用方持有，这样 ⌘F 之类的快捷键才有地方挂
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(DesignTokens.Typography.inlineIcon)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            // prompt + labelsHidden：否则表单会把占位符当成左侧的字段名
            TextField("", text: $query, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .labelsHidden()
                .focused(isFocused)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignTokens.Typography.inlineIcon)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除筛选")
            }
        }
        // 无边框输入框只有字形本身可点，整行都要能唤起焦点
        .contentShape(.rect)
        .onTapGesture { isFocused.wrappedValue = true }
    }
}
