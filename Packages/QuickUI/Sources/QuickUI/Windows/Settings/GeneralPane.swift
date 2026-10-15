// GeneralPane.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import QuickPlatform
import SwiftUI
import UniformTypeIdentifiers

/// 通用设置
struct GeneralPane: View {

    let dataSource: any HostSettingsDataSource & PluginSettingsDataSource

    @State private var launchAtLogin: Bool
    @AppStorage(SettingsKey.paletteAutoPasteSeconds)
    private var autoPasteSeconds = PaletteAutoBehavior.defaultPasteWindow.rawValue
    @AppStorage(SettingsKey.paletteAutoClearMinutes)
    private var autoClearMinutes = PaletteAutoBehavior.defaultClearIdle.rawValue

    /// 备份操作的结果提示（成功与失败都在页面里说，不弹 NSAlert）
    @State private var backupStatus: BackupStatus?

    private enum BackupStatus: Equatable {
        case exported(String)
        case imported(SettingsImportSummary)
        case failed(String)
    }

    init(dataSource: any HostSettingsDataSource & PluginSettingsDataSource) {
        self.dataSource = dataSource
        _launchAtLogin = State(initialValue: dataSource.isLaunchAtLoginEnabled)
    }

    var body: some View {
        Form {
            Section("启动") {
                Toggle(isOn: $launchAtLogin) {
                    SettingsRow(
                        title: "开机自动启动",
                        subtitle: "登录后在菜单栏常驻，不打开任何窗口。",
                        icon: { SettingsRowIcon(systemImage: "power") }
                    )
                }
                .onChange(of: launchAtLogin) { _, newValue in
                    dataSource.setLaunchAtLogin(newValue)
                }
            }

            Section("面板") {
                SettingsRow(
                    title: "关闭面板",
                    subtitle: "按 Esc，或点击面板以外的任意位置。唤出快捷键在「快捷键」页设置。",
                    icon: { SettingsRowIcon(systemImage: "escape") }
                ) {
                    KeyCapChip(text: "Esc", style: .outline)
                }
            }

            Section {
                Picker(selection: $autoPasteSeconds) {
                    ForEach(PaletteAutoBehavior.AutoPasteWindow.allCases) { window in
                        Text(window.title).tag(window.rawValue)
                    }
                } label: {
                    SettingsRow(
                        title: "自动粘贴搜索框",
                        subtitle: "刚复制过内容时，唤出面板自动把它填进搜索框。",
                        icon: { SettingsRowIcon(systemImage: "doc.on.clipboard") }
                    )
                }

                Picker(selection: $autoClearMinutes) {
                    ForEach(PaletteAutoBehavior.AutoClearIdle.allCases) { idle in
                        Text(idle.title).tag(idle.rawValue)
                    }
                } label: {
                    SettingsRow(
                        title: "自动清空搜索框",
                        subtitle: "搜索框内容放置超过这个时间后，下次打开面板时清空。",
                        icon: { SettingsRowIcon(systemImage: "eraser") }
                    )
                }
            } header: {
                Text("面板行为")
            } footer: {
                Text("两项都只在打开面板的那一刻生效，不会打断你正在进行的输入。")
            }

            keyboardLayoutSection

            backupSection
        }
        .formStyle(.grouped)
    }

    // MARK: - 备份与恢复

    /// 备份文件类型：自定义扩展名，内容是 plist
    private static let backupType = UTType(filenameExtension: "quicksettings", conformingTo: .propertyList)
        ?? .propertyList

    private var backupSection: some View {
        Section {
            SettingsRow(
                title: "设置备份",
                subtitle: "把快捷键、插件开关、别名与各插件的偏好存成一个文件，换电脑或重装后导入即可恢复。",
                icon: { SettingsRowIcon(systemImage: "externaldrive") }
            ) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Button("导出…") { Task { await exportBackup() } }
                    Button("导入…") { Task { await importBackup() } }
                }
            }
            if let status = backupStatus {
                backupStatusRow(status)
            }
        } header: {
            Text("备份与恢复")
        } footer: {
            Text("剪贴板历史等数据库内容与 API Key（钥匙串）不在备份里。导入会覆盖同名设置，并先把当前设置另存一份。")
        }
    }

    @ViewBuilder
    private func backupStatusRow(_ status: BackupStatus) -> some View {
        switch status {
        case .exported(let name):
            Label("已导出到 \(name)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(DesignTokens.Colors.success)
        case .imported(let summary):
            HStack {
                Label(
                    "已导入 \(summary.applied) 项" + (summary.skipped > 0 ? "，忽略 \(summary.skipped) 项不适用的条目" : ""),
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(DesignTokens.Colors.success)
                Spacer()
                Button("立即重启生效") { dataSource.restartApplication() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignTokens.Colors.destructive)
        }
    }

    private func exportBackup() async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.backupType]
        panel.nameFieldStringValue = "Quick 设置备份.quicksettings"
        panel.canCreateDirectories = true
        guard await panel.begin() == .OK, let url = panel.url else { return }
        do {
            try dataSource.exportSettings().write(to: url, options: .atomic)
            backupStatus = .exported(url.lastPathComponent)
        } catch {
            backupStatus = .failed("导出失败：\(error.localizedDescription)")
        }
    }

    private func importBackup() async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.backupType, .propertyList]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard await panel.begin() == .OK, let url = panel.url else { return }
        do {
            // 先看体积再读：选错成一个几个 GB 的文件时不该把它整个读进内存
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= SettingsBackup.maximumFileSize else {
                backupStatus = .failed("文件过大，不像是 Quick 的设置备份")
                return
            }
            let summary = try dataSource.importSettings(Data(contentsOf: url))
            backupStatus = .imported(summary)
        } catch {
            backupStatus = .failed("导入失败：\(error.localizedDescription)")
        }
    }

    /// 强制键盘布局
    ///
    /// 中文输入法用户在拼音状态下按 ⌥Space，打出来的是拼音串 —— 切到 ABC 才能直接输命令。
    /// 面板关闭时会还原原来的布局。
    private var keyboardLayoutSection: some View {
        Section {
            Picker(selection: forcedLayoutBinding) {
                Text("不切换").tag("")
                ForEach(dataSource.keyboardLayouts) { layout in
                    Text(layout.name).tag(layout.id)
                }
            } label: {
                SettingsRow(
                    title: "强制键盘布局",
                    subtitle: "面板打开期间切换到指定键盘布局，关闭后还原。留空则不切换。",
                    icon: { SettingsRowIcon(systemImage: "keyboard.badge.ellipsis") }
                )
            }
        } header: {
            Text("输入法")
        } footer: {
            Text("列表来自系统已启用的键盘布局；在「系统设置 → 键盘 → 输入法」里增删。")
        }
    }

    /// 强制布局的绑定（空串代表不切换）
    private var forcedLayoutBinding: Binding<String> {
        Binding(
            get: { dataSource.forcedKeyboardLayoutID ?? "" },
            set: { dataSource.setForcedKeyboardLayout($0.isEmpty ? nil : $0) }
        )
    }
}
