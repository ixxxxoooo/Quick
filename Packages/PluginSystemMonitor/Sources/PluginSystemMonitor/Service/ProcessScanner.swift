// ProcessScanner.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Foundation
import QuickCore

/// 系统监控采样器
///
/// 聚合进程列表、CPU / 内存 / 磁盘 / 电源 / 网络与硬件信息。
/// 解析与格式化都在 `Model/`，这里只负责起命令、读 Mach / ifaddrs。
@MainActor
@Observable
final class ProcessScanner {

    private(set) var processes: [ProcessEntry] = []
    private(set) var topCPUProcesses: [ProcessEntry] = []
    private(set) var topMemoryProcesses: [ProcessEntry] = []

    private(set) var cpuUsagePercent: Double?
    private(set) var perCoreUsage: [CoreUsage] = []
    private(set) var loadAverage: [String] = []

    private(set) var memory: MemorySnapshot?
    private(set) var disks: [DiskVolume] = []
    private(set) var rootVolume: RootVolumeDetails?
    private(set) var power: PowerSnapshot?
    private(set) var networkInterfaces: [NetworkInterfaceInfo] = []
    private(set) var networkThroughput: NetworkThroughput?
    private(set) var temperature: TemperatureSnapshot?

    private(set) var hardware: HardwareInfo?
    private(set) var software: SoftwareInfo?

    /// 兼容旧「系统信息」页的扁平结构
    struct SystemInfo: Sendable {
        let hostname: String
        let osVersion: String
        let uptime: String
        let cpuCount: Int
        let memoryTotal: String
    }

    private(set) var systemInfo: SystemInfo?

    private let defaults: UserDefaults
    private let log = QuickLog.plugin(SystemMonitorPlugin.id)

