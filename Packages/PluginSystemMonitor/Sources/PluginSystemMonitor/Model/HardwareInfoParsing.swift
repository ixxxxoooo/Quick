// HardwareInfoParsing.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 硬件规格（来自 `system_profiler`）
struct HardwareInfo: Sendable, Equatable {
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
}

/// 软件版本
struct SoftwareInfo: Sendable, Equatable {
    let osName: String
    let osVersion: String
    let hostname: String
    let uptime: String
}

/// 解析 `system_profiler SPHardwareDataType` / `SPDisplaysDataType`
enum HardwareInfoParsing {

    static func parseHardware(_ output: String, displayOutput: String) -> HardwareInfo {
        let memory = field(output, "Memory") ?? "未知"
        let vram = field(displayOutput, "VRAM (Total)") ?? field(displayOutput, "VRAM")
        let isUnified = vram == nil
        let gpuMemory = isUnified ? "共享（\(memory) 系统内存）" : (vram ?? "未知")

        return HardwareInfo(
            modelName: field(output, "Model Name") ?? "未知",
            modelIdentifier: field(output, "Model Identifier") ?? "未知",
            modelNumber: field(output, "Model Number") ?? "未知",
            chip: field(output, "Chip") ?? field(output, "Processor Name") ?? "未知",
            totalCores: field(output, "Total Number of Cores") ?? "未知",
            memory: memory,
            serialNumber: field(output, "Serial Number (system)") ?? "未知",
            gpuChipset: field(displayOutput, "Chipset Model") ?? "未知",
            gpuCores: field(displayOutput, "Total Number of Cores") ?? "未知",
            gpuMemory: gpuMemory
        )
    }

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
