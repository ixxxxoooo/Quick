// HardwareInfoParsing.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 硬件规格
///
/// 大部分字段来自 `sysctl` / IOKit（毫秒级，见 `HardwareSampler`）；只有 GPU 三项
/// 需要 `system_profiler SPDisplaysDataType`，在后台补齐。整体可编码，用于跨启动缓存。
struct HardwareInfo: Sendable, Equatable, Codable {
    let modelName: String
    let modelIdentifier: String
    let modelNumber: String
    let chip: String
    let totalCores: String
    let memory: String
    let serialNumber: String
    let gpuChipset: String
    let gpuCores: String
    let gpuMemory: String

    /// GPU 三项的占位文案（后台还没补上时显示）
    static let gpuPlaceholder = "读取中…"

    /// 已拿到的 GPU 信息；还是占位时返回 nil
    var gpu: GPUInfo? {
        guard gpuChipset != Self.gpuPlaceholder, gpuChipset != "—" else { return nil }
        return GPUInfo(chipset: gpuChipset, cores: gpuCores, memory: gpuMemory)
    }

    /// 只替换 GPU 三项，其余原样
    func mergingGPU(_ gpu: GPUInfo?) -> HardwareInfo {
        guard let gpu else { return self }
        return HardwareInfo(
            modelName: modelName,
            modelIdentifier: modelIdentifier,
            modelNumber: modelNumber,
            chip: chip,
            totalCores: totalCores,
            memory: memory,
            serialNumber: serialNumber,
            gpuChipset: gpu.chipset,
            gpuCores: gpu.cores,
            gpuMemory: gpu.memory
        )
    }
}

/// GPU 信息
struct GPUInfo: Sendable, Equatable, Codable {
    let chipset: String
    let cores: String
    let memory: String
}

/// 软件版本
struct SoftwareInfo: Sendable, Equatable {
    let osName: String
    let osVersion: String
    let hostname: String
    let uptime: String
}

/// 解析 `system_profiler SPDisplaysDataType`（只用来补 GPU）
enum HardwareInfoParsing {

    /// 从显示器输出里解析 GPU；拿不到核心字段时返回 nil
    static func parseGPU(_ output: String, memory: String) -> GPUInfo? {
        guard let chipset = field(output, "Chipset Model"), !chipset.isEmpty else { return nil }
        let vram = field(output, "VRAM (Total)") ?? field(output, "VRAM")
        let isUnified = vram == nil
        let gpuMemory = isUnified ? "共享（\(memory) 系统内存）" : (vram ?? "未知")
        return GPUInfo(
            chipset: chipset,
            cores: field(output, "Total Number of Cores") ?? "未知",
            memory: gpuMemory
        )
    }

    /// 取 `Label: value` 形式的一行
    static func field(_ output: String, _ label: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: label)
        let pattern = try? NSRegularExpression(
            pattern: "^[ \\t]*\(escaped):[ \\t]*(.+)$",
            options: .anchorsMatchLines
        )
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = pattern?.firstMatch(in: output, range: range),
            let valueRange = Range(match.range(at: 1), in: output)
        else {
            return nil
        }
        return String(output[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
