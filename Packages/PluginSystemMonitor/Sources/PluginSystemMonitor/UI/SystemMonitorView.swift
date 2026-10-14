// SystemMonitorView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import QuickUI
import SwiftUI

/// 系统监控主视图：左侧分类导航 + 右侧明细（对齐 Raycast System Monitor）
struct SystemMonitorView: View {

    let scanner: ProcessScanner

    @AppStorage(PluginSettingKey.SystemMonitor.defaultTab) private var defaultTabRaw =
        SystemMonitorPreferences.defaultTab.rawValue
    @AppStorage(PluginSettingKey.SystemMonitor.displayMode) private var modeRaw =
        SystemMonitorPreferences.defaultMode.rawValue

    @State private var selectedTab: SystemMonitorTab = SystemMonitorPreferences.defaultTab

    private var usageMode: UsageDisplayMode {
        SystemMonitorPreferences.displayMode(
            storedValue: modeRaw, fallback: SystemMonitorPreferences.defaultMode)
    }
    private var cpuMode: UsageDisplayMode { usageMode }
    private var memoryMode: UsageDisplayMode { usageMode }
    private var diskMode: UsageDisplayMode { usageMode }
    private var batteryMode: UsageDisplayMode { SystemMonitorPreferences.batteryMode }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: DesignTokens.Size.monitorSidebar)
            Divider().opacity(DesignTokens.Opacity.divider)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
        .onAppear {
            selectedTab = SystemMonitorPreferences.tab(storedValue: defaultTabRaw)
            scanner.noteViewAppeared()
        }
        .onDisappear {
            scanner.noteViewDisappeared()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: DesignTokens.Spacing.xxs) {
                    ForEach(SystemMonitorTab.allCases) { tab in
                        sidebarRow(tab)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.md)
            }
        }
    }

    private func sidebarRow(_ tab: SystemMonitorTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: tab.icon)
                    .font(DesignTokens.Typography.sidebarIcon)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .frame(width: DesignTokens.Size.sidebarIconSlot)
                Text(tab.title)
                    .font(DesignTokens.Typography.bar)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: DesignTokens.Spacing.xs)
                Text(sidebarAccessory(for: tab))
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(sidebarAccessoryColor(for: tab))
                    .lineLimit(1)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.row, style: .continuous)
                    .fill(isSelected ? DesignTokens.Colors.rowHover : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sidebarAccessory(for tab: SystemMonitorTab) -> String {
        switch tab {
        case .systemInfo:
            return ""
        case .cpu:
            guard let used = scanner.cpuUsagePercent else { return "—" }
            return SystemMetrics.accessoryPercent(used: used, mode: cpuMode)
        case .memory:
            guard let memory = scanner.memory else { return "—" }
            let displayed = SystemMetrics.displayedPercent(used: memory.usedPercent, mode: memoryMode)
            let amountGB =
                memoryMode == .free
                ? Int(((memory.totalMB - memory.usedMB) / 1024).rounded())
                : Int((memory.usedMB / 1024).rounded())
            return "\(SystemMetrics.percent(displayed)) (~ \(amountGB) GB)"
        case .disk:
            guard let disk = scanner.disks.first else { return "—" }
            return SystemMetrics.accessoryPercent(
                used: disk.usedPercent, mode: diskMode, suffixWhenFree: " free")
        case .power:
            guard let power = scanner.power, power.hasBattery, let percent = power.batteryPercent
            else {
                return "N/A"
            }
            return PowerStatsParsing.displayedLevel(percent, mode: batteryMode)
        case .network:
            return scanner.networkThroughput?.sidebarSummary ?? "—"
        case .temperature:
            return scanner.temperature?.sidebarSummary ?? "—"
        }
    }

    private func sidebarAccessoryColor(for tab: SystemMonitorTab) -> Color {
        switch tab {
        case .systemInfo:
            return DesignTokens.Colors.textTertiary
        case .cpu:
            guard let used = scanner.cpuUsagePercent else {
                return DesignTokens.Colors.textTertiary
            }
            let displayed = SystemMetrics.displayedPercent(used: used, mode: cpuMode)
            return color(
                for: SystemMetrics.tone(
                    forPressure: SystemMetrics.pressure(fromDisplayed: displayed, mode: cpuMode)))
        case .memory:
            guard let memory = scanner.memory else {
                return DesignTokens.Colors.textTertiary
            }
            let displayed = SystemMetrics.displayedPercent(used: memory.usedPercent, mode: memoryMode)
            return color(
                for: SystemMetrics.tone(
                    forPressure: SystemMetrics.pressure(fromDisplayed: displayed, mode: memoryMode)))
        case .disk:
            guard let disk = scanner.disks.first else {
                return DesignTokens.Colors.textTertiary
            }
            let displayed = SystemMetrics.displayedPercent(used: disk.usedPercent, mode: diskMode)
            return color(
                for: SystemMetrics.tone(
                    forPressure: SystemMetrics.pressure(fromDisplayed: displayed, mode: diskMode)))
        case .power:
            guard let power = scanner.power, power.hasBattery, let percent = power.batteryPercent
            else {
                return DesignTokens.Colors.textTertiary
            }
            let displayed = Double(batteryMode == .free ? percent : max(0, 100 - percent))
            return color(
                for: SystemMetrics.tone(
                    forPressure: SystemMetrics.pressure(fromDisplayed: displayed, mode: .free)))
        case .network:
            return DesignTokens.Colors.textSecondary
        case .temperature:
            guard let avg = scanner.temperature?.cpuAverage else {
                return DesignTokens.Colors.textTertiary
            }
            return color(for: TemperatureParsing.severity(celsius: avg))
        }
    }

    private func color(for tone: SystemMetrics.PressureTone) -> Color {
        switch tone {
        case .normal: DesignTokens.Colors.success
        case .elevated: DesignTokens.Colors.progress
        case .warning: DesignTokens.Colors.warning
        case .critical: DesignTokens.Colors.destructive
        case .muted: DesignTokens.Colors.textTertiary
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selectedTab {
        case .systemInfo:
            SystemInfoDetailView(scanner: scanner)
        case .cpu:
            CPUDetailView(scanner: scanner, mode: cpuMode)
        case .memory:
            MemoryDetailView(scanner: scanner, mode: memoryMode)
        case .disk:
            DiskDetailView(scanner: scanner, mode: diskMode)
        case .power:
            PowerDetailView(scanner: scanner, mode: batteryMode)
        case .network:
            NetworkDetailView(scanner: scanner)
        case .temperature:
            TemperatureDetailView(scanner: scanner)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        ActionPillBar {
            ActionPillButton(title: "打开活动监视器", keyCap: "↵") {
                openActivityMonitor()
            }
            .keyboardShortcut(.return, modifiers: [])
        }
    }

    private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.open(url)
    }
}
