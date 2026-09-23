// CpuHostSampler.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Darwin
import Foundation

/// 用 Mach host API 读 CPU tick
///
/// 放在 Service：碰 Darwin。算占用率的纯函数在 `CpuLoad`。
enum CpuHostSampler {

    /// 整体 CPU tick
    nonisolated static func overallTicks() -> CpuTickSample? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CpuTickSample(
            user: UInt32(info.cpu_ticks.0),
            system: UInt32(info.cpu_ticks.1),
            idle: UInt32(info.cpu_ticks.2),
            nice: UInt32(info.cpu_ticks.3)
        )
    }

    /// 每核 tick
    nonisolated static func perCoreTicks() -> [CpuTickSample]? {
        var processorInfo: processor_info_array_t?
        var processorMsgCount = mach_msg_type_number_t(0)
        var processorCount = natural_t(0)

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorMsgCount
        )
        guard result == KERN_SUCCESS, let processorInfo else { return nil }
        defer {
            let size = vm_size_t(processorMsgCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: processorInfo), size)
        }

        let loadInfo = UnsafeRawPointer(processorInfo)
            .bindMemory(to: processor_cpu_load_info.self, capacity: Int(processorCount))

        return (0..<Int(processorCount)).map { index in
            let ticks = loadInfo[index].cpu_ticks
            return CpuTickSample(
                user: UInt32(ticks.0),
                system: UInt32(ticks.1),
                idle: UInt32(ticks.2),
                nice: UInt32(ticks.3)
            )
        }
    }
}
