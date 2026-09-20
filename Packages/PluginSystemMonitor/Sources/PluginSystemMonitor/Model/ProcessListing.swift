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

    /// 内存占用，带百分号
    let memoryUsage: String
}

/// `ps -eo pid,pcpu,pmem,comm -r` 输出的解析
///
/// 纯粹是字符串切分，不碰进程、管道和线程，所以能脱离系统独立断言。
enum ProcessListing {

    /// 进程列表上限
    ///
    /// 面板一屏就那么大，`ps -r` 已经按 CPU 排好序，排在后面的看也没用。
    static let maximumCount = 50

    /// 产出行数据的命令
    static let commandPath = "/bin/ps"
    static let commandArguments = ["-eo", "pid,pcpu,pmem,comm", "-r"]

    /// pid、pcpu、pmem 之外至少还要一个 comm 字段，不足 4 列的行直接丢弃
    private static let minimumColumnCount = 4

    /// 解析 `ps` 的标准输出
    ///
    /// 第一行是表头，无条件丢掉 —— 不靠内容识别表头，因为列名会随系统版本变。
    /// 截断（`maximumCount`）发生在丢弃非法行**之前**：先取前 50 行，
    /// 再逐行过滤，所以表里混进非法行会让结果少于 50 条。
    /// - Parameter output: `ps` 的标准输出
    /// - Returns: 进程条目，顺序与输入一致
    static func parse(_ output: String) -> [ProcessEntry] {
        let lines = output.components(separatedBy: "\n").dropFirst()

        return lines.prefix(maximumCount).compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }

            guard parts.count >= minimumColumnCount else { return nil }
            guard let pid = Int32(parts[0]) else { return nil }

            // comm 本身可能带空格（`Google Chrome`），第 4 列起重新拼回一个字段
            let name = parts[3...].joined(separator: " ")
            return ProcessEntry(
                id: pid,
                name: (name as NSString).lastPathComponent,
                cpuUsage: "\(parts[1])%",
                memoryUsage: "\(parts[2])%"
            )
        }
    }
}
