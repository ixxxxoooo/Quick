// TemperatureParsing.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 单个温度传感器读数
struct TemperatureSensor: Sendable, Equatable, Identifiable {
    var id: String { name }
    let name: String
    let label: String
    let celsius: Double
}

/// 温度快照
struct TemperatureSnapshot: Sendable, Equatable {
    let sensors: [TemperatureSensor]
    let cpuAverage: Double?
    let cpuMax: Double?
    let gpuAverage: Double?
    /// 系统热压力（公开 API，始终可用）
    let thermalStateLabel: String
    let sensorAvailable: Bool

    var sidebarSummary: String {
        if let cpuAverage {
            return SystemMetrics.formatTemperature(cpuAverage)
        }
        return thermalStateLabel
    }
}

/// 温度展示与分级
enum TemperatureParsing {

    static func label(forRawName name: String) -> String {
        let lower = name.lowercased()
        if let match = lower.firstMatch(of: /tdie(\d+)/) {
            return "Die 传感器 \(match.1)"
        }
        if let match = lower.firstMatch(of: /tdev(\d+)/) {
            return "设备传感器 \(match.1)"
        }
        if lower.contains("gpu") { return "GPU" }
        if lower.contains("battery") || lower.contains("gas gauge") { return "电池" }
        if lower.contains("nand") { return "存储" }
        if lower.contains("die") { return "CPU Die" }
        return name
    }

    static func aggregate(sensors: [TemperatureSensor], thermalStateLabel: String) -> TemperatureSnapshot {
        let cpu = sensors.filter {
            let lower = $0.name.lowercased()
            return lower.contains("die") && !lower.contains("gpu")
        }.map(\.celsius)
        let gpu = sensors.filter { $0.name.lowercased().contains("gpu") }.map(\.celsius)

        return TemperatureSnapshot(
            sensors: sensors.sorted { $0.label < $1.label },
            cpuAverage: average(cpu),
            cpuMax: cpu.max(),
            gpuAverage: average(gpu),
            thermalStateLabel: thermalStateLabel,
            sensorAvailable: !sensors.isEmpty
        )
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return (values.reduce(0, +) / Double(values.count) * 10).rounded() / 10
    }

    static func severity(celsius: Double) -> SystemMetrics.PressureTone {
        if celsius <= 0 { return .muted }
        if celsius >= 95 { return .critical }
        if celsius >= 80 { return .warning }
        if celsius >= 65 { return .elevated }
        return .normal
    }

    static func thermalStateLabel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "正常"
        case .fair: "偏热"
        case .serious: "较高"
        case .critical: "危急"
        @unknown default: "未知"
        }
    }
}

extension SystemMetrics {
    static func formatTemperature(_ celsius: Double) -> String {
        guard celsius > 0 else { return "N/A" }
        return "\(Int(celsius.rounded())) °C"
    }
}
