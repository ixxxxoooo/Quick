// SectionHeader.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 列表分组标题
///
/// 用在结果列表里分隔不同插件的结果。底部留白是固定的
/// （`Spacing.sectionHeaderBottom`），这样标题与它下面第一行的距离
/// 在任何分组里都一致。
public struct SectionHeader: View {

    public let title: String

    /// 初始化分组标题
    /// - Parameter title: 标题文本
    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(DesignTokens.Typography.sectionHeader)
            .foregroundStyle(DesignTokens.Colors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.bottom, DesignTokens.Spacing.sectionHeaderBottom)
    }
}
