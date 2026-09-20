// WindowManagementSettingsPane.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import SwiftUI

/// 窗口管理设置面板
///
/// 完全参考 Tinycast WindowManagementSettingsView（见图 1）：
/// - Section 1 (Window Management): Enable window management + Show in launcher
/// - Section 2 (Options): Cycling + Gap between windows
/// - Section 3 (Window Layouts): Show layouts in launcher + New Layout + Create Layout from Current Windows
/// - Section 4 (Layout Commands): 窗口平铺命令列表，支持自定义快捷键与在启动器中显示
struct WindowManagementSettingsPane: View {

    let dataSource: any SettingsDataSource

    @AppStorage("windowManager.enabled") private var isEnabled = false
    @AppStorage("windowManager.showInLauncher") private var showInLauncher = true
    @AppStorage("windowManager.cycling") private var cycling = "None"
    @AppStorage("windowManager.gap") private var gap = 0
    @AppStorage("windowManager.showLayoutsInLauncher") private var showLayoutsInLauncher = true

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $isEnabled) {
                    Text("Enable window management")
                    Text(
                        "Moves the window you were last in, using the Accessibility permission Quick already uses to paste."
                    )
                }
                Toggle(isOn: $showInLauncher) {
                    Text("Show in launcher")
                    Text("Find the window commands in launcher search.")
                }
                .settingsEnabled(isEnabled)
            }

            Group {
                optionsSection
                windowLayoutsSection
                layoutCommandsSection
            }
            .settingsEnabled(isEnabled)
        }
        .formStyle(.grouped)
    }

    private var optionsSection: some View {
        Section {
            Picker(selection: $cycling) {
                Text("None").tag("None")
                Text("Halves and Thirds").tag("Halves and Thirds")
                Text("Across Displays").tag("Across Displays")
            } label: {
                Text("Cycling")
                Text(cycleDetail(for: cycling))
            }

            LabeledContent {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text("\(gap) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Stepper("Gap between windows", value: $gap, in: 0...64, step: 2)
                        .labelsHidden()
                }
            } label: {
                Text("Gap between windows")
                Text("Points left between tiled windows and around the screen edge.")
            }
        } header: {
            Text("Options")
        }
    }

    private func cycleDetail(for cycling: String) -> String {
        switch cycling {
        case "Halves and Thirds":
            return "Triggering a half again steps it through a third and two thirds."
        case "Across Displays":
            return "Triggering a half again walks it to the next half across your displays, wrapping around."
        default:
            return "Triggering a half again re-applies the same frame."
        }
    }

    private var windowLayoutsSection: some View {
        Section {
            Toggle(isOn: $showLayoutsInLauncher) {
                Text("Show layouts in launcher")
                Text("Find your layouts in launcher search, beside the window commands.")
            }

            Text("Save an arrangement once, then put every window back with one shortcut.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("New Layout") {
                // 新建布局
            }

            Button("Create Layout from Current Windows") {
                // 根据当前窗口创建布局
            }
        } header: {
            Text("Window Layouts")
        } footer: {
            Text("A layout puts named apps at fixed sizes on chosen displays, in one pass.")
        }
    }

    private var layoutCommandsSection: some View {
        Section {
            ForEach(WindowLayoutItem.defaults) { item in
                WindowCommandRow(item: item)
            }
        } header: {
            Text("Layout Commands")
        }
    }
}

private struct WindowLayoutItem: Identifiable {
    let id: String
    let name: String
    let icon: String

    static let defaults: [WindowLayoutItem] = [
        WindowLayoutItem(id: "leftHalf", name: "Left Half", icon: "rectangle.lefthalf.filled"),
        WindowLayoutItem(id: "rightHalf", name: "Right Half", icon: "rectangle.righthalf.filled"),
        WindowLayoutItem(id: "topHalf", name: "Top Half", icon: "rectangle.tophalf.filled"),
        WindowLayoutItem(id: "bottomHalf", name: "Bottom Half", icon: "rectangle.bottomhalf.filled"),
        WindowLayoutItem(id: "maximize", name: "Maximize", icon: "arrow.up.left.and.arrow.down.right"),
        WindowLayoutItem(id: "center", name: "Center", icon: "rectangle.center.inset.filled"),
        WindowLayoutItem(id: "topLeft", name: "Top Left", icon: "rectangle.inset.topleading.filled"),
        WindowLayoutItem(id: "topRight", name: "Top Right", icon: "rectangle.inset.toptrailing.filled"),
        WindowLayoutItem(id: "bottomLeft", name: "Bottom Left", icon: "rectangle.inset.bottomleading.filled"),
        WindowLayoutItem(
            id: "bottomRight", name: "Bottom Right", icon: "rectangle.inset.bottomtrailing.filled")
    ]
}

private struct WindowCommandRow: View {
    let item: WindowLayoutItem

    @AppStorage private var isVisible: Bool
    @State private var alias: String = ""

    init(item: WindowLayoutItem) {
        self.item = item
        _isVisible = AppStorage(wrappedValue: true, "windowManager.cmd.\(item.id).visible")
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: item.icon)
                .font(DesignTokens.Typography.iconGlyph)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, height: 20)

            Text(item.name)
                .lineLimit(1)

            Spacer(minLength: DesignTokens.Spacing.md)

            AliasField(
                placeholder: "Add Alias",
                text: $alias
            )

            ShortcutRecorder(
                keycaps: nil,
                onRecord: { _, _ in },
                onClear: {}
            )

            Toggle("", isOn: $isVisible)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help("Show in launcher")
                .accessibilityLabel("Show \(item.name) in launcher")
        }
        .padding(.vertical, 2)
    }
}
