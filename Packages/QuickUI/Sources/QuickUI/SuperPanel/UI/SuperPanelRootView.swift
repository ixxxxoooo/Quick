// SuperPanelRootView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import SwiftUI

/// 内容自然高度（由根视图量出，协调器据此调整窗口高度）
struct SuperPanelContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 超级面板根视图（对齐 Fasty：上下文态 + 工作台态）
struct SuperPanelRootView: View {

    let model: SuperPanelModel
    let onContentHeightChange: (CGFloat) -> Void
    let onOpenSettings: () -> Void
    let onClose: () -> Void
    let onLaunchTool: (SuperPanelQuickTool) -> Void
    let onRecentItem: (SuperPanelRecentItem) -> Void
    let onReplaceWithClipboard: (String) -> Void
    let onCopyClipboard: (String) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                SuperPanelHeaderView(
                    model: model,
                    onOpenSettings: onOpenSettings,
                    onClose: onClose
                )

                if model.isLoading {
                    SuperPanelSkeleton()
                } else {
                    switch model.activeTab {
                    case .context:
                        SuperPanelActionListView(
                            model: model,
                            onCopy: onCopyClipboard
                        )
                    case .dock:
                        SuperPanelDockView(
                            model: model,
                            onLaunchTool: onLaunchTool,
                            onRecentItem: onRecentItem,
                            onReplaceWithClipboard: onReplaceWithClipboard,
                            onCopyClipboard: onCopyClipboard
                        )
                    }
                }

                footer
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: SuperPanelContentHeightKey.self, value: proxy.size.height)
                }
            )
        }
        .frame(width: DesignTokens.Size.superPanelWidth)
        .background(SuperPanelBackground(appearance: model.appearance))
        .clipShape(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.superPanel, style: .continuous)
        )
        .overlay(alignment: .topTrailing) {
            if let toast = model.toast {
                SuperPanelToastView(message: toast)
                    .padding(DesignTokens.Spacing.md)
                    .transition(.opacity)
            }
        }
        .animation(Motion.animation(.easeOut(duration: DesignTokens.Duration.enter)), value: model.toast)
        .onPreferenceChange(SuperPanelContentHeightKey.self) { height in
            onContentHeightChange(height)
        }
    }

    /// 浮动胶囊底栏：没有分隔线、没有整条背景，只留一粒提示，把高度还给内容
    private var footer: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            switch model.activeTab {
            case .context:
                hint("↑↓", "选择")
                hint("↵", "执行")
            case .dock:
                hint("↑↓←→", "移动")
                hint("↵", "打开")
            }
            if model.hasContext {
                hint("⇥", "切换")
            }
            hint("esc", "关闭")
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(Capsule().fill(DesignTokens.Colors.controlSurface.opacity(DesignTokens.Opacity.controlSurfaceDim)))
        .frame(maxWidth: .infinity)
        .padding(.bottom, DesignTokens.Spacing.sm)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            Text(key)
                .font(DesignTokens.Typography.compactKeyCap)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .padding(.horizontal, DesignTokens.Spacing.xs)
                .padding(.vertical, DesignTokens.Spacing.hairline)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.keyCap, style: .continuous)
                        .fill(DesignTokens.Colors.controlSurface)
                )
            Text(label)
                .font(DesignTokens.Typography.compactKeyCap)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
    }
}

/// 面板背景：材质 + 可调不透明度的底色 + 边缘高光
struct SuperPanelBackground: View {

    let appearance: SuperPanelAppearance

    @Environment(\.displayScale) private var displayScale

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.superPanel, style: .continuous)
    }

    /// 不透明度映射到底色 alpha：文字始终不透明，只压背景
    private var tintAlpha: Double {
        if appearance.material == .solid { return 0.96 }
        let ratio =
            (appearance.opacity - SuperPanelPreferences.minOpacity)
            / (SuperPanelPreferences.maxOpacity - SuperPanelPreferences.minOpacity)
        return 0.22 + ratio * 0.68
    }

    var body: some View {
        ZStack {
            if appearance.material == .solid {
                Color(nsColor: .windowBackgroundColor)
            } else {
                VisualEffectView(material: appearance.material.nsMaterial, blending: .behindWindow)
                Color(nsColor: .windowBackgroundColor).opacity(tintAlpha)
            }
        }
        .clipShape(shape)
        .overlay {
            shape
                .strokeBorder(
                    DesignTokens.Colors.panelEdgeGradient,
                    lineWidth: DesignTokens.Size.hairline / displayScale
                )
                .allowsHitTesting(false)
        }
    }
}

extension SuperPanelMaterial {
    /// 映射到系统材质
    var nsMaterial: NSVisualEffectView.Material {
        switch self {
        case .hud: .hudWindow
        case .popover: .popover
        case .solid: .contentBackground
        }
    }
}
