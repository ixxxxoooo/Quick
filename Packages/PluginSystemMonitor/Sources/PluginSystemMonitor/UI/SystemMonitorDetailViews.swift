// SystemMonitorDetailViews.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickUI
import SwiftUI

// MARK: - 共享行

/// 左标签右数值的明细行
private struct MonitorMetricRow: View {
    let title: String
    let value: String
    var tone: SystemMetrics.PressureTone = .muted

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(DesignTokens.Typography.bar)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Spacer(minLength: DesignTokens.Spacing.md)
            Text(value)
                .font(DesignTokens.Typography.code)
                .foregroundStyle(valueColor)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    private var valueColor: Color {
        switch tone {
        case .normal: DesignTokens.Colors.success
        case .elevated: DesignTokens.Colors.progress
        case .warning: DesignTokens.Colors.warning
        case .critical: DesignTokens.Colors.destructive
        case .muted: DesignTokens.Colors.textPrimary
        }
    }
}

private struct MonitorSectionTitle: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(DesignTokens.Typography.keyCap)
            .foregroundStyle(DesignTokens.Colors.textTertiary)
            .tracking(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.top, DesignTokens.Spacing.lg)
            .padding(.bottom, DesignTokens.Spacing.xs)
    }
}

private struct MonitorScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.bottom, DesignTokens.Spacing.xxl)
        }
    }
}

// MARK: - System Info

struct SystemInfoDetailView: View {
    let scanner: ProcessScanner

    var body: some View {
        MonitorScroll {
            MonitorSectionTitle(title: "软件")
            MonitorMetricRow(title: "macOS", value: scanner.software?.osVersion ?? "…")

            MonitorSectionTitle(title: "硬件规格")
            if let hardware = scanner.hardware {
                MonitorMetricRow(title: "主机名", value: scanner.software?.hostname ?? "—")
                MonitorMetricRow(title: "机型", value: hardware.modelName)
                MonitorMetricRow(title: "型号标识符", value: hardware.modelIdentifier)
                MonitorMetricRow(title: "型号号码", value: hardware.modelNumber)
                MonitorMetricRow(title: "芯片", value: hardware.chip)
                MonitorMetricRow(title: "CPU 核心", value: hardware.totalCores)
                MonitorMetricRow(title: "GPU", value: hardware.gpuChipset)
                MonitorMetricRow(title: "GPU 核心", value: hardware.gpuCores)
                MonitorMetricRow(title: "GPU 内存", value: hardware.gpuMemory)
                MonitorMetricRow(title: "内存", value: hardware.memory)
                MonitorMetricRow(title: "序列号", value: hardware.serialNumber)
                MonitorMetricRow(title: "运行时间", value: scanner.software?.uptime ?? "—")
            } else {
                MonitorMetricRow(title: "状态", value: "正在读取硬件信息…")
            }
        }
    }
}

// MARK: - CPU

struct CPUDetailView: View {
    let scanner: ProcessScanner
    let mode: UsageDisplayMode

    var body: some View {
        MonitorScroll {
            MonitorSectionTitle(title: "概览")
            if let hardware = scanner.hardware {
                MonitorMetricRow(title: "芯片", value: hardware.chip)
                MonitorMetricRow(title: "CPU 核心", value: hardware.totalCores)
                MonitorMetricRow(title: "GPU 内存", value: hardware.gpuMemory)
            }
            if let used = scanner.cpuUsagePercent {
                let displayed = SystemMetrics.displayedPercent(used: used, mode: mode)
                let tone = SystemMetrics.tone(
                    forPressure: SystemMetrics.pressure(fromDisplayed: displayed, mode: mode))
                MonitorMetricRow(
                    title: mode == .free ? "空闲" : "占用",
                    value: SystemMetrics.percent(displayed),
                    tone: tone
                )
            } else {
                MonitorMetricRow(title: "占用", value: "采样中…")
            }

            if !scanner.loadAverage.isEmpty {
                MonitorMetricRow(
                    title: "负载均值",
                    value: scanner.loadAverage.joined(separator: " / ")
                )
            }
            MonitorMetricRow(title: "运行时间", value: scanner.software?.uptime ?? "—")

            MonitorSectionTitle(title: "高占用进程")
            if scanner.topCPUProcesses.isEmpty {
                MonitorMetricRow(title: "进程", value: "暂无数据")
            } else {
                ForEach(Array(scanner.topCPUProcesses.enumerated()), id: \.element.id) { index, proc in
                    MonitorMetricRow(
                        title: "#\(index + 1) · \(proc.name) (PID \(proc.id))",
                        value: proc.cpuUsage.replacingOccurrences(of: "%", with: " %")
                    )
                }
            }

            MonitorSectionTitle(title: "每核占用")
            if scanner.perCoreUsage.isEmpty {
                MonitorMetricRow(title: "核心", value: "采样中…")
            } else {
                ForEach(scanner.perCoreUsage) { core in
                    MonitorMetricRow(
                        title: "核心 \(core.id)",
                        value: SystemMetrics.percent(core.usagePercent),
                        tone: SystemMetrics.tone(forPressure: core.usagePercent)
                    )
                }
            }
        }
    }
}

