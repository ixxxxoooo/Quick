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

    /// 刷新进程列表
    func refreshProcesses() async {
        let result: [ProcessEntry] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.launchPath = ProcessListing.commandPath
                task.arguments = ProcessListing.commandArguments

                let pipe = Pipe()
                task.standardOutput = pipe

                try? task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: ProcessListing.parse(output))
            }
        }
        processes = result
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
}
