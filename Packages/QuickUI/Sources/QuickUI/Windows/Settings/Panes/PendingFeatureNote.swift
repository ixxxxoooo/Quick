// PendingFeatureNote.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 「这个选项还没有实现」的说明
///
/// 设置页里有些控件对应的功能还没做（天气数据源、日历提醒、ping 测试、保存窗口布局）。
/// 控件保留是为了让路线图可见，但**必须禁用并说明** ——
/// 一个能拨动却什么也不做的开关比没有这个开关更糟：用户会以为功能坏了，
/// 而且他会先怀疑自己没设置对。
struct PendingFeatureNote: View {

    /// 说明为什么还不能用、以及它在等什么
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "hammer")
                .font(DesignTokens.Typography.inlineIcon)
            Text(detail)
                .font(DesignTokens.Typography.keyCap)
        }
        .foregroundStyle(DesignTokens.Colors.textTertiary)
    }
}
