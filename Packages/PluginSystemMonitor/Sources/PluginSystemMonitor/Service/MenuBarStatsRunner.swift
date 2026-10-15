// MenuBarStatsRunner.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Darwin
import Foundation
import QuickCore

/// 菜单栏摘要的常驻采样
///
/// 和面板里的采样分开：面板采样只在面板可见时跑（并扫进程，较重）；这里要常驻，
/// 所以只读两个 Mach 计数器（CPU tick、VM 统计），每次是微秒级的系统调用，不起子进程。
/// 设置关着时只剩一个很慢的轮询去看开关，几乎不占资源。
@MainActor
final class MenuBarStatsRunner {

    private var task: Task<Void, Never>?
    private let log = QuickLog.plugin("sysmonitor")

    /// 开关关着时多久看一次设置
    private static let idlePollSeconds = 3

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            var previous: CpuTickSample?
            var isShowing = false
            while !Task.isCancelled {
                let enabled = PluginDefaults.isEnabled(
                    PluginSettingKey.SystemMonitor.showMenuBarStats, default: false)
                if enabled {
                    let current = CpuHostSampler.overallTicks()
                    let cpu = previous.flatMap { prev in current.flatMap { CpuLoad.usagePercent(previous: prev, current: $0) } }
                    previous = current
                    // 第一轮没有基线：先不发，等下一轮有了增量再显示，免得闪一个 0%
                    if let cpu, let memory = Self.memoryUsedPercent() {
                        EventBus.shared.post(
                            MenuBarTextEvent(text: MenuBarStats.title(cpuPercent: cpu, memoryPercent: memory)))
                        isShowing = true
                    }
                    let seconds = MenuBarStats.refreshSeconds(configured: SystemMonitorSampling.configuredInterval())
                    try? await Task.sleep(for: .seconds(seconds))
                } else {
                    previous = nil
                    if isShowing {
                        EventBus.shared.post(MenuBarTextEvent(text: nil))
                        isShowing = false
                        self?.log.notice("菜单栏摘要已关闭")
                    }
                    try? await Task.sleep(for: .seconds(Self.idlePollSeconds))
                }
            }
            if isShowing { EventBus.shared.post(MenuBarTextEvent(text: nil)) }
        }
        log.notice("菜单栏摘要采样已启动")
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// 内存占用百分比，口径与面板一致：(可分页内部页 − 可清除页) + 固定页 + 压缩页
    nonisolated static func memoryUsedPercent() -> Double? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pageSize = Double(getpagesize())
        let app = max(0, Double(stats.internal_page_count) - Double(stats.purgeable_count))
        let used = (app + Double(stats.wire_count) + Double(stats.compressor_page_count)) * pageSize
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return nil }
        return min(100, used / total * 100)
    }
}
