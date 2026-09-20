// SearchScopesSection.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import SwiftUI
import UniformTypeIdentifiers

/// 启动器应用搜索范围设置分区
///
/// 参考 Tinycast 设计：
/// - 列出所有索引目录/应用程序包
/// - 标记已不存在的失效目录（橙色感叹号）
/// - 支持「添加…」（通过 NSOpenPanel 选择目录或 .app）
/// - 支持「恢复默认」
struct SearchScopesSection: View {

    let dataSource: any SettingsDataSource

    @State private var scopes: [String]
    @State private var missingScopes: Set<String> = []

    init(dataSource: any SettingsDataSource) {
        self.dataSource = dataSource
        _scopes = State(initialValue: dataSource.searchScopes)
    }

    var body: some View {
        Section {
            ForEach(scopes, id: \.self) { scope in
                ScopeRow(scope: scope, isMissing: missingScopes.contains(scope)) {
                    removeScope(scope)
                }
            }

            HStack(spacing: DesignTokens.Spacing.lg) {
                Button("Add…", action: addScopes)
                    .help("Add folders or application bundles to search")

                Button("Restore Defaults") {
                    dataSource.restoreDefaultSearchScopes()
                    scopes = dataSource.searchScopes
                    refreshMissing()
                }
            }
        } header: {
            Text("Search Scopes")
        } footer: {
            Text(
                "Quick scans these directories for applications. Custom locations are indexed automatically.")
        }
        .onAppear(perform: refreshMissing)
    }

    private func refreshMissing() {
        let fm = FileManager.default
        missingScopes = Set(
            scopes.filter {
                let expanded = ($0 as NSString).expandingTildeInPath
                return !fm.fileExists(atPath: expanded)
            }
        )
    }

    private func removeScope(_ scope: String) {
        scopes.removeAll { $0 == scope }
        dataSource.setSearchScopes(scopes)
        refreshMissing()
    }

    private func addScopes() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "添加"
        panel.message = "选择要包含在启动器中的文件夹或应用程序包"

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }

        let newPaths = panel.urls.map { ($0.path as NSString).abbreviatingWithTildeInPath }
        var current = scopes
        for p in newPaths where !current.contains(p) {
            current.append(p)
        }
        scopes = current
        dataSource.setSearchScopes(scopes)
        refreshMissing()
    }
}

private struct ScopeRow: View {
    let scope: String
    let isMissing: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: scope.hasSuffix(".app") ? "app" : "folder")
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)

            Text(scope)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isMissing ? .secondary : .primary)

            Spacer()

            if isMissing {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("该路径当前不存在")
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("移除 \(scope)")
        }
    }
}
