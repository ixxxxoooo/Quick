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
///
/// **public**：插件的专属设置页住在插件自己的包里，它们要能拼出与宿主设置页
/// 一致的行。这是「插件只管内容区」在设置页上的对应约束 —— 外壳与行由 `QuickUI` 提供。
public struct SettingsRow<Icon: View, Trailing: View>: View {

    /// 尾部内容的位置
    public enum TrailingPlacement {
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

    /// 构造一行设置
    ///
    /// 显式声明而不是靠隐式 memberwise：**public 结构的隐式 memberwise init 是
    /// internal**，插件包因此用不了尾随闭包那种写法。参数名与属性一一对应，
    /// 调用点上看起来和 memberwise 一样。
    /// - Parameters:
    ///   - title: 主标题
    ///   - subtitle: 灰色的第二行；说清这一项会做什么
    ///   - trailingPlacement: 尾部控件与标题同行还是换到下方
    ///   - icon: 左侧固定宽度的图标槽位
    ///   - trailing: 尾部控件（开关、步进器、选择器等）
    public init(
        title: String,
        subtitle: String? = nil,
        trailingPlacement: TrailingPlacement = .inline,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailingPlacement = trailingPlacement
        self.icon = icon()
        self.trailing = trailing()
    }

    public var body: some View {
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
    public init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder icon: () -> Icon
    ) {
        self.init(title: title, subtitle: subtitle, icon: icon, trailing: { EmptyView() })
    }
}

extension SettingsRow where Icon == EmptyView, Trailing == EmptyView {
    public init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle, icon: { EmptyView() }, trailing: { EmptyView() })
    }
}

/// 设置页里统一尺寸的图标槽位
///
/// 默认用彩色色块（`SettingsTileIcon`），与侧栏视觉一致；
/// 未指定 tint 时回落为强调色单色符号，兼容旧调用点。
public struct SettingsRowIcon: View {

    let systemImage: String
    var tint: SettingsTileIcon.Tint? = nil
    var isEnabled: Bool = true

    /// 构造一个设置行图标
    /// - Parameters:
    ///   - systemImage: SF Symbol 名称
    ///   - tint: 色块档位；nil 时用强调色单色符号
    ///   - isEnabled: 关掉时置灰，与所在行的 `settingsEnabled` 一致
    public init(systemImage: String, tint: SettingsTileIcon.Tint? = nil, isEnabled: Bool = true) {
        self.systemImage = systemImage
        self.tint = tint
        self.isEnabled = isEnabled
    }

    public var body: some View {
        Group {
            if let tint {
                SettingsTileIcon(systemImage: systemImage, tint: tint, isEnabled: isEnabled)
            } else {
                Image(systemName: systemImage)
                    .font(DesignTokens.Typography.iconGlyph)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isEnabled ? Color.accentColor : .secondary)
                    .frame(width: DesignTokens.Size.rowIcon, alignment: .center)
            }
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// 置灰 + 禁用
    ///
    /// 只用 `.disabled` 会让标题保持全黑，看起来像能点 —— 必须同时降不透明度。
    public func settingsEnabled(_ isEnabled: Bool) -> some View {
        disabled(!isEnabled).opacity(isEnabled ? 1 : 0.45)
    }
}
