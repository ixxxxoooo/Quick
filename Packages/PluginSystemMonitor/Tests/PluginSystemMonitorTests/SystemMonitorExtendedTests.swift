// SystemMonitorExtendedTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Testing

@testable import PluginSystemMonitor

@Suite("系统监控偏好映射")
struct SystemMonitorPreferencesTests {

    @Test("默认标签只认合法 rawValue，其余回落到系统信息")
    func tabMapping() {
        #expect(SystemMonitorPreferences.tab(storedValue: nil) == .systemInfo)
        #expect(SystemMonitorPreferences.tab(storedValue: "cpu") == .cpu)
        #expect(SystemMonitorPreferences.tab(storedValue: "temperature") == .temperature)
        #expect(SystemMonitorPreferences.tab(storedValue: "bogus") == .systemInfo)
    }

    @Test("显示模式非法值回落到调用方给的 fallback")
    func displayModeMapping() {
        #expect(SystemMonitorPreferences.displayMode(storedValue: "free", fallback: .used) == .free)
        #expect(SystemMonitorPreferences.displayMode(storedValue: "nope", fallback: .used) == .used)
        #expect(SystemMonitorPreferences.displayMode(storedValue: nil, fallback: .free) == .free)
    }
}

@Suite("占用率显示与压力色阶")
struct SystemMetricsDisplayTests {

    @Test("空闲模式翻转占用率")
    func displayedPercentFlipsInFreeMode() {
        #expect(SystemMetrics.displayedPercent(used: 20, mode: .used) == 20)
        #expect(SystemMetrics.displayedPercent(used: 20, mode: .free) == 80)
        #expect(SystemMetrics.accessoryPercent(used: 95, mode: .free, suffixWhenFree: " free") == "5 % free")
    }

    @Test("压力色阶阈值")
    func pressureTones() {
        #expect(SystemMetrics.tone(forPressure: 10) == .normal)
        #expect(SystemMetrics.tone(forPressure: 65) == .elevated)
        #expect(SystemMetrics.tone(forPressure: 85) == .warning)
        #expect(SystemMetrics.tone(forPressure: 95) == .critical)
        #expect(SystemMetrics.tone(forPressureLabel: "警告") == .warning)
        #expect(SystemMetrics.tone(forPressureLabel: "危急") == .critical)
    }

    @Test("RSS 格式化")
    func rssFormatting() {
        #expect(SystemMetrics.rssKilobytes(512) == "512 KB")
        #expect(SystemMetrics.rssKilobytes(2048) == "2 MB")
        #expect(SystemMetrics.rssKilobytes(2_097_152) == "2.0 GB")
    }
}

@Suite("CPU tick 占用率")
struct CpuLoadTests {

    @Test("两次采样算出忙碌占比")
    func usageFromTicks() {
        let previous = CpuTickSample(user: 10, system: 10, idle: 80, nice: 0)
        let current = CpuTickSample(user: 30, system: 20, idle: 100, nice: 0)
        // busy delta = 30, total delta = 50 → 60%
        #expect(CpuLoad.usagePercent(previous: previous, current: current) == 60)
    }

    @Test("总增量为 0 时返回 nil")
    func zeroDeltaReturnsNil() {
        let sample = CpuTickSample(user: 1, system: 1, idle: 1, nice: 0)
        #expect(CpuLoad.usagePercent(previous: sample, current: sample) == nil)
    }

    @Test("每核长度不一致时返回 nil")
    func mismatchedCoreCounts() {
        let previous = [CpuTickSample(user: 1, system: 0, idle: 1, nice: 0)]
        let current = previous + previous
        #expect(CpuLoad.perCoreUsage(previous: previous, current: current) == nil)
    }
}

@Suite("内存解析")
struct MemoryStatsParsingTests {

    @Test("vm_stat 行解析页数")
    func pagesFromVmStat() {
        let output = """
            Pages free:                               1000.
            Pages active:                             2000.
            Pages inactive:                           3000.
            Pages wired down:                         4000.
            Pages occupied by compressor:             5000.
            """
        #expect(MemoryStatsParsing.pages(in: output, label: "wired down") == 4000)
        #expect(MemoryStatsParsing.pages(in: output, label: "occupied by compressor") == 5000)
        #expect(MemoryStatsParsing.pages(in: output, label: "missing") == 0)
    }

    @Test("swapusage 解析")
    func swapParsing() {
        let swap = MemoryStatsParsing.parseSwap("total = 5120.00M used = 4561.00M free = 559.00M")
        #expect(swap.total == 5120)
        #expect(swap.used == 4561)
    }

    @Test("快照 used 公式对齐 Raycast")
    func snapshotFormula() {
        let snapshot = MemoryStatsParsing.snapshot(
            pageSize: 16384,
            memSizeBytes: 16 * 1_073_741_824,
            pageableInternal: 1000,
            purgeable: 200,
            vmStatOutput: """
                Pages wired down: 100.
                Pages occupied by compressor: 50.
                Pages active: 10.
                Pages inactive: 20.
                """,
            swapOutput: "total = 0.00M used = 0.00M free = 0.00M",
            pressureRaw: "2"
        )
        // pagesApp = 800, wired = 100, compressed = 50 → 950 pages
        let expectedUsedMB = (950.0 * 16384) / 1_048_576.0
        #expect(abs(snapshot.usedMB - expectedUsedMB) < 0.01)
        #expect(snapshot.pressureLabel == "警告")
        #expect(snapshot.totalMB == 16 * 1024)
    }
}

