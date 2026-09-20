// ApplicationsSettingsPane.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import SwiftUI

/// 应用程序设置面板
///
/// 参考 Tinycast 设计：
/// - 顶部为搜索范围设置（SearchScopesSection）
/// - 下方为系统已安装应用列表
/// - 支持筛选应用
/// - 每行支持配置别名（Alias）以及独立全局快捷键（ShortcutRecorder）
struct ApplicationsSettingsPane: View {

    let dataSource: any SettingsDataSource

    @State private var query = ""
    @State private var showAll = false
    @State private var refreshCount = 0
    @State private var subscription: EventSubscription?

    private var allApps: [SettingsAppItem] {
        _ = refreshCount
        return dataSource.indexedApplications
    }

    private var filteredApps: [SettingsAppItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            return allApps.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed)
                    || ($0.alias?.localizedCaseInsensitiveContains(trimmed) ?? false)
                    || $0.bundleID.localizedCaseInsensitiveContains(trimmed)
            }
        }
        if showAll {
            return allApps
        }
        // 优先展示已配置别名或快捷键的应用，其余补齐前 30 个
        let customized = allApps.filter { $0.alias != nil || $0.shortcutKeycaps != nil }
        let customizedIDs = Set(customized.map(\.id))
        let remaining = allApps.filter { !customizedIDs.contains($0.id) }.prefix(30)
        return customized + remaining
    }

    var body: some View {
        let apps = filteredApps
        let totalCount = allApps.count

        return Form {
            SearchScopesSection(dataSource: dataSource)

            Section {
                // 搜索过滤框
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索应用…", text: $query)
                        .textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)

                if apps.isEmpty {
                    Text(query.isEmpty ? "暂无已索引的应用程序。" : "没有匹配「\(query)」的应用。")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, DesignTokens.Spacing.md)
                } else {
                    ForEach(apps) { app in
                        AppItemRow(app: app, dataSource: dataSource)
                    }

                    if query.isEmpty && !showAll && totalCount > apps.count {
                        Button("显示全部 \(totalCount) 个应用…") {
                            showAll = true
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("应用程序（\(totalCount) 个）")
            } footer: {
                Text("为应用设置自定义别名（如 'code' 对应 VS Code）或全局快捷键以快速启动。")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if subscription == nil {
                subscription = EventBus.shared.on(AppIndexRefreshedEvent.self) { _ in
                    Task { @MainActor in
                        refreshCount += 1
                    }
                }
            }
            if allApps.isEmpty {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    refreshCount += 1
                }
            }
        }
    }
}

private struct AppItemRow: View {
    let app: SettingsAppItem
    let dataSource: any SettingsDataSource

    @State private var alias: String
    @State private var iconImage: NSImage?

    init(app: SettingsAppItem, dataSource: any SettingsDataSource) {
        self.app = app
        self.dataSource = dataSource
        _alias = State(initialValue: app.alias ?? "")
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // 图标
            Group {
                if let iconImage {
                    Image(nsImage: iconImage)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "app")
                        .font(DesignTokens.Typography.iconGlyph)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
            .frame(width: 20, height: 20)

            // 应用名与类型
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .lineLimit(1)
                Text(app.isSystemApp ? "系统应用" : "应用程序")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: DesignTokens.Spacing.md)

            // 别名输入框（Tinycast 风格）
            AliasField(
                placeholder: "Add Alias",
                text: $alias,
                onChange: { newValue in
                    dataSource.setAppAlias(newValue, for: app.bundleID)
                }
            )

            // 快捷键录制
            ShortcutRecorder(
                keycaps: app.shortcutKeycaps,
                onRecord: { keyCode, modifiers in
                    dataSource.setAppShortcut(keyCode: keyCode, carbonModifiers: modifiers, for: app.bundleID)
                },
                onClear: {
                    dataSource.clearAppShortcut(for: app.bundleID)
                }
            )
        }
        .padding(.vertical, 2)
        .onAppear {
            if iconImage == nil {
                iconImage = dataSource.appIcon(for: app.path)
            }
        }
    }
}
