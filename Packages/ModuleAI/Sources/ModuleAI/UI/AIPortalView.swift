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

    @State private var activeProviders: Set<String> = []
    @State private var feedbackMessage: String?
    @State private var reloadingID: String?

    /// 定时刷新活跃状态
    private let pollTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

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
        .onAppear { refreshActive() }
        .onReceive(pollTimer) { _ in refreshActive() }
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
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "sparkles")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text("AI 聚合")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text("AI Hub")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }
                Text("各大 AI 官网独立窗口，保持登录态，一键直达")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                Text("管理中心")
                    .font(.system(size: 11))
            }
            .foregroundStyle(DesignTokens.Colors.textTertiary)
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
        let isActive = activeProviders.contains(provider.id)
        let accentColor = Color(hex: provider.accent) ?? Color.accentColor

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            // 上部：Logo + 名称 + 状态
            HStack(spacing: DesignTokens.Spacing.sm) {
                // Provider 图标
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: provider.icon)
                        .font(.system(size: 15))
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DesignTokens.Colors.textPrimary)

                        // 在线状态指示
                        Text(isActive ? "运行中" : "就绪")
                            .font(.system(size: 10))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(
                                    isActive ? Color.green.opacity(0.12) : Color.secondary.opacity(0.1))
                            )
                            .foregroundStyle(isActive ? .green : DesignTokens.Colors.textTertiary)
                    }

                    // URL 显示
                    Text(provider.url.replacingOccurrences(of: "https://", with: ""))
                        .font(.system(size: 10.5))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .lineLimit(1)
                }

                Spacer()
            }

            // 操作按钮行
            HStack(spacing: 6) {
                // 主操作：打开/聚焦
                Button {
                    AIWebViewWindowManager.shared.openOrFocus(providerId: provider.id)
                    showFeedback("已打开 \(provider.name)")
                    refreshActive()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "macwindow")
                            .font(.system(size: 11))
                        Text(isActive ? "聚焦窗口" : "打开窗口")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(accentColor.opacity(0.12))
                    .foregroundStyle(accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                // 刷新
                Button {
                    reloadingID = provider.id
                    AIWebViewWindowManager.shared.reloadWindow(for: provider.id)
                    showFeedback("正在刷新…")
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.8))
                        reloadingID = nil
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
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
                    AIWebViewWindowManager.shared.openInBrowser(providerId: provider.id)
                    showFeedback("已在浏览器中打开")
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .frame(width: 26, height: 26)
                .foregroundStyle(DesignTokens.Colors.textTertiary)

                // 关闭窗口
                Button {
                    AIWebViewWindowManager.shared.destroyWindow(for: provider.id)
                    refreshActive()
                    showFeedback("已关闭 \(provider.name)")
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .frame(width: 26, height: 26)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .disabled(!isActive)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DesignTokens.Colors.cardStroke, lineWidth: 0.5)
        )
    }

    // MARK: - 底部

    private var footerSection: some View {
        VStack(spacing: 4) {
            Text("搜索 AI 名称可直接打开对应窗口")
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text("窗口关闭后登录态仍然保持")
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DesignTokens.Spacing.sm)
    }

    // MARK: - Toast

    private func toastView(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 11))
            Text(message)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .padding(.bottom, DesignTokens.Spacing.lg)
    }

    // MARK: - 辅助

    private func refreshActive() {
        activeProviders = AIWebViewWindowManager.shared.activeProviderIDs()
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
