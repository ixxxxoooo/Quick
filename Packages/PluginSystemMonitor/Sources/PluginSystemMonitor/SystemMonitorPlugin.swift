// SystemMonitorPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 系统监控插件
///
/// 进程管理 + 系统信息 + 端口查询。
/// 合并 Fasty 的 process-manager、system-info、port-scanner。
@MainActor
public final class SystemMonitorPlugin: QuickPlugin {

    public static let id = "sysmonitor"
    public static let name = "系统监控"
    public static let icon = "cpu"
    public static let description = "实时监控 macOS 系统 CPU、内存占用率与高负载进程，提供进程查看与一键终止功能。"
    public static let triggerWords = [
        "系统信息", "系统监控", "系统", "system", "信息", "硬件", "进程", "进程管理", "process", "monitor", "端口", "port", "cpu",
        "内存"
    ]

    public var isEnabled = true

    private let log = QuickLog.plugin(SystemMonitorPlugin.id)

    /// 进程扫描器。
    ///
    /// internal 而不是 private：采样间隔由扫描器从设置读出来（见 `ProcessScanner.samplingInterval`），
    /// 接线测试要能从这里拿到它验证设置确实传到了采样循环。
    let scanner = ProcessScanner()

    public init() {}

    public func searchItems(query: String) async -> [SearchableItem] {
        // 用整词匹配而不是 contains：否则 export / support / report / import 都会误触发本插件
        guard query.matchesAnyTrigger(Self.triggerWords) else { return [] }

        return [
            SearchableItem(
                id: "sysmonitor.overview",
                pluginID: Self.id,
                title: "系统监控",
                subtitle: "查看进程、系统信息和端口",
                icon: "cpu",
                relevance: 0.6,
                action: {
                    EventBus.shared.post(NavigateEvent(pluginID: "sysmonitor"))
                }
            )
        ]
    }

    public func makeView() -> AnyView {
        AnyView(SystemMonitorView(scanner: scanner))
    }

    public func activate() {
        log.notice("插件已激活，进程列表在打开视图时刷新")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
