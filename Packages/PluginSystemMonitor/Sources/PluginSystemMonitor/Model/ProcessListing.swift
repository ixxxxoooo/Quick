// ProcessListing.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// `ps` 输出里的一行进程
///
/// 名字不叫 `ProcessInfo`：那样会和 `Foundation.ProcessInfo` 撞名，
/// 调用方不得不处处写 `Foundation.` 前缀。
struct ProcessEntry: Identifiable, Sendable, Equatable {

    /// 进程号
    let id: Int32

    /// 可执行文件名（已去掉目录路径）
    let name: String

    /// CPU 占用，带百分号
    let cpuUsage: String

    /// 内存占用百分比，带百分号
    let memoryUsage: String

    /// 物理内存 RSS 的人类可读形式（如 `664 MB`）
    let memoryRss: String
}

/// `ps` 排序方式
enum ProcessSortMode: Sendable {
    /// 按 CPU 降序（`-r`）
    case cpu
    /// 按内存降序（`-m`）
    case memory

    var flag: String {
        switch self {
        case .cpu: "-r"
        case .memory: "-m"
        }
    }
}

/// `ps -axo pid=,pcpu=,pmem=,rss=,comm= …` 输出的解析
///
/// 纯粹是字符串切分，不碰进程、管道和线程，所以能脱离系统独立断言。
enum ProcessListing {

    /// 进程列表上限
    ///
    /// 面板一屏就那么大，`ps` 已经按目标指标排好序，排在后面的看也没用。
    static let maximumCount = 50

    /// Top Processes 预览条数（对齐 Raycast）
    static let topPreviewCount = 5

    /// 产出行数据的命令
    static let commandPath = "/bin/ps"

    /// 列契约：pid / pcpu / pmem / rss / comm
    static let columnSpec = "pid=,pcpu=,pmem=,rss=,comm="

    /// 历史兼容：默认按 CPU 排序的完整参数表
    static let commandArguments = ["-axo", columnSpec, ProcessSortMode.cpu.flag]

    static func commandArguments(sort: ProcessSortMode) -> [String] {
        ["-axo", columnSpec, sort.flag]
    }

    /// pid、pcpu、pmem、rss 之外至少还要一个 comm 字段
    private static let minimumColumnCount = 5

    /// 解析 `ps` 的标准输出
    ///
    /// 新格式用 `pid=` 抑制表头，但仍兼容带表头的旧输出：第一行若 pid 不可解析就丢掉。
    /// 截断（`maximumCount`）发生在丢弃非法行**之前**。
    /// - Parameters:
    ///   - output: `ps` 的标准输出
    ///   - limit: 最多保留多少行（默认 `maximumCount`）
    /// - Returns: 进程条目，顺序与输入一致
    static func parse(_ output: String, limit: Int = maximumCount) -> [ProcessEntry] {
        let lines = output.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let body: ArraySlice<String>
        if let first = lines.first,
            Int32(first.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? "") == nil
        {
            body = lines.dropFirst()
        } else {
            body = lines[...]
        }

        return body.prefix(limit).compactMap(parseLine)
    }

    /// 解析单行
    private static func parseLine(_ line: String) -> ProcessEntry? {
        let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard parts.count >= minimumColumnCount else { return nil }
        guard let pid = Int32(parts[0]) else { return nil }
        guard let rss = Int(parts[3]) else { return nil }

        let name = parts[4...].joined(separator: " ")
        return ProcessEntry(
            id: pid,
            name: (name as NSString).lastPathComponent,
            cpuUsage: "\(parts[1])%",
            memoryUsage: "\(parts[2])%",
            memoryRss: SystemMetrics.rssKilobytes(rss)
        )
    }
}
