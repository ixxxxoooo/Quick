// WindowManagerView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 窗口管理模块视图
struct WindowManagerView: View {

    let mover: WindowMover

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xxl) {
            Text("窗口管理")
                .font(DesignTokens.Typography.panelTitle)

            // 布局网格
            LazyVGrid(columns: [
                GridItem(.flexible()), GridItem(.flexible()),
                GridItem(.flexible()), GridItem(.flexible())
            ], spacing: DesignTokens.Spacing.md) {
                ForEach(WindowLayout.allCases, id: \.rawValue) { layout in
                    Button {
                        mover.apply(layout)
                        EventBus.shared.post(HidePaletteEvent())
                    } label: {
                        VStack(spacing: DesignTokens.Spacing.sm) {
                            Image(systemName: layout.icon)
                                .font(.system(size: 24))
                            Text(layout.title)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(DesignTokens.Spacing.lg)
                        .background(DesignTokens.Colors.cardFill)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            Text("点击布局按钮将前台窗口移动到对应位置")
                .font(.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .padding(DesignTokens.Spacing.xxl)
    }
}
