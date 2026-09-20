// SystemMonitorModule.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 系统监控模块
///
/// 进程管理 + 系统信息 + 端口查询。
/// 合并 Fasty 的 process-manager、system-info、port-scanner。
@MainActor
public final class SystemMonitorModule: QuickModule {

    public static let id = "sysmonitor"
    public static let name = "系统监控"
    public static let icon = "gauge.with.dots.needle.33percent"

    public var isEnabled = true

    private let scanner = ProcessScanner()

    public init() {}

    public func searchItems(query: String) async -> [SearchableItem] {
        let triggers = ["进程", "系统信息", "系统监控", "process", "monitor", "端口", "port", "cpu", "内存"]
        guard triggers.contains(where: { query.lowercased().contains($0) }) else { return [] }

        return [
            SearchableItem(
                id: "sysmonitor.overview",
                moduleID: Self.id,
                title: "系统监控",
                subtitle: "查看进程、系统信息和端口",
                icon: "gauge.with.dots.needle.33percent",
                relevance: 0.6,
                action: {
                    EventBus.shared.post(NavigateEvent(moduleID: "sysmonitor"))
                }
            )
        ]
    }

    public func makeView() -> AnyView {
        AnyView(SystemMonitorView(scanner: scanner))
    }
}
