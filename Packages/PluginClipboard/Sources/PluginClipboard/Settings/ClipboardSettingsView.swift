// ClipboardSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickUI
import SwiftUI

/// 剪贴板插件设置视图（嵌入 FeatureSettingsPane 的自定义区域）
///
/// 此视图由 ClipboardPlugin.makeSettingsView() 提供，
/// 覆盖 FeatureSettingsPane 的默认 ClipboardFeatureSection。
/// 为空实现，让 FeatureSettingsPane 使用统一的 defaultFeatureContent 即可。
/// 已弃用 —— 配置项统一在 FeatureSettingsPanes.ClipboardFeatureSection 中管理。
struct ClipboardSettingsView: View {

    var body: some View {
        EmptyView()
    }
}