@Suite("磁盘解析")
struct DiskStatsParsingTests {

    @Test("df -kP 解析启动盘与卷")
    func parseDf() {
        let output = """
            Filesystem 1024-blocks Used Available Capacity Mounted on
            /dev/disk3s1s1 488245288 10000000 400000000 3% /
            /dev/disk3s1 488245288 20000000 400000000 5% /System/Volumes/Data
            /dev/disk4s1 1000000 500000 500000 50% /Volumes/Backup
            /dev/disk3s1 488245288 1 1 50% /Volumes/Recovery
            """
        let volumes = DiskStatsParsing.parseStorage(output)
        #expect(volumes.count == 2)
        #expect(volumes[0].name == "Macintosh HD")
        #expect(volumes[0].isExternal == false)
        #expect(volumes[1].name == "Backup")
        #expect(volumes[1].isExternal == true)
    }
}

@Suite("电源解析")
struct PowerStatsParsingTests {

    @Test("台式机只有 AC Power 时判定无电池")
    func desktopHasNoBattery() {
        let parsed = PowerStatsParsing.parsePmset("Now drawing from 'AC Power'")
        #expect(parsed.hasBattery == false)
        #expect(parsed.percent == nil)
    }

    @Test("笔记本电池行能读出百分比")
    func laptopBatteryPercent() {
        let output = """
            Now drawing from 'Battery Power'
             -InternalBattery-0 (id=123) 72%; discharging; 3:21 remaining present: true
            """
        let parsed = PowerStatsParsing.parsePmset(output)
        #expect(parsed.hasBattery == true)
        #expect(parsed.percent == 72)
        #expect(parsed.isOnAC == false)
    }

    @Test("显示口径翻转电量")
    func displayMode() {
        #expect(PowerStatsParsing.displayedLevel(80, mode: .free) == "80 %")
        #expect(PowerStatsParsing.displayedLevel(80, mode: .used) == "20 %")
        #expect(PowerStatsParsing.displayedLevel(nil, mode: .free) == "N/A")
    }
}

@Suite("硬件信息解析")
struct HardwareInfoParsingTests {

    @Test("解析 SPHardwareDataType 字段")
    func parseHardware() {
        let hardware = """
            Hardware Overview:

              Model Name: Mac mini
              Model Identifier: Mac16,10
              Model Number: MU9D3CH/A
              Chip: Apple M4
              Total Number of Cores: 10 (4 performance and 6 efficiency)
              Memory: 16 GB
              Serial Number (system): ABCD1234
            """
        let display = """
            Graphics/Displays:

                Chipset Model: Apple M4
                Total Number of Cores: 10
            """
        let info = HardwareInfoParsing.parseHardware(hardware, displayOutput: display)
        #expect(info.modelName == "Mac mini")
        #expect(info.chip == "Apple M4")
        #expect(info.gpuMemory.contains("共享"))
        #expect(info.serialNumber == "ABCD1234")
    }
}

@Suite("网络吞吐")
struct NetworkStatsParsingTests {

    @Test("两次计数器算出上下行速率")
    func throughputFromCounters() {
        let t0 = Date(timeIntervalSince1970: 1000)
        let t1 = Date(timeIntervalSince1970: 1002)
        let previous = [
            NetworkCounterSample(interface: "en0", bytesIn: 1000, bytesOut: 500, timestamp: t0)
        ]
        let current = [
            NetworkCounterSample(interface: "en0", bytesIn: 3000, bytesOut: 2500, timestamp: t1)
        ]
        let rate = NetworkStatsParsing.throughput(previous: previous, current: current)
        #expect(rate?.downloadBytesPerSecond == 1000)
        #expect(rate?.uploadBytesPerSecond == 1000)
    }
}

@Suite("温度解析")
struct TemperatureParsingTests {

    @Test("传感器标签与聚合")
    func aggregate() {
        let sensors = [
            TemperatureSensor(
                name: "pmu tdie0", label: TemperatureParsing.label(forRawName: "pmu tdie0"), celsius: 40),
            TemperatureSensor(
                name: "pmu tdie1", label: TemperatureParsing.label(forRawName: "pmu tdie1"), celsius: 50),
            TemperatureSensor(
                name: "gpu die", label: TemperatureParsing.label(forRawName: "gpu die"), celsius: 55)
        ]
        let snap = TemperatureParsing.aggregate(sensors: sensors, thermalStateLabel: "正常")
        #expect(snap.cpuAverage == 45)
        #expect(snap.cpuMax == 50)
        #expect(snap.gpuAverage == 55)
        #expect(snap.sensorAvailable)
        #expect(TemperatureParsing.severity(celsius: 90) == .warning)
    }
}
