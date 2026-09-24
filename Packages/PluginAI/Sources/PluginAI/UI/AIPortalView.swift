// AIPortalView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import QuickUI
import SwiftUI

/// AI 聚合门户视图
///
/// 参考 Fasty AI Portal 布局：
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
                // 头部品牌区
                headerSection

                // Provider 卡片网格
                providerGrid

                // 底部提示
                footerSection
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .task {
            // 窗口开关都由本插件自己发起，2 秒的轮询足够贴近；`Task` 的好处是视图
            // 消失时自动取消，不会留下一个孤儿定时器
            while !Task.isCancelled {
                refreshActive()
                try? await Task.sleep(for: Self.activeRefreshInterval)
            }
        }
        .overlay(alignment: .bottom) {
            // 操作反馈 Toast
            if let msg = feedbackMessage {
                toastView(msg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - 头部

    private var headerSection: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // 品牌头像
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "sparkles")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text("AI 聚合")
                        .font(DesignTokens.Typography.panelTitle)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text("AI Hub")
                        .font(DesignTokens.Typography.compactKeyCap).fontWeight(.medium)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }
                Text("各大 AI 官网独立窗口，保持登录态，一键直达")
                    .font(DesignTokens.Typography.rowTrailing)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }

            Spacer()

            // 长得像控件的文字必须是控件：Provider 开关在设置页里，这里给一条真能走的路
            Button {
                EventBus.shared.post(ShowPaletteSettingsEvent())
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                        .font(DesignTokens.Typography.inlineIcon)
                    Text("管理中心")
                        .font(DesignTokens.Typography.inlineIcon)
                }
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .help("打开设置窗口")
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
        // 停用优先于运行状态：停用的 Provider 打不开，说它「就绪」就是骗人 ——
        // 用户看到的就是「点了没反应」。
        let isEnabled = !disabledProviders.contains(provider.id)
        let isActive = isEnabled && activeProviders.contains(provider.id)
        let accentColor = Color(hex: provider.accent) ?? Color.accentColor

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            // 上部：Logo + 名称 + 状态
            HStack(spacing: DesignTokens.Spacing.sm) {
                // Provider 图标
                ZStack {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                        .fill(accentColor.opacity(isEnabled ? 0.12 : 0.05))
                        .frame(width: 32, height: 32)
                    Image(systemName: provider.icon)
                        .font(DesignTokens.Typography.iconGlyph)
                        .foregroundStyle(isEnabled ? accentColor : DesignTokens.Colors.textTertiary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.name)
                            .font(DesignTokens.Typography.sectionHeader)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)

                        // 状态指示
                        Text(isEnabled ? (isActive ? "运行中" : "就绪") : "已停用")
                            .font(DesignTokens.Typography.compactKeyCap)
                            .padding(.horizontal, DesignTokens.Spacing.sm)
                            .padding(.vertical, DesignTokens.Spacing.xxs)
                            .background(
                                Capsule().fill(
                                    isActive
                                        ? DesignTokens.Colors.success.opacity(0.12)
                                        : DesignTokens.Colors.controlSurface)
                            )
                            .foregroundStyle(
                                isActive ? DesignTokens.Colors.success : DesignTokens.Colors.textTertiary)
                    }

                    // 副标题：停用时换成「去哪儿重新打开」，比一个点不动的按钮有用
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

            // 操作按钮行
            HStack(spacing: 6) {
                // 主操作：打开/聚焦
                Button {
                    if manager.openOrFocus(providerId: provider.id) {
                        showFeedback("已打开 \(provider.name)")
                    }
                    refreshActive()
                } label: {
                    HStack(spacing: 4) {
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
                    .frame(height: 28)
                    .background(
                        isEnabled ? accentColor.opacity(0.12) : DesignTokens.Colors.controlSurface)
                    .foregroundStyle(isEnabled ? accentColor : DesignTokens.Colors.textTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl))
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)

                // 刷新
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
                            reloadingID == provider.id
                                ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                            value: reloadingID
                        )
                }
                .buttonStyle(.plain)
                .frame(width: 26, height: 26)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .disabled(!isActive)

                // 外部浏览器
                Button {
                    manager.openInBrowser(providerId: provider.id)
                    showFeedback("已在浏览器中打开")
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(DesignTokens.Typography.inlineIcon)
                }
                .buttonStyle(.plain)
                .frame(width: 26, height: 26)
                .foregroundStyle(DesignTokens.Colors.textTertiary)

                // 关闭窗口
                Button {
                    manager.destroyWindow(for: provider.id)
                    refreshActive()
                    showFeedback("已关闭 \(provider.name)")
                } label: {
                    Image(systemName: "xmark")
                        .font(DesignTokens.Typography.inlineIcon)
                }
                .buttonStyle(.plain)
                .frame(width: 26, height: 26)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .disabled(!isActive)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .strokeBorder(DesignTokens.Colors.cardStroke, lineWidth: 0.5)
        )
    }

    // MARK: - 底部

    private var footerSection: some View {
        VStack(spacing: 4) {
            Text("搜索 AI 名称可直接打开对应窗口")
                .font(DesignTokens.Typography.inlineIcon)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text("窗口关闭后登录态仍然保持")
                .font(DesignTokens.Typography.inlineIcon)
                .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DesignTokens.Spacing.sm)
    }

    // MARK: - Toast

    private func toastView(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(DesignTokens.Typography.inlineIcon)
            Text(message)
                .font(DesignTokens.Typography.bar)
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .padding(.bottom, DesignTokens.Spacing.lg)
    }

    /// 活跃状态的刷新间隔
    ///
    /// 窗口的开关都由本插件自己发起，2 秒足够贴近；再密只是白跑主 actor。
    private static let activeRefreshInterval = Duration.seconds(2)

    // MARK: - 辅助

    private func refreshActive() {
        activeProviders = manager.activeProviderIDs()
        disabledProviders = manager.disabledProviderIDs()
    }

    private func showFeedback(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            feedbackMessage = message
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(.easeInOut(duration: 0.2)) {
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
