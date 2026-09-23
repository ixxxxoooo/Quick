// DiskStatsParsing.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 一块已挂载卷的容量
struct DiskVolume: Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    /// GiB
    let totalGB: Double
    let availableGB: Double
    let isExternal: Bool

    var usedGB: Double { max(0, totalGB - availableGB) }

    var usedPercent: Double {
        guard totalGB > 0 else { return 0 }
        return (usedGB / totalGB) * 100
    }

    var freePercent: Double { max(0, 100 - usedPercent) }
}

/// 启动盘详情（来自 `diskutil info /`）
struct RootVolumeDetails: Sendable, Equatable {
    let volumeName: String
    let fileSystem: String
    let mediaType: String
    let protocolName: String
    let physicalStore: String
    let containerFreeSpace: String
    let containerTotalSpace: String
}

/// 解析 `df -kP` / `diskutil info`
enum DiskStatsParsing {

    /// 解析 `df -kP` 输出
    static func parseStorage(_ output: String) -> [DiskVolume] {
        let rows = output.split(separator: "\n").dropFirst().compactMap {
            line -> (device: String, mount: String, sizeKB: Double, availKB: Double)? in
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 6,
                let size = Double(parts[1]),
                let avail = Double(parts[3])
            else { return nil }
            let mount = parts[5...].joined(separator: " ")
            return (parts[0], mount, size, avail)
        }
        .filter { $0.mount == "/" || $0.mount.hasPrefix("/Volumes") }
        .filter { $0.mount != "/Volumes/Recovery" }

        let bootDevice = deviceNumber(rows.first(where: { $0.mount == "/" })?.device ?? "")

        return rows.map { row in
            let name =
                row.mount == "/"
                ? "Macintosh HD" : (row.mount.split(separator: "/").last.map(String.init) ?? row.mount)
            let device = deviceNumber(row.device)
            let isExternal = bootDevice != nil && device != nil && device != bootDevice
            return DiskVolume(
                id: row.mount,
                name: name,
                totalGB: row.sizeKB / 1024 / 1024,
                availableGB: row.availKB / 1024 / 1024,
                isExternal: isExternal
            )
        }
    }

    /// 解析 `diskutil info` 键值行
    static func parseRootVolume(_ output: String) -> RootVolumeDetails {
        RootVolumeDetails(
            volumeName: field(output, "Volume Name"),
            fileSystem: field(output, "File System Personality"),
            mediaType: field(output, "Media Type"),
            protocolName: field(output, "Protocol"),
            physicalStore: field(output, "APFS Physical Store"),
            containerFreeSpace: field(output, "Container Free Space"),
            containerTotalSpace: field(output, "Container Total Space")
        )
    }

    static func field(_ output: String, _ label: String) -> String {
        let pattern = try? NSRegularExpression(
            pattern: "^[ \\t]*\(NSRegularExpression.escapedPattern(for: label)):[ \\t]*(.+)$",
            options: .anchorsMatchLines)
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = pattern?.firstMatch(in: output, range: range),
            let valueRange = Range(match.range(at: 1), in: output)
        else {
            return "未知"
        }
        return String(output[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func deviceNumber(_ filesystem: String) -> Int? {
        guard let match = filesystem.firstMatch(of: /\/dev\/disk(\d+)/) else { return nil }
        return Int(match.1)
    }
}
