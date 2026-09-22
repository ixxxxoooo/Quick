// SuperPanelDockView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 工作台：常用工具 + 剪贴板预览（对齐 Fasty SuperPanelDockView）
struct SuperPanelDockView: View {
    let clipboardText: String
    let showQuickTools: Bool
    let showClipboard: Bool
    let project: ProjectContext?
    let onOpenProject: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                if showQuickTools {
                    quickToolsSection
                }

                if showClipboard, !clipboardText.isEmpty {
                    clipboardCard
                }

                if let project {
                    projectCard(project)
                }

                if !showQuickTools && clipboardText.isEmpty && project == nil {
                    emptyHint
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.vertical, DesignTokens.Spacing.lg)
        }
    }

    private var quickToolsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("常用工具")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: DesignTokens.Spacing.md), count: 4),
                spacing: DesignTokens.Spacing.md
            ) {
                ForEach(SuperPanelQuickTools.defaults) { tool in
                    Button {
                        SuperPanelQuickTools.open(tool)
                    } label: {
                        VStack(spacing: DesignTokens.Spacing.sm) {
                            Image(systemName: tool.icon)
                                .font(DesignTokens.Typography.iconGlyph)
                                .foregroundStyle(Color.accentColor)
                                .frame(
                                    width: DesignTokens.Size.rowIcon + DesignTokens.Spacing.xl,
                                    height: DesignTokens.Size.rowIcon + DesignTokens.Spacing.xl
                                )
                                .background(
                                    RoundedRectangle(
                                        cornerRadius: DesignTokens.Radius.card, style: .continuous
                                    )
                                    .fill(Color.accentColor.opacity(0.1))
                                )
                            Text(tool.title)
                                .font(DesignTokens.Typography.keyCap)
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignTokens.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                                .fill(DesignTokens.Colors.cardFill)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var clipboardCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Label("最近剪贴板", systemImage: "doc.on.clipboard")
                    .font(DesignTokens.Typography.sectionHeader)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Spacer()
                Button("复制") {
                    EventBus.shared.post(CopyToClipboardEvent(text: clipboardText))
                }
                .font(DesignTokens.Typography.keyCap)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

            Text(clipboardText)
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .lineLimit(3)
        }
        .padding(DesignTokens.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .fill(DesignTokens.Colors.cardFill)
        )
    }

    private func projectCard(_ project: ProjectContext) -> some View {
        Button(action: onOpenProject) {
            HStack(spacing: DesignTokens.Spacing.lg) {
                Image(systemName: project.type.icon)
                    .font(DesignTokens.Typography.iconGlyph)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: DesignTokens.Size.rowIcon, height: DesignTokens.Size.rowIcon)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(project.name)
                        .font(DesignTokens.Typography.rowTitle)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Text(project.type.displayName)
                        if let branch = project.gitBranch {
                            Text("· \(branch)")
                        }
                    }
                    .font(DesignTokens.Typography.rowTrailing)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(DesignTokens.Typography.inlineIcon)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .padding(DesignTokens.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                    .fill(DesignTokens.Colors.cardFill)
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyHint: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "bolt.square")
                .font(DesignTokens.Typography.emptyStateIcon)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text("复制文本后再打开，可识别网址、颜色、时间戳等")
                .font(DesignTokens.Typography.rowTitle)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignTokens.Spacing.xxl)
    }
}
