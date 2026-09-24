// MarkdownPreviewSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct MarkdownPreviewSettingsView: View {
    @AppStorage(PluginSettingKey.MarkdownPreview.showLineNumbers) private var showLineNumbers = true
    @AppStorage(PluginSettingKey.MarkdownPreview.enableMathJax) private var enableMathJax = true

    var body: some View {
        Section {
            Toggle(isOn: $showLineNumbers) {
                SettingsRow(
                    title: "代码块显示行号",
                    subtitle: "在渲染的代码语法高亮区块左侧显示代码行号。",
                    icon: { SettingsRowIcon(systemImage: "list.number") }
                )
            }

            Toggle(isOn: $enableMathJax) {
                SettingsRow(
                    title: "启用数学公式渲染 (LaTeX)",
                    subtitle: "自动识别并渲染 $...$ 与 $$...$$ 内的数学公式。",
                    icon: { SettingsRowIcon(systemImage: "function") }
                )
            }
        } header: {
            Text("Markdown 渲染")
        }
    }
}
