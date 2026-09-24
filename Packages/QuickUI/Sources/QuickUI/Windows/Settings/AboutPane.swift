// AboutPane.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import SwiftUI

/// 关于
///
/// 除了版本号，这里放的是**排查问题时真正用得上的东西**：bundle id、
/// 日志命令、面板几何。这三样在定位「日志里怎么找不到它」时都会用到。
struct AboutPane: View {

    let dataSource: any HostSettingsDataSource

    /// 复制反馈
    @State private var copiedField: String?

    var body: some View {
        Form {
            Section("版本") {
                SettingsRow(
                    title: "Quick",
                    subtitle: "原生 macOS 效率启动器",
                    icon: { SettingsRowIcon(systemImage: "macwindow.on.rectangle") }
                ) {
                    Text(dataSource.versionDescription)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                SettingsRow(title: "Bundle ID", subtitle: "统一日志的 subsystem 就是它。") {
                    copyable(dataSource.bundleIdentifier, field: "bundle")
                }
            }

            Section("面板") {
                SettingsRow(
                    title: "尺寸",
                    subtitle: "与设计基准一致，改 DesignTokens.panelScale 可整体缩放。",
                    icon: { SettingsRowIcon(systemImage: "rectangle.inset.filled") }
                ) {
                    Text(dataSource.panelGeometryDescription)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                SettingsRow(
                    title: "全局快捷键",
                    icon: { SettingsRowIcon(systemImage: "keyboard") }
                ) {
                    KeyCapChip(text: dataSource.hotKeyDescription, style: .outline)
                }
            }

            Section {
                SettingsRow(
                    title: "查看实时日志",
                    subtitle: "在终端里执行。面板显隐、搜索耗时这类高频日志只在实时流里可见。",
                    icon: { SettingsRowIcon(systemImage: "text.alignleft") }
                ) {
                    copyable("cd \(Bundle.main.bundlePath) && ./Scripts/logs.sh", field: "logs")
                }
            } header: {
                Text("排查")
            } footer: {
                Text("遇到问题时先看日志：插件是否激活、快捷键是否注册成功、哪一步失败，都会记在里面。")
            }
        }
        .formStyle(.grouped)
    }

    /// 一个可点击复制的值
    ///
    /// 排查时要粘贴到终端或日志过滤器里，所以做成一键复制 —— 手选容易漏字符。
    private func copyable(_ value: String, field: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            copiedField = field
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                if copiedField == field { copiedField = nil }
            }
        } label: {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Text(value)
                    .font(DesignTokens.Typography.code)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: copiedField == field ? "checkmark" : "doc.on.doc")
                    .font(DesignTokens.Typography.inlineIcon)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(copiedField == field ? DesignTokens.Colors.success : Color.accentColor)
        .help("点击复制")
        .accessibilityLabel("复制 \(value)")
    }
}
