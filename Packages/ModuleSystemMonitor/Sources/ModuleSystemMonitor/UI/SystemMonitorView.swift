// SystemMonitorView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickUI
import SwiftUI

/// 系统监控视图
struct SystemMonitorView: View {

    let scanner: ProcessScanner
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("进程").tag(0)
                Text("系统信息").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(DesignTokens.Spacing.md)

            if selectedTab == 0 {
                processTab
            } else {
                systemInfoTab
            }
        }
        .task {
            await scanner.refreshProcesses()
            scanner.refreshSystemInfo()
        }
    }

    private var processTab: some View {
        VStack(spacing: 0) {
            HStack {
                Text("进程名").font(DesignTokens.Typography.sectionHeader).frame(maxWidth: .infinity, alignment: .leading)
                Text("CPU").font(DesignTokens.Typography.sectionHeader).frame(width: 60)
                Text("内存").font(DesignTokens.Typography.sectionHeader).frame(width: 60)
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.vertical, DesignTokens.Spacing.sm)

            Divider().opacity(0.3)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(scanner.processes) { proc in
                        HStack {
                            Text(proc.name).font(DesignTokens.Typography.code).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Text(proc.cpuUsage).font(DesignTokens.Typography.code).frame(width: 60)
                            Text(proc.memoryUsage).font(DesignTokens.Typography.code).frame(width: 60)
                        }
                        .padding(.horizontal, DesignTokens.Spacing.xl)
                        .padding(.vertical, DesignTokens.Spacing.xs)
                    }
                }
            }
        }
    }

    private var systemInfoTab: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            if let info = scanner.systemInfo {
                infoRow("主机名", value: info.hostname)
                infoRow("系统版本", value: info.osVersion)
                infoRow("运行时间", value: info.uptime)
                infoRow("CPU 核心数", value: "\(info.cpuCount)")
                infoRow("总内存", value: info.memoryTotal)
            }
            Spacer()
        }
        .padding(DesignTokens.Spacing.xl)
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(DesignTokens.Typography.code)
                .textSelection(.enabled)
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.row))
    }
}
