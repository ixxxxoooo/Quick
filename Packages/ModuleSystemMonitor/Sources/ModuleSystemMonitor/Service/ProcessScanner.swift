// ProcessScanner.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Foundation

/// 进程扫描器
///
/// 获取正在运行的进程列表和系统信息。
@MainActor
final class ProcessScanner: Observable {

    /// 进程信息
    struct ProcessInfo: Identifiable, Sendable {
        let id: Int32
        let name: String
        let cpuUsage: String
        let memoryUsage: String
    }

    /// 系统信息
    struct SystemInfo: Sendable {
        let hostname: String
        let osVersion: String
        let uptime: String
        let cpuCount: Int
        let memoryTotal: String
    }

    private(set) var processes: [ProcessInfo] = []
    private(set) var systemInfo: SystemInfo?

    /// 刷新进程列表
    func refreshProcesses() async {
        let result: [ProcessInfo] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.launchPath = "/bin/ps"
                task.arguments = ["-eo", "pid,pcpu,pmem,comm", "-r"]

                let pipe = Pipe()
                task.standardOutput = pipe

                try? task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let lines = output.components(separatedBy: "\n").dropFirst()

                let procs = lines.prefix(50).compactMap { line -> ProcessInfo? in
                    let parts = line.trimmingCharacters(in: .whitespaces)
                        .components(separatedBy: .whitespaces)
                        .filter { !$0.isEmpty }
                    guard parts.count >= 4 else { return nil }
                    guard let pid = Int32(parts[0]) else { return nil }
                    let name = parts[3...].joined(separator: " ")
                    return ProcessInfo(
                        id: pid,
                        name: (name as NSString).lastPathComponent,
                        cpuUsage: "\(parts[1])%",
                        memoryUsage: "\(parts[2])%"
                    )
                }
                continuation.resume(returning: Array(procs))
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
            uptime: formatUptime(sysInfo.systemUptime),
            cpuCount: sysInfo.processorCount,
            memoryTotal: formatBytes(Int64(sysInfo.physicalMemory))
        )
    }

    /// 格式化运行时间
    private func formatUptime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 24 {
            return "\(hours / 24) 天 \(hours % 24) 小时"
        }
        return "\(hours) 小时 \(minutes) 分钟"
    }

    /// 格式化字节数
    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        return String(format: "%.1f GB", gb)
    }
}
