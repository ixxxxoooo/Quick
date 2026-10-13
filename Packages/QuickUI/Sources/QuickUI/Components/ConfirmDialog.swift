// ConfirmDialog.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 一次待确认的操作
///
/// 面板是无边框玻璃，`NSAlert` 的标题栏窗口与它视觉冲突（见 `docs/ui.md` §9），
/// 所以破坏性操作的二次确认走这个应用内对话框。
public struct ConfirmRequest: Identifiable, Equatable, Sendable {

    public let id: String
    public let title: String
    public let message: String
    public let confirmTitle: String
    /// 破坏性操作：确认按钮用警示色
    public let isDestructive: Bool
    /// 顶部大图标（SF Symbol）
    public let icon: String

    public init(
        id: String,
        title: String,
        message: String,
        confirmTitle: String,
        isDestructive: Bool = true,
        icon: String = "exclamationmark.triangle.fill"
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.isDestructive = isDestructive
        self.icon = icon
    }
}

/// 模态确认框的键盘语义
///
/// 抽成纯函数是为了能单测：确认框出现时 ↵ 必须是「确认」、Esc 必须是「取消」，
/// 其余导航键一律吞掉（不能让 ↑↓ 在背后的列表里悄悄移动选中项）。
public enum ConfirmDialogKey: Equatable, Sendable {
    case confirm
    case cancel
    case ignore

    /// 把插件收到的导航请求翻译成确认框的动作
    public static func resolve(_ navigation: PluginSearchQuery.Navigation) -> ConfirmDialogKey {
        switch navigation {
        case .submit: return .confirm
        case .cancel: return .cancel
        case .move, .tab: return .ignore
        }
    }
}

extension View {

    /// 在视图上叠一个应用内模态确认框
    ///
    /// 确认框显示期间会把 `search.wantsCancel` 置真，让面板把 Esc 变成 `.cancel` 请求，
    /// 收起时置回；键盘事件由插件视图在 `commandToken` 回调里交给 `ConfirmDialogKey.resolve`。
    ///
    /// - Parameters:
    ///   - request: 待确认的请求；非 nil 即显示
    ///   - search: 面板的插件内搜索桥（用来接管 Esc）
    ///   - onConfirm: 用户确认时回调
    public func confirmDialog(
        _ request: Binding<ConfirmRequest?>,
        search: PluginSearchQuery?,
        onConfirm: @escaping (ConfirmRequest) -> Void
    ) -> some View {
        modifier(ConfirmDialogModifier(request: request, search: search, onConfirm: onConfirm))
    }
}

private struct ConfirmDialogModifier: ViewModifier {

    @Binding var request: ConfirmRequest?
    let search: PluginSearchQuery?
    let onConfirm: (ConfirmRequest) -> Void

    func body(content: Content) -> some View {
        content
            .overlay {
                if let current = request {
                    ConfirmDialogView(
                        request: current,
                        onConfirm: {
                            request = nil
                            onConfirm(current)
                        },
                        onCancel: { request = nil }
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: DesignTokens.Duration.hover), value: request?.id)
            .onChange(of: request?.id) { _, newValue in
                search?.wantsCancel = newValue != nil
            }
            .onDisappear { search?.wantsCancel = false }
    }
}

/// 对话框本体
struct ConfirmDialogView: View {

    let request: ConfirmRequest
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            DesignTokens.Colors.panelScrim
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: DesignTokens.Spacing.lg) {
                Image(systemName: request.icon)
                    .font(.system(size: DesignTokens.Size.dialogIcon))
                    .foregroundStyle(
                        request.isDestructive
                            ? DesignTokens.Colors.destructive : DesignTokens.Colors.warning
                    )
                    .accessibilityHidden(true)

                VStack(spacing: DesignTokens.Spacing.sm) {
                    Text(request.title)
                        .font(DesignTokens.Typography.panelTitle)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text(request.message)
                        .font(DesignTokens.Typography.rowTrailing)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: DesignTokens.Spacing.md) {
                    dialogButton(title: "取消", hint: "Esc", isPrimary: false, action: onCancel)
                    dialogButton(
                        title: request.confirmTitle, hint: "↵", isPrimary: true, action: onConfirm)
                }
            }
            .padding(DesignTokens.Spacing.xxl)
            .frame(width: DesignTokens.Size.dialogWidth)
            .background {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.dialog, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.dialog, style: .continuous)
                            .strokeBorder(DesignTokens.Colors.cardStroke)
                    }
            }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }

    private func dialogButton(
        title: String, hint: String, isPrimary: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text(title)
                    .font(DesignTokens.Typography.bar)
                KeyCapChip(text: hint, style: .outline, scale: .compact)
            }
            .frame(maxWidth: .infinity)
            .frame(height: DesignTokens.Size.barButtonHeight)
            .foregroundStyle(
                isPrimary && request.isDestructive
                    ? DesignTokens.Colors.destructive : DesignTokens.Colors.textPrimary
            )
            .background {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                    .fill(
                        isPrimary && request.isDestructive
                            ? DesignTokens.Colors.destructive.opacity(DesignTokens.Opacity.destructiveFill)
                            : DesignTokens.Colors.controlSurface)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
