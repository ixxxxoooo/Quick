// SystemControlView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 系统控制模块视图
struct SystemControlView: View {

    let runner: SystemActionRunner

    var body: some View {
        ScrollView {
            LazyVStack(spacing: DesignTokens.Spacing.xs) {
                ForEach(SystemAction.allCases, id: \.rawValue) { action in
                    SystemActionRow(action: action) {
                        runner.execute(action)
                        EventBus.shared.post(HidePaletteEvent())
                    }
                }
            }
            .padding(DesignTokens.Spacing.xl)
        }
    }
}

/// 系统操作行视图
struct SystemActionRow: View {

    let action: SystemAction
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: action.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(width: DesignTokens.Size.rowIcon)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(DesignTokens.Typography.rowTitle)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                Text(action.description)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.row)
                .fill(isHovered ? DesignTokens.Colors.rowHover : .clear)
        }
        .onHover { isHovered = $0 }
        .onTapGesture { onTap() }
        .contentShape(Rectangle())
    }
}
