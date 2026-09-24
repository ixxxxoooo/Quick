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
    /// **只问能力，不做分发。** 以前这里是一个按 `SettingsTab` 硬编码 22 个分支的
    /// switch，把每个插件的表单都留在 `QuickUI` 里 —— 结果是共享 UI 包认识每个插件
    /// 的专属配置（`QuickUI` 因此成了「所有插件设置页的宿主」，而不是外壳）。
    /// 现在插件的表单住在插件自己的包里，由 `PluginSettingsProviding` 提供。
    ///
    /// 没实现该协议的插件（或返回 nil 的）不额外显示内容 —— 概览与触发关键字
    /// 两节已经把它们能配置的东西说完了，再补一块空白只是噪音。
    @ViewBuilder
    private var featureSection: some View {
        if let customView = dataSource.makeFeatureSettingsView(for: tab) {
            customView.settingsEnabled(isEnabled)
        }
    }

    // MARK: - 触发关键字

    /// 触发关键字：按功能拆开，每个功能一行 + 它自己的关键字胶囊
    ///
    /// 插件默认的「打开本插件」命令不单列 —— 它的关键字就是插件的唤醒词，和下面的
    /// 功能关键字重复，单列只是噪音。没有声明任何功能（命令）的插件，这一节整体不显示。
    @ViewBuilder
    private var wakeSection: some View {
        let commands = extraCommands.filter { !displayKeywords($0.keywords).isEmpty }
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
                        triggerChips(displayKeywords(command.keywords))
                    }
                }
            } header: {
                Text("触发关键字")
            } footer: {
                Text("在主面板输入某个功能的关键字即可直接触发它；要给某条命令绑快捷键，到「快捷键」页添加。")
            }
        }
    }

    /// 除默认「打开本插件」之外的命令
    private var extraCommands: [SettingsCommandBinding] {
        guard let pluginID = tab.pluginID else { return [] }
        let openCommandID = CommandID.openPlugin(pluginID)
        return dataSource.pluginCommands(pluginID).filter { $0.id != openCommandID }
    }

    /// 展示用的关键字：命令关键字不带空格，带空格的直接不显示；并去重
    private func displayKeywords(_ keywords: [String]) -> [String] {
        var seen = Set<String>()
        return keywords.filter { word in
            !word.isEmpty
                && !word.contains(where: { $0.isWhitespace })
                && seen.insert(word.lowercased()).inserted
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
                            .fill(Color.accentColor.opacity(0.12))
                    )
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

}
