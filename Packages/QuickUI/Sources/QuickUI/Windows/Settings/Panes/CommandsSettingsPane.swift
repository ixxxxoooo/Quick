// CommandsSettingsPane.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 命令与终端设置面板
///
/// 参考 Tinycast 设计：
/// - 支持开启/关闭在启动器主搜索中运行 Shell 命令（Run Shell Command）
/// - 支持用户添加、编辑、删除自定义 Shell 脚本与命令
/// - 每条自定义命令支持配置别名与独立快捷键
struct CommandsSettingsPane: View {

    let dataSource: any SettingsDataSource
    var embedded = false

    @State private var runShellFallback: Bool
    @State private var showingAddSheet = false
    @State private var editingCommand: SettingsCustomCommandItem?
    @AppStorage(PluginSettingKey.Shell.preferredTerminal) private var preferredTerminal = "com.apple.Terminal"

    init(dataSource: any SettingsDataSource, embedded: Bool = false) {
        self.dataSource = dataSource
        self.embedded = embedded
        _runShellFallback = State(initialValue: dataSource.isRunShellFallbackEnabled)
    }

    var body: some View {
        Group {
            if embedded {
                sections
            } else {
                Form {
                    sections
                }
                .formStyle(.grouped)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            CommandEditorSheet(dataSource: dataSource, existingCommand: nil)
        }
        .sheet(item: $editingCommand) { cmd in
            CommandEditorSheet(dataSource: dataSource, existingCommand: cmd)
        }
    }

    @ViewBuilder
    private var sections: some View {
        let commands = dataSource.customCommands
        Section {
            Toggle(isOn: $runShellFallback) {
                SettingsRow(
                    title: "启用终端命令回退",
                    subtitle: "在主面板输入任意命令或以 > 开头，可直接在终端中执行。",
                    icon: { SettingsRowIcon(systemImage: "terminal") }
                )
            }
            .onChange(of: runShellFallback) { _, newValue in
                dataSource.setRunShellFallbackEnabled(newValue)
            }

            Picker(selection: $preferredTerminal) {
                Text("终端 (Terminal)").tag("com.apple.Terminal")
                Text("iTerm2").tag("com.googlecode.iterm2")
                Text("Warp").tag("dev.warp.Warp-Stable")
                Text("Kitty").tag("net.kovidgoyal.kitty")
                Text("Alacritty").tag("org.alacritty")
            } label: {
                SettingsRow(
                    title: "默认终端",
                    subtitle: "运行 Shell 命令时打开的终端应用。",
                    icon: { SettingsRowIcon(systemImage: "rectangle.topthird.inset.filled") }
                )
            }
        } header: {
            Text("终端集成")
        }

        Section {
            if commands.isEmpty {
                Text("暂无自定义命令。点击下方按钮添加常用终端脚本。")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, DesignTokens.Spacing.sm)
            } else {
                ForEach(commands) { command in
                    CustomCommandRow(
                        command: command,
                        dataSource: dataSource,
                        onEdit: { editingCommand = command },
                        onDelete: { dataSource.deleteCustomCommand(id: command.id) }
                    )
                }
            }

            Button("添加自定义 Shell 命令…") {
                showingAddSheet = true
            }
        } header: {
            Text("自定义 Shell 命令 (\(commands.count))")
        } footer: {
            Text("这些命令可以在主面板里搜到。快捷键到「快捷键」页添加。")
        }
    }
}

private struct CustomCommandRow: View {
    let command: SettingsCustomCommandItem
    let dataSource: any SettingsDataSource
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var alias: String

    init(
        command: SettingsCustomCommandItem,
        dataSource: any SettingsDataSource,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.command = command
        self.dataSource = dataSource
        self.onEdit = onEdit
        self.onDelete = onDelete
        _alias = State(initialValue: command.alias ?? "")
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "terminal")
                .font(DesignTokens.Typography.iconGlyph)
                .foregroundStyle(command.isEnabled ? Color.accentColor : .secondary)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(command.name)
                    .lineLimit(1)
                Text(command.command)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: DesignTokens.Spacing.md)

            TextField("设置别名", text: $alias)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .onChange(of: alias) { _, newValue in
                    dataSource.updateCustomCommand(
                        id: command.id,
                        name: command.name,
                        command: command.command,
                        isEnabled: command.isEnabled,
                        alias: newValue,
                        workingDirectory: command.workingDirectory,
                        loadsShellEnvironment: command.loadsShellEnvironment
                    )
                }

            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .font(DesignTokens.Typography.inlineIcon)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("编辑")

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(DesignTokens.Typography.inlineIcon)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .help("删除")
        }
        .padding(.vertical, 2)
    }
}

/// 自定义命令编辑弹窗
private struct CommandEditorSheet: View {
    let dataSource: any SettingsDataSource
    let existingCommand: SettingsCustomCommandItem?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var command: String = ""
    @State private var workingDirectory: String = ""
    @State private var loadsShellEnvironment = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text(existingCommand == nil ? "添加自定义 Shell 命令" : "编辑 Shell 命令")
                .font(.headline)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("命令名称")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("例如：清理项目缓存", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("Shell 命令行 (zsh)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("例如：git clean -fdx", text: $command)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("工作目录（可选，留空则为主目录）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("例如：~/Projects", text: $workingDirectory)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle(isOn: $loadsShellEnvironment) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("加载 Shell 配置（.zshrc）")
                    Text("打开后别名与 .zshrc 里的 PATH 才生效，代价是每次执行多一份加载时间。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("保存") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    name.trimmingCharacters(in: .whitespaces).isEmpty
                        || command.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 420)
        .onAppear {
            if let existingCommand {
                name = existingCommand.name
                command = existingCommand.command
                workingDirectory = existingCommand.workingDirectory ?? ""
                loadsShellEnvironment = existingCommand.loadsShellEnvironment
            }
        }
    }

    private func save() {
        let dir = workingDirectory.trimmingCharacters(in: .whitespaces).isEmpty ? nil : workingDirectory
        if let existingCommand {
            dataSource.updateCustomCommand(
                id: existingCommand.id,
                name: name,
                command: command,
                isEnabled: existingCommand.isEnabled,
                alias: existingCommand.alias,
                workingDirectory: dir,
                loadsShellEnvironment: loadsShellEnvironment
            )
        } else {
            dataSource.addCustomCommand(
                name: name,
                command: command,
                workingDirectory: dir,
                loadsShellEnvironment: loadsShellEnvironment
            )
        }
    }
}
