// SuperPanelSettingsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 超级面板的独立设置页
///
/// 它是宿主级页面，不出现在「插件」列表里：超级面板不是插件，而是一块系统级浮层。
/// 面板行为（唤出、外观、工作台内容）都写在这里，快捷键与辅助功能权限通过
/// `SettingsDataSource` 走宿主的系统能力。
public struct SuperPanelSettingsView: View {

    let dataSource: any SettingsDataSource

    public init(dataSource: any SettingsDataSource) {
        self.dataSource = dataSource
    }

    @AppStorage(SuperPanelPreferences.Key.mouseLongPressEnabled) private var longPressEnabled = true
    @AppStorage(SuperPanelPreferences.Key.middleClickEnabled) private var middleClickEnabled = true
    @AppStorage(SuperPanelPreferences.Key.mouseLongPressThresholdMs) private var thresholdMs = 450
    @AppStorage(SuperPanelPreferences.Key.opacity) private var opacity = SuperPanelPreferences.defaultOpacity
    @AppStorage(SuperPanelPreferences.Key.material) private var materialRaw = SuperPanelPreferences
        .defaultMaterial.rawValue
    @AppStorage(SuperPanelPreferences.Key.showRecents) private var showRecents = true
    @AppStorage(SuperPanelPreferences.Key.showClipboard) private var showClipboard = true

    @State private var tools: [SuperPanelQuickTool] = []
    @State private var toolToAdd: String = ""
    @State private var didClearRecents = false

    // 滑块的拖动值单独放本地状态，**只有松手时才写回 `@AppStorage`**。
    //
    // 直接绑定 `@AppStorage` 会在拖动的每一帧都写一次 `UserDefaults`，而宿主监听
    // `UserDefaults.didChangeNotification` 重新套用外观 —— 那个重排会在拖动过程中把
    // 手势打断，表现就是「滑块拖不动」。本地状态不落盘，松手才持久化一次。
    @State private var thresholdValue = Double(SuperPanelPreferences.defaultThresholdMs)
    @State private var opacityValue = SuperPanelPreferences.defaultOpacity

    private var permission: SettingsPermissionState {
        dataSource.permissionState(.accessibility)
    }

    public var body: some View {
        Form {
            triggerSection
            appearanceSection
            contentSection
            toolsSection
        }
        .formStyle(.grouped)
        .onAppear {
            tools = SuperPanelQuickTools.load()
            thresholdValue = Double(thresholdMs)
            opacityValue = opacity
        }
    }

    // MARK: - 唤醒

    private var triggerSection: some View {
        Section {
            SettingsRow(
                title: "全局快捷键",
                subtitle: "在任意应用中唤出超级面板。默认 ⌥C。",
                icon: { SettingsRowIcon(systemImage: "keyboard") }
            ) {
                ShortcutRecorder(
                    keycaps: dataSource.superPanelShortcutKeycaps,
                    onRecord: { keyCode, modifiers in
                        _ = dataSource.setSuperPanelShortcut(keyCode: keyCode, carbonModifiers: modifiers)
                    },
                    onClear: { dataSource.clearSuperPanelShortcut() }
                )
            }

            Toggle(isOn: $longPressEnabled) {
                SettingsRow(
                    title: "长按鼠标右键唤出",
                    subtitle: "在任意应用中按住右键约 \(Int(thresholdValue)) 毫秒唤出。",
                    icon: { SettingsRowIcon(systemImage: "computermouse") }
                )
            }

            if longPressEnabled {
                SettingsRow(
                    title: "长按判定阈值",
                    subtitle: "阈值越短越灵敏，也越容易误触。",
                    icon: { SettingsRowIcon(systemImage: "timer") }
                ) {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Slider(
                            value: $thresholdValue,
                            in: thresholdRange,
                            step: Double(SuperPanelPreferences.thresholdStepMs),
                            onEditingChanged: { editing in
                                if !editing {
                                    thresholdMs = SuperPanelPreferences.clampedThreshold(
                                        Int(thresholdValue))
                                }
                            }
                        )
                        .frame(width: 140)
                        Text("\(Int(thresholdValue)) ms")
                            .font(DesignTokens.Typography.rowTrailing)
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)
                    }
                }
            }

            Toggle(isOn: $middleClickEnabled) {
                SettingsRow(
                    title: "中键单击唤出",
                    subtitle: "按下鼠标滚轮键（中键）唤出，会保留划词选中。",
                    icon: { SettingsRowIcon(systemImage: "computermouse") }
                )
            }