// MARK: - Memory

struct MemoryDetailView: View {
    let scanner: ProcessScanner
    let mode: UsageDisplayMode

    var body: some View {
        MonitorScroll {
            if let memory = scanner.memory {
                MonitorSectionTitle(title: "内存")
                MonitorMetricRow(
                    title: "总内存",
                    value: "\(Int((memory.totalMB / 1024).rounded())) GB"
                )
                if mode == .free {
                    MonitorMetricRow(
                        title: "空闲内存",
                        value: "\(Int(((memory.totalMB - memory.usedMB) / 1024).rounded())) GB"
                    )
                    let free = memory.freePercent
                    MonitorMetricRow(
                        title: "空闲占比",
                        value: SystemMetrics.percent(free),
                        tone: SystemMetrics.tone(
                            forPressure: SystemMetrics.pressure(fromDisplayed: free, mode: .free))
                    )
                } else {
                    MonitorMetricRow(
                        title: "已用内存",
                        value: "\(Int((memory.usedMB / 1024).rounded())) GB"
                    )
                    MonitorMetricRow(
                        title: "已用占比",
                        value: SystemMetrics.percent(memory.usedPercent),
                        tone: SystemMetrics.tone(forPressure: memory.usedPercent)
                    )
                }
                MonitorMetricRow(title: "活跃", value: SystemMetrics.megabytesAsGigabytes(memory.activeMB))
                MonitorMetricRow(title: "非活跃", value: SystemMetrics.megabytesAsGigabytes(memory.inactiveMB))
                MonitorMetricRow(title: "联动", value: SystemMetrics.megabytesAsGigabytes(memory.wiredMB))
                MonitorMetricRow(title: "已压缩", value: SystemMetrics.megabytesAsGigabytes(memory.compressedMB))
                MonitorMetricRow(title: "可清除", value: SystemMetrics.megabytesAsGigabytes(memory.purgeableMB))
                MonitorMetricRow(
                    title: "交换已用",
                    value:
                        "\(SystemMetrics.megabytes(memory.swapUsedMB)) / \(SystemMetrics.megabytes(memory.swapTotalMB))"
                )
                MonitorMetricRow(
                    title: "内存压力",
                    value: memory.pressureLabel,
                    tone: SystemMetrics.tone(forPressureLabel: memory.pressureLabel)
                )
            } else {
                MonitorMetricRow(title: "状态", value: "正在读取内存…")
            }

            MonitorSectionTitle(title: "高占用进程")
            if scanner.topMemoryProcesses.isEmpty {
                MonitorMetricRow(title: "进程", value: "暂无数据")
            } else {
                ForEach(Array(scanner.topMemoryProcesses.enumerated()), id: \.element.id) { index, proc in
                    MonitorMetricRow(
                        title: "#\(index + 1) · \(proc.name) (PID \(proc.id))",
                        value: proc.memoryRss
                    )
                }
            }
        }
    }
}

// MARK: - Disk

struct DiskDetailView: View {
    let scanner: ProcessScanner
    let mode: UsageDisplayMode

    var body: some View {
        MonitorScroll {
            if let root = scanner.rootVolume {
                MonitorSectionTitle(title: "启动卷")
                MonitorMetricRow(title: "卷名", value: root.volumeName)
                MonitorMetricRow(title: "文件系统", value: root.fileSystem)
                MonitorMetricRow(title: "介质类型", value: root.mediaType)
                MonitorMetricRow(title: "协议", value: root.protocolName)
                MonitorMetricRow(title: "物理存储", value: root.physicalStore)
                MonitorMetricRow(title: "容器可用", value: root.containerFreeSpace)
                MonitorMetricRow(title: "容器总量", value: root.containerTotalSpace)
            }

            MonitorSectionTitle(title: "容量")
            if scanner.disks.isEmpty {
                MonitorMetricRow(title: "磁盘", value: "暂无数据")
            } else {
                ForEach(scanner.disks) { disk in
                    let displayed = SystemMetrics.displayedPercent(used: disk.usedPercent, mode: mode)
                    let tone = SystemMetrics.tone(
                        forPressure: SystemMetrics.pressure(fromDisplayed: displayed, mode: mode))
                    let label = disk.isExternal ? "\(disk.name)（外置）" : disk.name
                    MonitorMetricRow(
                        title: label,
                        value: String(
                            format: "%.1f / %.1f GB · %@",
                            mode == .free ? disk.availableGB : disk.usedGB,
                            disk.totalGB,
                            SystemMetrics.percent(displayed)
                        ),
                        tone: tone
                    )
                }
            }
        }
    }
}

