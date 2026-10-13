// AIPortalView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import QuickUI
import SwiftUI

/// AI 聚合门户视图
///
/// 头部品牌区 → Provider 卡片网格（2列）→ 全局偏好
/// 每个卡片展示 Provider 名称、URL、在线状态、操作按钮
struct AIPortalView: View {

    /// AI 窗口管理器（由插件注入，视图不去够全局单例）
    let manager: AIWebViewWindowManager

    @State private var activeProviders: Set<String> = []
    @State private var disabledProviders: Set<String> = []
    @State private var feedbackMessage: String?
    @State private var reloadingID: String?

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.lg) {
                headerSection
                providerGrid
                footerSection
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .task {
            while !Task.isCancelled {
                refreshActive()
                try? await Task.sleep(for: Self.activeRefreshInterval)
            }
        }
        .overlay(alignment: .bottom) {
            if let msg = feedbackMessage {
                toastView(msg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - 头部

    private var headerSection: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                    .fill(Color.accentColor.opacity(DesignTokens.Opacity.tint))
                    .frame(width: DesignTokens.Size.heroTile, height: DesignTokens.Size.heroTile)
                Image(systemName: "sparkles")
                    .font(.system(size: DesignTokens.Size.heroGlyph))
                    .foregroundStyle(Color.accentColor)
            }
            .help("AI 聚合门户")

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text("AI 聚合")
                        .font(DesignTokens.Typography.panelTitle)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text("AI Hub")
                        .font(DesignTokens.Typography.compactKeyCap).fontWeight(.medium)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(Color.accentColor.opacity(DesignTokens.Opacity.tint))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }
                Text("多窗口 AI 工作台，保持登录态，一键直达")
                    .font(DesignTokens.Typography.rowTrailing)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }

            Spacer()

            Button {
                manager.openOrFocusMergedWindow()
            } label: {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "macwindow.on.rectangle")
                        .font(DesignTokens.Typography.inlineIcon)
                    Text("聚合窗口")
                        .font(DesignTokens.Typography.inlineIcon)
                }
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .help("打开多标签 AI 聚合窗口")

            Button {
                EventBus.shared.post(ShowPaletteSettingsEvent(pluginID: AIPlugin.id))
            } label: {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "gearshape")
                        .font(DesignTokens.Typography.inlineIcon)
                    Text("管理中心")
                        .font(DesignTokens.Typography.inlineIcon)
                }
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .help("打开 AI 聚合的设置页面")
        }
        .padding(.bottom, DesignTokens.Spacing.sm)
    }

    // MARK: - Provider 网格

    private var providerGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: DesignTokens.Spacing.md),
                GridItem(.flexible(), spacing: DesignTokens.Spacing.md)
            ],
            spacing: DesignTokens.Spacing.md
        ) {
            ForEach(AIProviderRegistry.all) { provider in
                providerCard(provider)
            }
        }
    }

    private func providerCard(_ provider: AIProvider) -> some View {
        let isEnabled = !disabledProviders.contains(provider.id)
        let isActive = isEnabled && activeProviders.contains(provider.id)
        let accentColor = Color(hex: provider.accent) ?? Color.accentColor

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                        .fill(accentColor.opacity(isEnabled ? 0.12 : 0.05))
                        .frame(width: DesignTokens.Size.providerIcon, height: DesignTokens.Size.providerIcon)
                    Image(systemName: provider.icon)
                        .font(DesignTokens.Typography.iconGlyph)
                        .foregroundStyle(isEnabled ? accentColor : DesignTokens.Colors.textTertiary)
                }
                .help(provider.name)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Text(provider.name)
                            .font(DesignTokens.Typography.sectionHeader)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)

                        Text(isEnabled ? (isActive ? "运行中" : "就绪") : "已停用")
                            .font(DesignTokens.Typography.compactKeyCap)
                            .padding(.horizontal, DesignTokens.Spacing.sm)
                            .padding(.vertical, DesignTokens.Spacing.xxs)
                            .background(
                                Capsule().fill(
                                    isActive
                                        ? DesignTokens.Colors.success.opacity(DesignTokens.Opacity.tint)
                                        : DesignTokens.Colors.controlSurface)
                            )
                            .foregroundStyle(
                                isActive ? DesignTokens.Colors.success : DesignTokens.Colors.textTertiary)
                    }

                    Text(
                        isEnabled
                            ? provider.url.replacingOccurrences(of: "https://", with: "")
                            : "已在「设置 › AI 聚合」中停用"
                    )
                    .font(DesignTokens.Typography.compactKeyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .lineLimit(1)
                }

                Spacer()
            }

            HStack(spacing: DesignTokens.Spacing.sm) {
                Button {
                    if manager.openOrFocus(providerId: provider.id) {
                        showFeedback("已打开 \(provider.name)")
                    }
                    refreshActive()
                } label: {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Image(systemName: isEnabled ? "macwindow" : "nosign")
                            .font(DesignTokens.Typography.inlineIcon)
                        Text(
                            isEnabled
                                ? (isActive ? "聚焦窗口" : "打开窗口")
                                : "已在设置中停用"
                        )
                        .font(DesignTokens.Typography.bar)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: DesignTokens.Size.controlSquare)
                    .background(
                        isEnabled ? accentColor.opacity(DesignTokens.Opacity.tint) : DesignTokens.Colors.controlSurface)
                    .foregroundStyle(isEnabled ? accentColor : DesignTokens.Colors.textTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl))
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .help(isEnabled ? (isActive ? "聚焦 \(provider.name) 窗口" : "打开 \(provider.name)") : "该服务已在设置中停用")

                Button {
                    reloadingID = provider.id
                    manager.reloadWindow(for: provider.id)
                    showFeedback("正在刷新…")
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.8))
                        reloadingID = nil
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(DesignTokens.Typography.inlineIcon)
                        .rotationEffect(reloadingID == provider.id ? .degrees(360) : .zero)
                        .animation(
                            Motion.animation(
                                reloadingID == provider.id
                                    ? .linear(duration: DesignTokens.Duration.spin).repeatForever(
                                        autoreverses: false) : .default),
                            value: reloadingID
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("刷新 \(provider.name)")
                .frame(width: DesignTokens.Size.controlSquare, height: DesignTokens.Size.controlSquare)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .disabled(!isActive)
                .help("刷新 \(provider.name) 页面")

                Button {
                    manager.openInBrowser(providerId: provider.id)
                    showFeedback("已在浏览器中打开")
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(DesignTokens.Typography.inlineIcon)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("在浏览器中打开 \(provider.name)")
                .frame(width: DesignTokens.Size.controlSquare, height: DesignTokens.Size.controlSquare)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .help("在浏览器中打开 \(provider.name)")

                Button {
                    manager.destroyWindow(for: provider.id)
                    refreshActive()
                    showFeedback("已关闭 \(provider.name)")
                } label: {
                    Image(systemName: "xmark")
                        .font(DesignTokens.Typography.inlineIcon)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭 \(provider.name)")
                .frame(width: DesignTokens.Size.controlSquare, height: DesignTokens.Size.controlSquare)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .disabled(!isActive)
                .help("关闭 \(provider.name)")
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .strokeBorder(DesignTokens.Colors.cardStroke, lineWidth: DesignTokens.Size.hairlineThin)
        )
    }

    // MARK: - 底部

    private var footerSection: some View {
        // 合并成一行：两行提示会把内容撑出 475 的面板高度，凭空多出一段滚动
        Text("搜索 AI 名称可直接打开对应窗口 · 关闭窗口后登录态仍然保持")
            .font(DesignTokens.Typography.inlineIcon)
            .foregroundStyle(DesignTokens.Colors.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, DesignTokens.Spacing.xs)
    }

    // MARK: - Toast

    private func toastView(_ message: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "checkmark")
                .font(DesignTokens.Typography.inlineIcon)
            Text(message)
                .font(DesignTokens.Typography.bar)
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(DesignTokens.Opacity.popoverShadow), radius: DesignTokens.Size.popoverShadowRadius, y: DesignTokens.Size.popoverShadowOffsetY)
        .padding(.bottom, DesignTokens.Spacing.lg)
    }

    private static let activeRefreshInterval = Duration.seconds(2)

    // MARK: - 辅助

    private func refreshActive() {
        activeProviders = manager.activeProviderIDs()
        disabledProviders = manager.disabledProviderIDs()
    }

    private func showFeedback(_ message: String) {
        Motion.withAnimation(.easeInOut(duration: DesignTokens.Duration.feedbackFade)) {
            feedbackMessage = message
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(DesignTokens.Duration.feedbackHold))
            Motion.withAnimation(.easeInOut(duration: DesignTokens.Duration.feedbackFade)) {
                feedbackMessage = nil
            }
        }
    }
}

// MARK: - Color 十六进制扩展

extension Color {
    /// 从十六进制字符串创建颜色
    init?(hex: String) {
        let clean = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        guard clean.count == 6, let value = UInt64(clean, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
