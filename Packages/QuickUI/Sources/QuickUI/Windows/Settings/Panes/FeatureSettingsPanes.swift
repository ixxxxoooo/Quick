// FeatureSettingsPanes.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 功能插件独立设置页容器
///
/// 每个功能插件的设置页只有三块，且互不重复：
/// 1. 概览：启用开关 + 一句话简介
/// 2. 专属配置项
/// 3. 触发关键字：按功能拆开，每个功能展示自己的关键字
struct FeatureSettingsPane: View {

    let tab: SettingsTab
    let dataSource: any PluginSettingsDataSource & CommandSettingsDataSource

    @State private var isEnabled: Bool

    init(tab: SettingsTab, dataSource: any PluginSettingsDataSource & CommandSettingsDataSource) {
        self.tab = tab
        self.dataSource = dataSource
        let modID = tab.pluginID ?? ""
        _isEnabled = State(initialValue: dataSource.isPluginEnabled(modID))
    }

    /// 查找当前插件的元信息
    private var pluginInfo: SettingsPlugin? {
        guard let pluginID = tab.pluginID else { return nil }
        return dataSource.pluginEntries.first { $0.id == pluginID }
    }

    var body: some View {
        Form {
            overviewSection
            featureSection
            wakeSection
        }
        .formStyle(.grouped)
    }

    // MARK: - 概览

    /// 启用开关 + 简介
    ///
    /// 不设分组标题：窗口标题与侧边栏已经写着插件名，这里再重复一遍就是噪音。
    private var overviewSection: some View {
        Section {
            Toggle(isOn: $isEnabled) {
                SettingsRow(
                    title: "启用此插件",
                    subtitle: "开启后可在主面板搜索并使用。",
                    icon: {
                        SettingsRowIcon(
                            systemImage: tab.systemImage,
                            tint: .named(tab.iconTintName)
                        )
                    }
                )
            }
            .onChange(of: isEnabled) { _, newValue in
                if let modID = tab.pluginID {
                    dataSource.setPluginEnabled(modID, enabled: newValue)
                }
            }

            if let description = pluginInfo?.description, !description.isEmpty {
                SettingsRow(
                    title: "简介",
                    subtitle: description,
                    icon: { SettingsRowIcon(systemImage: "info.circle") }
                )
            }
        }
    }

    // MARK: - 专属配置

    /// 插件自己的设置项；插件关闭时整体置灰
    ///
    /// **只问能力，不做分发。** 表单住在插件自己的包里，由 `PluginSettingsProviding`
    /// 在运行时提供；这里认识的是协议，不是任何一个插件。没实现该协议（或返回 nil）
    /// 的插件不额外显示内容 —— 概览与触发关键字两节已经说完了它能配置的东西。
    @ViewBuilder
    private var featureSection: some View {
        if let customView = dataSource.makeFeatureSettingsView(for: tab) {
            customView.settingsEnabled(isEnabled)
        }
    }

    // MARK: - 触发关键字

    /// 触发关键字：有独立子命令的插件按子命令逐行展示；单一视图插件直接展示本插件入口及其触发词
    @ViewBuilder
    private var wakeSection: some View {
        let commands = wakeCommands.filter { !displayKeywords($0.keywords, title: $0.title).isEmpty }
        if !commands.isEmpty {
            Section {
                ForEach(commands) { command in
                    SettingsRow(
                        title: command.title,
                        subtitle: command.subtitle,
                        trailingPlacement: .below,
                        icon: {
                            SettingsRowIcon(
                                systemImage: command.icon,
                                isEnabled: command.isInvocationEnabled)
                        }
                    ) {
                        triggerChips(displayKeywords(command.keywords, title: command.title))
                    }
                }
            } header: {
                Text("触发关键字")
            } footer: {
                Text("在主面板输入某个功能的关键字即可直接触发它；要给某条命令绑快捷键，到「快捷键」页添加。")
            }
        }
    }

    /// 优先展示独立功能命令；若插件只有单一面板入口，则展示该入口命令
    private var wakeCommands: [SettingsCommandBinding] {
        guard let pluginID = tab.pluginID else { return [] }
        let all = dataSource.pluginCommands(pluginID)
        let openCommandID = CommandID.openPlugin(pluginID)
        let specific = all.filter { $0.id != openCommandID }
        return specific.isEmpty ? all : specific
    }

    /// 展示用的关键字：过滤掉空格、与标题重复的词、并大小写去重
    private func displayKeywords(_ keywords: [String], title: String? = nil) -> [String] {
        var seen = Set<String>()
        if let title {
            seen.insert(title.lowercased())
            seen.insert(title.replacingOccurrences(of: " ", with: "").lowercased())
        }
        return keywords.filter { word in
            let clean = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, !clean.contains(where: { $0.isWhitespace }) else { return false }
            return seen.insert(clean.lowercased()).inserted
        }
    }

    /// 关键字标签：一行放不下就换行，标签内部不换行
    private func triggerChips(_ words: [String]) -> some View {
        FlowLayout(horizontalSpacing: DesignTokens.Spacing.sm, verticalSpacing: DesignTokens.Spacing.xs) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                Text(word)
                    .font(DesignTokens.Typography.keyCap)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                            .fill(Color.accentColor.opacity(DesignTokens.Opacity.tint))
                    )
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

}
