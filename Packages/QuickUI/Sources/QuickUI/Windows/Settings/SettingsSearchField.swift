// SettingsSearchField.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import SwiftUI

/// 侧边栏的搜索框
///
/// 参考 Tinycast 设计：
/// - 胶囊型毛玻璃外观（`frosted(in: Capsule())`）
/// - 左侧放大镜图标
/// - 有输入时右侧显示清除按钮
struct SettingsSearchField: View {

    @Binding var query: String
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(DesignTokens.Typography.inlineIcon)
                .foregroundStyle(.secondary)

            TextField("", text: $query, prompt: Text("Search"))
                .textFieldStyle(.plain)
                .labelsHidden()
                .focused($isFocused)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignTokens.Typography.inlineIcon)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .frame(height: DesignTokens.Size.settingsSearchField)
        .background {
            Color.clear.frosted(in: Capsule())
        }
        .overlay {
            Capsule()
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
        .contentShape(.rect)
        .onTapGesture { isFocused = true }
        .accessibilityLabel("Search")
    }
}
