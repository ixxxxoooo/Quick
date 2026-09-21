// ShortcutsPane.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import SwiftUI

/// 快捷键设置面板
///
/// 参考 Fasty / Raycast 设计：
/// - 顶部为主面板全局唤出快捷键（默认 ⌥Space）
/// - 支持按类别浏览与搜索全部插件、系统操作与自定义终端命令
/// - 每项均支持录制独立全局快捷键，按下即可直接唤醒或置顶打开对应插件/执行命令
struct ShortcutsPane: View {

    let dataSource: any SettingsDataSource

    enum ItemCategory: String, CaseIterable, Identifiable {
        case all = "全部"
        case plugins = "插件"
        case systemActions = "系统操作"
        case customCommands = "终端命令"

        var id: Self { self }
    }

    @State private var query = ""
    @State private var selectedCategory: ItemCategory = .all
    @State private var showOnlyBound = false

    var body: some View {
        Form {
            globalSection
            bindingsSection
        }
        .formStyle(.grouped)
    }

    /// 主面板全局快捷键
    private var globalSection: some View {
        Section {
            SettingsRow(
                title: "唤出主面板",
                subtitle: "在任何应用中按下即可显示或隐藏 Quick 命令面板。",
                icon: { SettingsRowIcon(systemImage: "keyboard") }
            ) {
                ShortcutRecorder(
                    keycaps: dataSource.globalShortcutKeycaps,
                    onRecord: { keyCode, modifiers in
                        dataSource.setGlobalShortcut(keyCode: keyCode, carbonModifiers: modifiers)
                    },
                    onClear: {
                        dataSource.clearGlobalShortcut()
                    }
                )
            }
        } header: {
            Text("主面板快捷键")
        } footer: {
            Text("默认快捷键为 ⌥Space (Option+Space)。")
        }
    }

    /// 快捷唤醒命令绑定
    private var bindingsSection: some View {
        Section {
            // 搜索与过滤筛选行
            VStack(spacing: DesignTokens.Spacing.sm) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(DesignTokens.Typography.inlineIcon)
                        .foregroundStyle(.secondary)
                    TextField("搜索命令或插件…", text: $query)
                        .textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(DesignTokens.Typography.inlineIcon)
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.xs)

                HStack {
                    Picker("分类", selection: $selectedCategory) {
                        ForEach(ItemCategory.allCases) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("仅已绑定", isOn: $showOnlyBound)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                }
            }

            // 渲染过滤后的条目
            let items = filteredItems
            if items.isEmpty {
                Text("未找到匹配的命令或插件。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, DesignTokens.Spacing.md)
            } else {
                ForEach(items) { item in
                    ShortcutItemRow(item: item, dataSource: dataSource)
                }
            }
        } header: {
            Text("命令与插件独立快捷键 (\(filteredItems.count))")
        } footer: {
            Text("为指定插件或命令绑定全局快捷键后，可在任意应用中按下快捷键直接唤醒并置顶打开该插件或运行命令，无需先打开搜索框。")
        }
    }

    /// 统一列表项结构
    struct BindableItem: Identifiable {
        enum Kind {
            case plugin(id: String)
            case systemAction(id: String)
            case customCommand(id: UUID)
        }

        let id: String
        let name: String
        let subtitle: String
        let icon: String
        let category: ItemCategory
        let kind: Kind
        let shortcutKeycaps: [String]?
    }

    private var allItems: [BindableItem] {
        var result: [BindableItem] = []

        // 1. 插件
        for p in dataSource.pluginEntries {
            let keycaps = dataSource.pluginShortcutKeycaps(for: p.id)
            let sub =
                p.triggerWords.isEmpty ? p.description : "唤醒词: \(p.triggerWords.joined(separator: ", "))"
            result.append(
                BindableItem(
                    id: "plugin.\(p.id)",
                    name: p.name,
                    subtitle: sub,
                    icon: p.icon,
                    category: .plugins,
                    kind: .plugin(id: p.id),
                    shortcutKeycaps: keycaps
                )
            )
        }

        // 2. 系统操作
        for a in dataSource.systemActions {
            result.append(
                BindableItem(
                    id: "sys.\(a.id)",
                    name: a.title,
                    subtitle: "系统控制",
                    icon: a.icon,
                    category: .systemActions,
                    kind: .systemAction(id: a.id),
                    shortcutKeycaps: a.shortcutKeycaps
                )
            )
        }

        // 3. 终端命令
        for c in dataSource.customCommands {
            result.append(
                BindableItem(
                    id: "cmd.\(c.id.uuidString)",
                    name: c.name,
                    subtitle: c.command,
                    icon: "terminal",
                    category: .customCommands,
                    kind: .customCommand(id: c.id),
                    shortcutKeycaps: c.shortcutKeycaps
                )
            )
        }

        return result
    }

    private var filteredItems: [BindableItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return allItems.filter { item in
            // 分类过滤
            if selectedCategory != .all && item.category != selectedCategory {
                return false
            }
            // 仅已绑定过滤
            if showOnlyBound && (item.shortcutKeycaps == nil || item.shortcutKeycaps?.isEmpty == true) {
                return false
            }
            // 搜索过滤
            if !trimmed.isEmpty {
                return item.name.localizedCaseInsensitiveContains(trimmed)
                    || item.subtitle.localizedCaseInsensitiveContains(trimmed)
            }
            return true
        }
    }
}

private struct ShortcutItemRow: View {
    let item: ShortcutsPane.BindableItem
    let dataSource: any SettingsDataSource

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: item.icon)
                .font(DesignTokens.Typography.iconGlyph)
                .foregroundStyle(Color.accentColor)
                .frame(width: DesignTokens.Size.rowIcon, height: DesignTokens.Size.rowIcon)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text(item.name)
                        .lineLimit(1)
                    badge(for: item.category)
                }
                Text(item.subtitle)
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: DesignTokens.Spacing.md)

            recorderView
        }
        .padding(.vertical, DesignTokens.Spacing.xxs)
    }

    @ViewBuilder
    private var recorderView: some View {
        switch item.kind {
        case .plugin(let id):
            ShortcutRecorder(
                keycaps: dataSource.pluginShortcutKeycaps(for: id),
                onRecord: { keyCode, modifiers in
                    dataSource.setPluginShortcut(keyCode: keyCode, carbonModifiers: modifiers, for: id)
                },
                onClear: {
                    dataSource.clearPluginShortcut(for: id)
                }
            )
        case .systemAction(let id):
            ShortcutRecorder(
                keycaps: item.shortcutKeycaps,
                onRecord: { keyCode, modifiers in
                    dataSource.setSystemActionShortcut(keyCode: keyCode, carbonModifiers: modifiers, for: id)
                },
                onClear: {
                    dataSource.clearSystemActionShortcut(for: id)
                }
            )
        case .customCommand(let id):
            ShortcutRecorder(
                keycaps: item.shortcutKeycaps,
                onRecord: { keyCode, modifiers in
                    dataSource.setCustomCommandShortcut(keyCode: keyCode, carbonModifiers: modifiers, for: id)
                },
                onClear: {
                    dataSource.clearCustomCommandShortcut(for: id)
                }
            )
        }
    }

    private func badge(for category: ShortcutsPane.ItemCategory) -> some View {
        Text(category.rawValue)
            .font(DesignTokens.Typography.keyCap)
            .foregroundStyle(DesignTokens.Colors.textTertiary)
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                    .fill(DesignTokens.Colors.controlSurface)
            )
    }
}
