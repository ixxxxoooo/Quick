// ProcessRecord.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 一条可被结束的进程记录
struct ProcessRecord: Identifiable, Sendable, Equatable {
    let id: Int32
    let name: String
    let path: String
    let cpuPercent: Double
    let memoryPercent: Double
    /// RSS，单位 KB
    let rssKilobytes: Int

    var cpuText: String {
        String(format: "%.1f%%", cpuPercent)
    }

    var memoryText: String {
        KillProcessMetrics.formatRSS(rssKilobytes)
    }
}

/// 排序口径
enum KillProcessSortMode: String, CaseIterable, Sendable {
    case cpu
    case memory

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "内存"
        }
    }

    var psFlag: String {
        switch self {
        case .cpu: "-r"
        case .memory: "-m"
        }
    }
}

/// 展示与解析辅助
enum KillProcessMetrics {

    static func formatRSS(_ kilobytes: Int) -> String {
        if kilobytes >= 1024 * 1024 {
            return String(format: "%.1f GB", Double(kilobytes) / (1024 * 1024))
        }
        if kilobytes >= 1024 {
            return String(format: "%.1f MB", Double(kilobytes) / 1024)
        }
        return "\(kilobytes) KB"
    }

    static func parseCPU(_ text: String) -> Double {
        Double(text) ?? 0
    }

    static func parseMemoryPercent(_ text: String) -> Double {
        Double(text) ?? 0
    }
}

/// `ps` 输出解析
enum KillProcessListing {

    static let commandPath = "/bin/ps"
    static let columnSpec = "pid=,pcpu=,pmem=,rss=,comm="

    static func arguments(sort: KillProcessSortMode) -> [String] {
        ["-axo", columnSpec, sort.psFlag]
    }

    /// 解析 `ps` 标准输出
    static func parse(_ output: String) -> [ProcessRecord] {
        let lines = output.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return lines.compactMap { line -> ProcessRecord? in
            let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 5 else { return nil }
            guard let pid = Int32(parts[0]), pid > 0 else { return nil }
            guard let rss = Int(parts[3]) else { return nil }

            let path = parts[4...].joined(separator: " ")
            let name = (path as NSString).lastPathComponent
            return ProcessRecord(
                id: pid,
                name: name,
                path: path,
                cpuPercent: KillProcessMetrics.parseCPU(parts[1]),
                memoryPercent: KillProcessMetrics.parseMemoryPercent(parts[2]),
                rssKilobytes: rss
            )
        }
    }

    /// 按名称 / PID / 路径过滤
    static func filter(
        _ records: [ProcessRecord],
        query: String,
        searchPath: Bool,
        searchPID: Bool
    ) -> [ProcessRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return records }
        let lower = trimmed.lowercased()
        return records.filter { record in
            if record.name.lowercased().contains(lower) { return true }
            if searchPID, String(record.id).contains(trimmed) { return true }
            if searchPath, record.path.lowercased().contains(lower) { return true }
            return false
        }
    }
}
