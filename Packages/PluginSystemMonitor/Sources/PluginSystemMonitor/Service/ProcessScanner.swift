// ProcessScanner.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Foundation

/// 进程扫描器
///
/// 获取正在运行的进程列表和系统信息。
/// 解析与格式化都在 `Model/` 里（`ProcessListing` / `SystemMetrics`），
/// 这里只负责起命令、读环境事实。
@MainActor
@Observable
final class ProcessScanner {

    /// 系统信息
    struct SystemInfo: Sendable {
        let hostname: String
        let osVersion: String
        let uptime: String
        let cpuCount: Int
        let memoryTotal: String
    }

    private(set) var processes: [ProcessEntry] = []
    private(set) var systemInfo: SystemInfo?

    /// 偏好存储。注入是为了让采样间隔能被测试固定住 —— 默认就是标准偏好
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 当前的采样间隔（秒）
    ///
    /// 采样循环每轮都问它一次，所以设置页改了下一轮就生效。
    /// internal 而不是 private：循环体默认要起 `ps`，测试里不允许起进程，间隔因此在这里被断言。
    var samplingInterval: Int {
        SystemMonitorSampling.configuredInterval(defaults: defaults)
    }

    /// 按设置里的采样间隔连续刷新，直到任务被取消
    ///
    /// 由视图的 `.task` 驱动：面板关掉（任务取消）采样就停，不会在后台空转。
    ///
    /// - Parameter tick: 每一轮的动作。默认刷新进程列表与系统信息；
    ///   测试传入计数闭包，采样节奏就能在不起 `ps` 的前提下被观察。
    func startSampling(tick: (@MainActor () async -> Void)? = nil) async {
        while !Task.isCancelled {
            if let tick {
                await tick()
            } else {
                await refreshProcesses()
                refreshSystemInfo()
            }

            // 每轮重新读一次间隔：中途改设置，下一轮就是新的节奏
            try? await Task.sleep(for: .seconds(samplingInterval))
        }
    }

    /// 刷新进程列表
    func refreshProcesses() async {
        processes = await Task.detached(priority: .userInitiated) {
            ProcessScanner.scan()
        }.value
    }

    /// 获取系统信息
    func refreshSystemInfo() {
        let sysInfo = Foundation.ProcessInfo.processInfo
        systemInfo = SystemInfo(
            hostname: sysInfo.hostName,
            osVersion: sysInfo.operatingSystemVersionString,
            uptime: SystemMetrics.uptime(sysInfo.systemUptime),
            cpuCount: sysInfo.processorCount,
            memoryTotal: SystemMetrics.bytes(Int64(sysInfo.physicalMemory))
        )
    }

    /// 起 `ps` 并把输出解析成进程条目
    ///
    /// `nonisolated` 是必需的：`ProcessScanner` 是 `@MainActor`，静态成员默认也继承主 actor 隔离，
    /// 不加这个标注的话 `Task.detached` 里调用它仍会跳回主线程。起进程 + 阻塞读管道是 IO，
    /// 留在主线程会卡住面板 —— 这也是它以前跑在 `DispatchQueue.global` 上的原因，行为不变。
    nonisolated private static func scan() -> [ProcessEntry] {
        let task = Process()
        task.launchPath = ProcessListing.commandPath
        task.arguments = ProcessListing.commandArguments

        let pipe = Pipe()
        task.standardOutput = pipe

        try? task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return ProcessListing.parse(output)
    }
}