            SettingsRow(
                title: "辅助功能权限",
                subtitle: "鼠标唤出与「替换原文」需要此权限。",
                icon: { SettingsRowIcon(systemImage: "hand.raised") }
            ) {
                if permission.isGranted {
                    Label("已授权", systemImage: "checkmark.circle.fill")
                        .font(DesignTokens.Typography.rowTrailing)
                        .foregroundStyle(DesignTokens.Colors.success)
                        .labelStyle(.titleAndIcon)
                } else if permission.canRequest {
                    Button("申请授权") { dataSource.requestPermission(.accessibility) }
                } else {
                    Button("打开系统设置") { dataSource.openPermissionSettings(.accessibility) }
                }
            }
        } header: {
            Text("唤醒")
        } footer: {
            Text("鼠标唤出需要辅助功能权限；未授权时监听不会启动，只能使用快捷键。")
        }
    }

    private var thresholdRange: ClosedRange<Double> {
        Double(SuperPanelPreferences.minThresholdMs)...Double(SuperPanelPreferences.maxThresholdMs)
    }

    // MARK: - 外观

    private var appearanceSection: some View {
        Section {
            SettingsRow(
                title: "背景不透明度",
                subtitle: "只影响背景，文字始终保持清晰。",
                icon: { SettingsRowIcon(systemImage: "circle.lefthalf.filled") }
            ) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Slider(
                        value: $opacityValue,
                        in: SuperPanelPreferences.minOpacity...SuperPanelPreferences.maxOpacity,
                        step: SuperPanelPreferences.opacityStep,
                        onEditingChanged: { editing in
                            if !editing {
                                opacity = SuperPanelPreferences.clampedOpacity(opacityValue)
                            }
                        }
                    )
                    .frame(width: 140)
                    Text("\(Int((opacityValue * 100).rounded()))%")
                        .font(DesignTokens.Typography.rowTrailing)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }

            Picker(selection: $materialRaw) {
                ForEach(SuperPanelMaterial.allCases) { material in
                    Text(material.title).tag(material.rawValue)
                }
            } label: {
                SettingsRow(
                    title: "背景材质",
                    subtitle: "macOS 只提供固定的几档毛玻璃，这里选的是其中最接近的。",
                    icon: { SettingsRowIcon(systemImage: "square.on.square") }
                )
            }
        } header: {
            Text("外观")
        }
    }

    // MARK: - 工作台

    private var contentSection: some View {
        Section {
            Toggle(isOn: $showRecents) {
                SettingsRow(
                    title: "显示最近使用",
                    subtitle: "空白唤出时列出最近用过的应用与工具。",
                    icon: { SettingsRowIcon(systemImage: "clock.arrow.circlepath") }
                )
            }

            Toggle(isOn: $showClipboard) {
                SettingsRow(
                    title: "显示剪贴板预览",
                    subtitle: "在工作台底部展示最近一条剪贴板内容。",
                    icon: { SettingsRowIcon(systemImage: "doc.on.clipboard") }
                )
            }

            SettingsRow(
                title: "清空最近使用",
                subtitle: "只清空超级面板里展示的「最近使用」记录。",
                icon: { SettingsRowIcon(systemImage: "trash") }
            ) {
                Button(didClearRecents ? "已清空" : "清空") {
                    dataSource.clearRecentUsage()
                    didClearRecents = true
                }
                .disabled(didClearRecents)
            }
        } header: {
            Text("工作台")
        }
    }

    // MARK: - 常用工具

    private var toolsSection: some View {
        Section {
            ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                SettingsRow(
                    title: tool.title,
                    subtitle: "plugin.\(tool.pluginID)",
                    icon: { SettingsRowIcon(systemImage: tool.icon) }
                ) {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Button {
                            move(from: index, by: -1)
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)

                        Button {
                            move(from: index, by: 1)
                        } label: {
                            Image(systemName: "arrow.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == tools.count - 1)

                        Button {
                            remove(tool)
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .disabled(tools.count <= 1)
                    }
                }
            }

            HStack(spacing: DesignTokens.Spacing.sm) {
                Picker(selection: $toolToAdd) {
                    Text("添加工具…").tag("")
                    ForEach(availableTools) { tool in
                        Text(tool.title).tag(tool.id)
                    }
                } label: {
                    SettingsRow(
                        title: "添加常用工具",
                        subtitle: "工作台默认展示前 8 个。",
                        icon: { SettingsRowIcon(systemImage: "plus") }
                    )
                }
                .frame(maxWidth: 320)
                .disabled(availableTools.isEmpty)

                Button("添加") { addTool() }
                    .disabled(toolToAdd.isEmpty)
            }

            SettingsRow(
                title: "恢复默认",
                subtitle: "把常用工具恢复为默认的八宫格。",
                icon: { SettingsRowIcon(systemImage: "arrow.counterclockwise") }
            ) {
                Button("恢复默认") {
                    tools = SuperPanelQuickTools.defaults
                    SuperPanelQuickTools.save(tools)
                }
            }
        } header: {
            Text("常用工具")
        } footer: {
            Text("工具卡片点击后会跳转到对应插件的面板。")
        }
    }

    private var availableTools: [SuperPanelQuickTool] {
        SuperPanelQuickTools.available(excluding: tools)
    }

    private func move(from index: Int, by delta: Int) {
        let target = index + delta
        guard tools.indices.contains(index), tools.indices.contains(target) else { return }
        tools.swapAt(index, target)
        SuperPanelQuickTools.save(tools)
    }

    private func remove(_ tool: SuperPanelQuickTool) {
        tools.removeAll { $0.id == tool.id }
        SuperPanelQuickTools.save(tools)
    }

    private func addTool() {
        guard let tool = SuperPanelQuickTools.catalog.first(where: { $0.id == toolToAdd }) else { return }
        tools.append(tool)
        SuperPanelQuickTools.save(tools)
        toolToAdd = ""
    }
}
