// MemoryStatsParsing.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 内存快照（单位：MB，与活动监视器 / Raycast 口径一致）
struct MemorySnapshot: Sendable, Equatable {
    let totalMB: Double
    let usedMB: Double
    let wiredMB: Double
    let compressedMB: Double
    let activeMB: Double
    let inactiveMB: Double
    let purgeableMB: Double
    let swapUsedMB: Double
    let swapTotalMB: Double
    /// `kern.memorystatus_vm_pressure_level` 原始值
    let pressureLevel: Int

    var usedPercent: Double {
        guard totalMB > 0 else { return 0 }
        return (usedMB / totalMB) * 100
    }

    var freePercent: Double {
        max(0, 100 - usedPercent)
    }

    var pressureLabel: String {
        SystemMetrics.pressureLabel(pressureLevel)
    }
}

/// 解析 `vm_stat` / `sysctl` 输出为内存快照
///
/// 公式对齐 Raycast `memory-stats.ts`：
/// used = (pageable_internal - purgeable) + wired + compressor。
enum MemoryStatsParsing {

    /// 从一组已读好的环境事实拼快照
    static func snapshot(
        pageSize: Int,
        memSizeBytes: UInt64,
        pageableInternal: Int,
        purgeable: Int,
        vmStatOutput: String,
        swapOutput: String,
        pressureRaw: String
    ) -> MemorySnapshot {
        let pagesWired = pages(in: vmStatOutput, label: "wired down")
        let pagesCompressed = pages(in: vmStatOutput, label: "occupied by compressor")
        let pagesActive = pages(in: vmStatOutput, label: "active")
        let pagesInactive = pages(in: vmStatOutput, label: "inactive")
        let pagesApp = max(0, pageableInternal - purgeable)

        let toMB = { (pages: Double) -> Double in
            (pages * Double(pageSize)) / 1_048_576.0
        }

        let swap = parseSwap(swapOutput)
        let pressure = Int(pressureRaw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

        return MemorySnapshot(
            totalMB: Double(memSizeBytes) / 1_048_576.0,
            usedMB: toMB(Double(pagesApp + pagesWired + pagesCompressed)),
            wiredMB: toMB(Double(pagesWired)),
            compressedMB: toMB(Double(pagesCompressed)),
            activeMB: toMB(Double(pagesActive)),
            inactiveMB: toMB(Double(pagesInactive)),
            purgeableMB: toMB(Double(purgeable)),
            swapUsedMB: swap.used,
            swapTotalMB: swap.total,
            pressureLevel: pressure
        )
    }

    /// 从 `vm_stat` 文本里取某一行的页数
    static func pages(in output: String, label: String) -> Int {
        guard let line = output.split(separator: "\n").first(where: { $0.contains(label) }) else {
            return 0
        }
        let digits = line.split(separator: ":").last?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")
            .filter(\.isNumber)
        return Int(digits ?? "") ?? 0
    }

    /// `vm.swapusage` → (total, used) MB
    static func parseSwap(_ output: String) -> (total: Double, used: Double) {
        let pattern = /total = (?<total>[\d.]+)M\s+used = (?<used>[\d.]+)M/
        guard let match = output.firstMatch(of: pattern) else { return (0, 0) }
        return (Double(match.total) ?? 0, Double(match.used) ?? 0)
    }
}