// MARK: - Power

struct PowerDetailView: View {
    let scanner: ProcessScanner
    let mode: UsageDisplayMode

    var body: some View {
        MonitorScroll {
            MonitorSectionTitle(title: "电源")
            if let power = scanner.power {
                if power.hasBattery {
                    MonitorMetricRow(
                        title: mode == .free ? "剩余电量" : "已用电量",
                        value: PowerStatsParsing.displayedLevel(power.batteryPercent, mode: mode)
                    )
                    MonitorMetricRow(title: "充电中", value: power.isCharging ? "是" : "否")
                    MonitorMetricRow(title: "电源", value: power.isOnACPower ? "交流电" : "电池")
                    MonitorMetricRow(title: "电池状况", value: power.condition)
                    MonitorMetricRow(title: "循环次数", value: power.cycleCount)
                } else {
                    MonitorMetricRow(title: "电池", value: "此 Mac 无内置电池")
                    MonitorMetricRow(title: "电源", value: power.isOnACPower ? "交流电" : "未知")
                }
            } else {
                MonitorMetricRow(title: "状态", value: "正在读取…")
            }
        }
    }
}

// MARK: - Network

struct NetworkDetailView: View {
    let scanner: ProcessScanner

    var body: some View {
        MonitorScroll {
            MonitorSectionTitle(title: "吞吐")
            if let throughput = scanner.networkThroughput {
                MonitorMetricRow(
                    title: "下载", value: NetworkThroughput.formatRate(throughput.downloadBytesPerSecond))
                MonitorMetricRow(
                    title: "上传", value: NetworkThroughput.formatRate(throughput.uploadBytesPerSecond))
            } else {
                MonitorMetricRow(title: "速率", value: "采样中…")
            }

            MonitorSectionTitle(title: "接口")
            if scanner.networkInterfaces.isEmpty {
                MonitorMetricRow(title: "接口", value: "暂无数据")
            } else {
                ForEach(scanner.networkInterfaces) { iface in
                    let address = iface.addresses.first ?? "—"
                    MonitorMetricRow(
                        title: "\(iface.name)\(iface.isUp ? "" : "（未连接）")",
                        value: address
                    )
                }
            }
        }
    }
}

// MARK: - Temperature

struct TemperatureDetailView: View {
    let scanner: ProcessScanner

    var body: some View {
        MonitorScroll {
            MonitorSectionTitle(title: "热状态")
            if let temperature = scanner.temperature {
                MonitorMetricRow(title: "系统热压力", value: temperature.thermalStateLabel)
                if let cpuAverage = temperature.cpuAverage {
                    MonitorMetricRow(
                        title: "CPU 平均",
                        value: SystemMetrics.formatTemperature(cpuAverage),
                        tone: TemperatureParsing.severity(celsius: cpuAverage)
                    )
                }
                if let cpuMax = temperature.cpuMax {
                    MonitorMetricRow(
                        title: "CPU 最高",
                        value: SystemMetrics.formatTemperature(cpuMax),
                        tone: TemperatureParsing.severity(celsius: cpuMax)
                    )
                }
                if let gpuAverage = temperature.gpuAverage {
                    MonitorMetricRow(
                        title: "GPU 平均",
                        value: SystemMetrics.formatTemperature(gpuAverage),
                        tone: TemperatureParsing.severity(celsius: gpuAverage)
                    )
                }

                MonitorSectionTitle(title: "传感器")
                if temperature.sensors.isEmpty {
                    MonitorMetricRow(title: "读数", value: "当前机型未暴露 HID 温度传感器")
                } else {
                    ForEach(temperature.sensors) { sensor in
                        MonitorMetricRow(
                            title: sensor.label,
                            value: SystemMetrics.formatTemperature(sensor.celsius),
                            tone: TemperatureParsing.severity(celsius: sensor.celsius)
                        )
                    }
                }
            } else {
                MonitorMetricRow(title: "状态", value: "正在读取…")
            }
        }
    }
}