    private var previousCPUTicks: CpuTickSample?
    private var previousCoreTicks: [CpuTickSample]?
    private var previousNetworkCounters: [NetworkCounterSample]?
    private var didLoadHardware = false
    /// GPU 那一步每次运行只补一次（它要起 `system_profiler`，是硬件里唯一慢的部分）
    private var didStartGPU = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 先用上次的缓存秒开（含 GPU），首屏不再等 system_profiler
        hardware = HardwareCache.load(defaults: defaults)
    }

    /// 当前的采样间隔（秒）
    var samplingInterval: Int {
        SystemMonitorSampling.configuredInterval(defaults: defaults)
    }

    /// 视图仍希望采样（面板隐藏时保留，以便再次显示时恢复）
    private var resumeWhenVisible = false

    /// 采样循环句柄；面板 `orderOut` 不会取消 SwiftUI `.task`，必须自己持有并取消
    private var samplingTask: Task<Void, Never>?

    /// 当前是否持有采样任务（测试与排查用）
    var isSampling: Bool { samplingTask != nil }

    /// 视图出现：标记需要采样并立刻开始
    func noteViewAppeared() {
        setResumeWhenVisible(true)
        startSamplingIfNeeded()
    }

    /// 视图消失（退回主搜索 / 分离后主面板 pop）：彻底停，且不再自动恢复
    func noteViewDisappeared() {
        setResumeWhenVisible(false)
        stopSampling()
    }

    /// 标记「视图仍挂着、面板再显示时应恢复采样」
    func setResumeWhenVisible(_ value: Bool) {
        resumeWhenVisible = value
    }

    /// 主面板显隐。隐藏一律停；显示时仅当视图仍挂着才恢复
    func notePanelVisibility(_ isVisible: Bool) {
        if isVisible {
            if resumeWhenVisible {
                startSamplingIfNeeded()
            }
        } else {
            stopSampling()
        }
    }

    /// 若尚未在采，启动采样循环
    func startSamplingIfNeeded(tick: (@MainActor () async -> Void)? = nil) {
        guard samplingTask == nil else { return }
        log.notice("开始系统监控采样，间隔 \(self.samplingInterval, privacy: .public) 秒")
        samplingTask = Task { [weak self] in
            await self?.runSamplingLoop(tick: tick)
        }
    }

    /// 取消采样循环
    func stopSampling() {
        guard samplingTask != nil else { return }
        samplingTask?.cancel()
        samplingTask = nil
        log.notice("已停止系统监控采样")
    }

    /// 按设置里的采样间隔连续刷新，直到任务被取消
    ///
    /// 测试可直接 `Task { await startSampling(tick:) }` 再 `cancel`；生产路径走
    /// `startSamplingIfNeeded` / `stopSampling`。
    func startSampling(tick: (@MainActor () async -> Void)? = nil) async {
        await runSamplingLoop(tick: tick)
    }

    private func runSamplingLoop(tick: (@MainActor () async -> Void)?) async {
        while !Task.isCancelled {
            if let tick {
                await tick()
            } else {
                await refreshAll()
            }
            try? await Task.sleep(for: .seconds(samplingInterval))
        }
    }

    /// 刷新全部可变指标
    func refreshAll() async {
        async let cpuTask: Void = refreshCPU()
        async let memoryTask: Void = refreshMemory()
        async let processTask: Void = refreshProcesses()
        async let diskTask: Void = refreshDisks()
        async let powerTask: Void = refreshPower()
        async let networkTask: Void = refreshNetwork()
        async let temperatureTask: Void = refreshTemperature()

        await cpuTask
        await memoryTask
        await processTask
        await diskTask
        await powerTask
        await networkTask
        await temperatureTask

        refreshSoftware()
        if !didLoadHardware {
            await refreshHardware()
        }
    }

    /// 刷新进程列表（CPU 排序完整表 + 两类 Top 5）
    func refreshProcesses() async {
        let cpuSorted = await Task.detached(priority: .userInitiated) {
            ProcessScanner.scan(sort: .cpu)
        }.value
        let memorySorted = await Task.detached(priority: .userInitiated) {
            ProcessScanner.scan(sort: .memory, limit: ProcessListing.topPreviewCount)
        }.value

        processes = cpuSorted
        topCPUProcesses = Array(cpuSorted.prefix(ProcessListing.topPreviewCount))
        topMemoryProcesses = memorySorted
    }

    /// 获取基础系统信息（兼容旧路径）
    func refreshSystemInfo() {
        refreshSoftware()
    }

    // MARK: - CPU

    private func refreshCPU() async {
        let sample = await Task.detached(priority: .utility) {
            (CpuHostSampler.overallTicks(), CpuHostSampler.perCoreTicks())
        }.value

        if let current = sample.0 {
            if let previous = previousCPUTicks {
                cpuUsagePercent = CpuLoad.usagePercent(previous: previous, current: current)
            }
            previousCPUTicks = current
        }

        if let currentCores = sample.1 {
            if let previous = previousCoreTicks,
                let usage = CpuLoad.perCoreUsage(previous: previous, current: currentCores)
            {
                perCoreUsage = usage
            }
            previousCoreTicks = currentCores
        }

        var loads = [Double](repeating: 0, count: 3)
        _ = loads.withUnsafeMutableBufferPointer { buffer in
            getloadavg(buffer.baseAddress, 3)
        }
        loadAverage = CpuLoad.formatLoadAverage(loads)
    }

    // MARK: - Memory

    private func refreshMemory() async {
        memory = await Task.detached(priority: .utility) {
            ProcessScanner.collectMemory()
        }.value
    }

    // MARK: - Disk

    private func refreshDisks() async {
        let result = await Task.detached(priority: .utility) {
            let df = LocalCommand.run(path: "/bin/df", arguments: ["-kP"])
            let volumes = DiskStatsParsing.parseStorage(df)
            let info = LocalCommand.run(path: "/usr/sbin/diskutil", arguments: ["info", "/"])
            let root = info.isEmpty ? nil : DiskStatsParsing.parseRootVolume(info)
            return (volumes, root)
        }.value
        disks = result.0
        rootVolume = result.1
    }

    // MARK: - Power

    private func refreshPower() async {
        power = await Task.detached(priority: .utility) {
            ProcessScanner.collectPower()
        }.value
    }

    // MARK: - Network

    private func refreshNetwork() async {
        let now = Date()
        let result = await Task.detached(priority: .utility) {
            (NetworkInterfaceSampler.interfaces(), NetworkInterfaceSampler.counters(now: now))
        }.value
        networkInterfaces = result.0
        let counters = result.1
        if let previous = previousNetworkCounters {
            networkThroughput = NetworkStatsParsing.throughput(previous: previous, current: counters)
        }
        previousNetworkCounters = counters
    }

    // MARK: - Temperature

    private func refreshTemperature() async {
        let state = Foundation.ProcessInfo.processInfo.thermalState
        temperature = await Task.detached(priority: .utility) {
            TemperatureSampler.sample(thermalState: state)
        }.value
    }

    // MARK: - Software / Hardware

    private func refreshSoftware() {
        let info = Foundation.ProcessInfo.processInfo
        software = SoftwareInfo(
            osName: "macOS",
            osVersion: info.operatingSystemVersionString,
            hostname: info.hostName,
            uptime: SystemMetrics.uptime(info.systemUptime)
        )
        systemInfo = SystemInfo(
            hostname: info.hostName,
            osVersion: info.operatingSystemVersionString,
            uptime: SystemMetrics.uptime(info.systemUptime),
            cpuCount: info.processorCount,
            memoryTotal: SystemMetrics.bytes(Int64(info.physicalMemory))
        )
    }

    /// 采集硬件信息
    ///
    /// 快路径（sysctl / IOKit）毫秒级，直接出；GPU 三项要靠 `system_profiler`，
    /// 丢到后台补，不阻塞这一轮刷新。结果写进缓存，下次启动秒开。
    private func refreshHardware() async {
        let fast = await Task.detached(priority: .userInitiated) {
            HardwareSampler.sample()
        }.value

        if let fast {
            hardware = fast.mergingGPU(hardware?.gpu)
            HardwareCache.save(hardware, defaults: defaults)
            didLoadHardware = true
            log.notice("硬件信息已就绪（sysctl）：\(fast.modelIdentifier, privacy: .public)")
        } else if hardware == nil {
            // 连机型都读不到：这一轮不算就绪，下个 tick 再试
            log.error("sysctl 读取硬件信息失败")
            return
        } else {
            didLoadHardware = true
        }

        startGPUIfNeeded()
    }

    /// GPU 后台补齐（每次运行一次）
    private func startGPUIfNeeded() {
        guard !didStartGPU, let current = hardware else { return }
        didStartGPU = true
        let memory = current.memory
        Task { [weak self] in
            let gpu = await Task.detached(priority: .utility) {
                HardwareSampler.sampleGPU(memory: memory)
            }.value
            guard let self, let gpu, let latest = self.hardware else { return }
            self.hardware = latest.mergingGPU(gpu)
            HardwareCache.save(self.hardware, defaults: self.defaults)
            self.log.notice("GPU 信息已补全")
        }
    }

    // MARK: - 后台采集

    nonisolated private static func scan(
        sort: ProcessSortMode,
        limit: Int = ProcessListing.maximumCount
    ) -> [ProcessEntry] {
        let output = LocalCommand.run(
            path: ProcessListing.commandPath,
            arguments: ProcessListing.commandArguments(sort: sort)
        )
        return ProcessListing.parse(output, limit: limit)
    }

    nonisolated private static func collectMemory() -> MemorySnapshot? {
        let pageSize =
            Int(
                LocalCommand.run(path: "/usr/sbin/sysctl", arguments: ["-n", "hw.pagesize"])
                    .trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let memSize =
            UInt64(
                LocalCommand.run(path: "/usr/sbin/sysctl", arguments: ["-n", "hw.memsize"])
                    .trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let pageable =
            Int(
                LocalCommand.run(
                    path: "/usr/sbin/sysctl", arguments: ["-n", "vm.page_pageable_internal_count"]
                ).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let purgeable =
            Int(
                LocalCommand.run(path: "/usr/sbin/sysctl", arguments: ["-n", "vm.page_purgeable_count"])
                    .trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let vmStat = LocalCommand.run(path: "/usr/bin/vm_stat", arguments: [])
        let swap = LocalCommand.run(path: "/usr/sbin/sysctl", arguments: ["-n", "vm.swapusage"])
        let pressure = LocalCommand.run(
            path: "/usr/sbin/sysctl", arguments: ["-n", "kern.memorystatus_vm_pressure_level"])

        guard pageSize > 0, memSize > 0 else { return nil }
        return MemoryStatsParsing.snapshot(
            pageSize: pageSize,
            memSizeBytes: memSize,
            pageableInternal: pageable,
            purgeable: purgeable,
            vmStatOutput: vmStat,
            swapOutput: swap,
            pressureRaw: pressure
        )
    }

    nonisolated private static func collectPower() -> PowerSnapshot {
        let pmset = LocalCommand.run(path: "/usr/bin/pmset", arguments: ["-g", "batt"])
        let parsed = PowerStatsParsing.parsePmset(pmset)
        return PowerSnapshot(
            hasBattery: parsed.hasBattery,
            batteryPercent: parsed.percent,
            isCharging: parsed.isCharging,
            isOnACPower: parsed.isOnAC,
            condition: parsed.hasBattery ? "正常" : "N/A",
            cycleCount: parsed.hasBattery ? "—" : "N/A",
            timeRemainingMinutes: nil
        )
    }
}
