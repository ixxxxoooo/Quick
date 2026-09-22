// SettingsRow.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 设置页的一行
///
/// 参考实现的行结构：**固定宽度的图标槽位 + 标题/副标题 + 弹性空隙 + 尾部控件**。
/// 副标题是这一行存在的理由 —— 一个只有「开机自动启动」的开关说不清它会做什么，
/// 一行灰字才能。
///
/// 放进 `Toggle` 的 label 里时只贡献左侧内容，开关仍然由系统放在尾部。
struct SettingsRow<Icon: View, Trailing: View>: View {

    /// 尾部内容的位置
    enum TrailingPlacement {
        /// 与标题同一行、靠右（默认）
        case inline
        /// 标题下方占满整行；标签这类「宽度不定、需要换行」的内容用它，
        /// 挤在同一行会被压扁成竖排文字
        case below
    }

    let title: String
    var subtitle: String?
    var trailingPlacement: TrailingPlacement = .inline
    @ViewBuilder var icon: Icon
    @ViewBuilder var trailing: Trailing

    var body: some View {
        switch trailingPlacement {
        case .inline:
            HStack(spacing: DesignTokens.Spacing.lg) {
                icon
                titleBlock
                Spacer(minLength: DesignTokens.Spacing.lg)
                trailing
            }
        case .below:
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                HStack(spacing: DesignTokens.Spacing.lg) {
                    icon
                    titleBlock
                }
                trailing
                    .padding(.leading, DesignTokens.Size.rowIcon + DesignTokens.Spacing.lg)
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            Text(title)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(DesignTokens.Typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .truncationMode(.middle)
                    // 副标题被截断时，悬停要能看到全文
                    .help(subtitle)
            }
        }
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder icon: () -> Icon
    ) {
        self.init(title: title, subtitle: subtitle, icon: icon, trailing: { EmptyView() })
    }
}

extension SettingsRow where Icon == EmptyView, Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle, icon: { EmptyView() }, trailing: { EmptyView() })
    }
}

/// 设置页里统一尺寸的图标槽位
///
/// 单独抽出来是因为「图标槽位宽度一致」是这一页读起来整齐的关键：
/// 每行各自 `Image` 会让标题的起始位置逐行漂移。
struct SettingsRowIcon: View {

    let systemImage: String
    var isEnabled: Bool = true

    var body: some View {
        Image(systemName: systemImage)
            .font(DesignTokens.Typography.iconGlyph)
            .foregroundStyle(isEnabled ? Color.accentColor : .secondary)
            .frame(width: DesignTokens.Size.rowIcon, alignment: .center)
            .accessibilityHidden(true)
    }
}

extension View {
    /// 置灰 + 禁用
    ///
    /// 只用 `.disabled` 会让标题保持全黑，看起来像能点 —— 必须同时降不透明度。
    func settingsEnabled(_ isEnabled: Bool) -> some View {
        disabled(!isEnabled).opacity(isEnabled ? 1 : 0.45)
    }
}
