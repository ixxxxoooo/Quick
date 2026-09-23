// HardwareSampler.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Darwin
import Foundation
import IOKit

/// 硬件信息采集
///
/// 快路径全部走系统内核接口（`sysctlbyname` / IOKit），**毫秒级、不起子进程**：
/// 机型标识符、芯片、核心数、内存、序列号。GPU 三项只能靠 `system_profiler`，
/// 单独一个方法，由调用方放到后台跑 —— 慢也不挡首屏。
///
/// 之前整块硬件信息都来自 `system_profiler SPHardwareDataType` + `SPDisplaysDataType`，
/// 那是 Apple 的「枚举整棵 IORegistry」的重工具，冷启动/外设多时能到秒级；现在只有
/// GPU 那一步还用它。
enum HardwareSampler {

    /// 快路径：sysctl + IOKit（毫秒级）
    ///
    /// - Returns: 硬件信息（GPU 三项为占位）；连机型都读不到时返回 `nil`
    static func sample() -> HardwareInfo? {
        guard let identifier = sysctlString("hw.model"), !identifier.isEmpty else { return nil }
        let memoryBytes = sysctlUInt64("hw.memsize") ?? 0
        return HardwareInfo(
            modelName: modelDisplayName(identifier),
            modelIdentifier: identifier,
            modelNumber: "—",
            chip: sysctlString("machdep.cpu.brand_string") ?? "未知",
            totalCores: sysctlInt("hw.ncpu").map(String.init) ?? "未知",
            memory: memoryBytes > 0 ? SystemMetrics.bytes(Int64(memoryBytes)) : "未知",
            serialNumber: platformSerial() ?? "—",
            gpuChipset: HardwareInfo.gpuPlaceholder,
            gpuCores: HardwareInfo.gpuPlaceholder,
            gpuMemory: HardwareInfo.gpuPlaceholder
        )
    }

    /// 慢路径：GPU（`system_profiler SPDisplaysDataType`），由调用方放后台
    static func sampleGPU(memory: String) -> GPUInfo? {
        let output = LocalCommand.run(
            path: "/usr/sbin/system_profiler", arguments: ["SPDisplaysDataType"])
        return HardwareInfoParsing.parseGPU(output, memory: memory)
    }

    /// 从机型标识符推一个可读名字；推不出来就原样返回标识符
    ///
    /// Apple Silicon 的 `Mac16,1` 这类标识符不含名字（同一个前缀横跨 MacBook Pro / iMac），
    /// 只有 `MacBookPro18,3` 这类才含，所以只做「能确定就映射」，绝不瞎猜。
    static func modelDisplayName(_ identifier: String) -> String {
        let table: [(prefix: String, name: String)] = [
            ("MacBookPro", "MacBook Pro"),
            ("MacBookAir", "MacBook Air"),
            ("MacBook", "MacBook"),
            ("Macmini", "Mac mini"),
            ("MacStudio", "Mac Studio"),
            ("MacPro", "Mac Pro"),
            ("iMac", "iMac")
        ]
        for entry in table where identifier.hasPrefix(entry.prefix) {
            return entry.name
        }
        return identifier
    }

    // MARK: - sysctl / IOKit

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value = 0
        var size = MemoryLayout<Int>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    private static func sysctlUInt64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    private static func platformSerial() -> String? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard
            let value = IORegistryEntryCreateCFProperty(
                service, "IOPlatformSerialNumber" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue()
        else { return nil }
        return value as? String
    }
}
