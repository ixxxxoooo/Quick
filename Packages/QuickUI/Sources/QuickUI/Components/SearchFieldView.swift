// SearchFieldView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 统一搜索输入框组件
///
/// 面板顶部的搜索栏，包含图标和文本输入框。
/// 所有插件在面板中都复用此组件。
///
/// **键盘导航不在这里。** 上下键与回车由 `PalettePanel.sendEvent` 在 AppKit 层拦截：
/// 面板打开时焦点在这个输入框里，field editor 会先把上下键拿去移动光标、
/// 把回车当成提交，挂在 SwiftUI 这一层的 `onKeyPress` 收不到事件。
public struct SearchFieldView: View {

    /// 搜索文本（双向绑定）
    @Binding public var query: String

    /// 占位文本
    public let placeholder: String

    /// 左侧图标（SF Symbol 名称）。`nil` 表示不显示图标
    public let icon: String?

    /// 出现时是否自动取焦点。主搜索传 true；插件头部传 false（按 ⌘F 才聚焦）
    public let autoFocus: Bool

    /// 外部请求聚焦的序号：变化一次就取一次焦点
    ///
    /// 焦点在 `@FocusState` 里，外部没法直接设，只能靠这个令牌。
    public let focusTrigger: Int

    @FocusState private var isFocused: Bool

    /// 初始化搜索输入框
    /// - Parameters:
    ///   - query: 搜索文本绑定
    ///   - placeholder: 占位文本
    ///   - icon: 左侧图标
    ///   - autoFocus: 出现时是否自动取焦点
    ///   - focusTrigger: 外部聚焦请求序号
    public init(
        query: Binding<String>,
        placeholder: String = "搜索…",
        icon: String? = "magnifyingglass",
        autoFocus: Bool = true,
        focusTrigger: Int = 0
    ) {
        self._query = query
        self.placeholder = placeholder
        self.icon = icon
        self.autoFocus = autoFocus
        self.focusTrigger = focusTrigger
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            if let icon {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.headerIcon)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .frame(width: DesignTokens.Size.headerIconSlot)
                    .accessibilityHidden(true)
            }

            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(DesignTokens.Typography.searchField)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .focused($isFocused)
                .onAppear {
                    if autoFocus { isFocused = true }
                }
                .onChange(of: focusTrigger) { _, _ in
                    isFocused = true
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) {
                    _ in
                    if autoFocus { isFocused = true }
                }
        }
        .frame(height: DesignTokens.Size.headerHeight)
    }
}
