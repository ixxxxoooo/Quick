// SearchPane.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 主搜索搜哪些来源，以及应用索引目录
struct SearchPane: View {

    let dataSource: any SettingsDataSource
    @State private var enabled: [String: Bool] = [:]

    var body: some View {
        Form {
            Section {
                ForEach(dataSource.searchSources) { source in
                    Toggle(
                        isOn: Binding(
                            get: { enabled[source.id] ?? source.isEnabled },
                            set: { newValue in
                                enabled[source.id] = newValue
                                dataSource.setSearchSourceEnabled(source.id, enabled: newValue)
                            }
                        )
                    ) {
                        SettingsRow(
                            title: source.title,
                            subtitle: source.subtitle,
                            icon: { SettingsRowIcon(systemImage: source.icon) }
                        )
                    }
                }
            } header: {
                Text("搜索来源")
            } footer: {
                Text("关掉的来源不会出现在主面板搜索里。插件本身仍可从「插件」页打开。")
            }

            SearchScopesSection(dataSource: dataSource)
        }
        .formStyle(.grouped)
        .onAppear {
            enabled = Dictionary(
                uniqueKeysWithValues: dataSource.searchSources.map { ($0.id, $0.isEnabled) }
            )
        }
    }
}
