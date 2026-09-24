// SystemMonitorPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 系统监控插件
///
/// CPU / 内存 / 磁盘 / 电源 / 网络与硬件规格，布局对齐 Raycast System Monitor。
@MainActor
public final class SystemMonitorPlugin: QuickPlugin, PluginViewProviding {

    public static let id = "sysmonitor"
    public static let name = "系统监控"
    public static let icon = "gauge.with.dots.needle.67percent"
    public static let description = "查看 CPU、内存、磁盘、电源与网络占用，以及硬件规格与高负载进程。"
    /// 触发词**必须全局唯一**（跨插件不重复）。
    ///
    /// `进程` / `process` / `网络` 归「结束进程」与「网络工具」—— 它们的功能更专一，
    /// 而那三个词在这里只是仪表盘的一项。本插件仍可通过 `cpu` / `内存` / `磁盘` /
    /// `系统信息` / `monitor` 等词命中，功能命令也各自带自己的关键词。
    /// 这条约束由 `TriggerWordUniquenessTests` 守着。
    public static let triggerWords = [
        "系统信息", "系统监控", "系统", "system", "信息", "硬件", "进程管理", "monitor", "端口", "port",
        "cpu", "内存", "磁盘", "电池", "电源"
    ]

    public static var functionCommands: [CommandDescriptor] {
        [
            CommandDescriptor(
                id: "sysmonitor.cpu", pluginID: id, pluginName: name, title: "CPU 监控",
                subtitle: "查看 CPU 占用", keywords: ["cpu", "cpu监控"], icon: "cpu"),
            CommandDescriptor(
                id: "sysmonitor.memory", pluginID: id, pluginName: name, title: "内存监控",
                subtitle: "查看内存占用", keywords: ["内存", "memory"], icon: "memorychip"),
            CommandDescriptor(
                id: "sysmonitor.disk", pluginID: id, pluginName: name, title: "磁盘监控",
                subtitle: "查看磁盘占用", keywords: ["磁盘", "disk"], icon: "internaldrive"),
            CommandDescriptor(
                id: "sysmonitor.network", pluginID: id, pluginName: name, title: "网络监控",
                subtitle: "查看网络吞吐", keywords: ["网络监控"], icon: "network"),
            CommandDescriptor(
                id: "sysmonitor.temperature", pluginID: id, pluginName: name, title: "温度监控",
                subtitle: "查看机身温度", keywords: ["温度", "temperature"],
                icon: "thermometer.medium")
        ]
    }

    public var isEnabled = true

    private let log = QuickLog.plugin(SystemMonitorPlugin.id)

    /// 进程扫描器。
    ///
    /// internal 而不是 private：采样间隔由扫描器从设置读出来（见 `ProcessScanner.samplingInterval`），
    /// 接线测试要能从这里拿到它验证设置确实传到了采样循环。
    let scanner = ProcessScanner()

    /// 面板显隐订阅；不保存会被 ARC 立刻取消
    private var visibilitySubscription: EventSubscription?

    public init() {}

    public func makeView() -> AnyView {
        AnyView(SystemMonitorView(scanner: scanner))
    }

    public func activate() {
        visibilitySubscription = EventBus.shared.on(PaletteVisibilityChangedEvent.self) {
            [weak self] event in
            self?.scanner.notePanelVisibility(event.isVisible)
        }
        log.notice("插件已激活，采样跟随面板显隐")
    }

    public func deactivate() {
        visibilitySubscription?.cancel()
        visibilitySubscription = nil
        scanner.noteViewDisappeared()
        log.notice("插件已停用")
    }
}
