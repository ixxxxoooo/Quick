// NetworkStatsParsing.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 一块网络接口的摘要
struct NetworkInterfaceInfo: Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let addresses: [String]
    let isUp: Bool
}

/// 网络吞吐（字节/秒）；尚未采到第二帧时为 nil
struct NetworkThroughput: Sendable, Equatable {
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double

    var sidebarSummary: String {
        "↓ \(Self.formatRate(downloadBytesPerSecond))  ↑ \(Self.formatRate(uploadBytesPerSecond))"
    }

    static func formatRate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_048_576 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_048_576)
        }
        if bytesPerSecond >= 1024 {
            return String(format: "%.0f KB/s", bytesPerSecond / 1024)
        }
        return String(format: "%.0f B/s", bytesPerSecond)
    }
}

/// 接口计数器快照，用于算速率
struct NetworkCounterSample: Sendable, Equatable {
    let interface: String
    let bytesIn: UInt64
    let bytesOut: UInt64
    let timestamp: Date
}

/// 网络文本解析与速率计算
enum NetworkStatsParsing {

    /// 从两次计数器算吞吐（汇总所有接口）
    static func throughput(
        previous: [NetworkCounterSample],
        current: [NetworkCounterSample]
    ) -> NetworkThroughput? {
        guard let firstPrev = previous.first, let firstCurr = current.first else { return nil }
        let elapsed = firstCurr.timestamp.timeIntervalSince(firstPrev.timestamp)
        guard elapsed > 0.2 else { return nil }

        let prevMap = Dictionary(uniqueKeysWithValues: previous.map { ($0.interface, $0) })
        var down: Double = 0
        var up: Double = 0
        for sample in current {
            guard let old = prevMap[sample.interface] else { continue }
            if sample.bytesIn >= old.bytesIn {
                down += Double(sample.bytesIn - old.bytesIn) / elapsed
            }
            if sample.bytesOut >= old.bytesOut {
                up += Double(sample.bytesOut - old.bytesOut) / elapsed
            }
        }
        return NetworkThroughput(downloadBytesPerSecond: down, uploadBytesPerSecond: up)
    }

    /// 解析 `netstat -ib -I <iface>` 风格的汇总行不在这里；计数器由 Service 用 getifaddrs 填。
}
