// LocalCommand.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 起本地命令并读标准输出
///
/// 只给系统监控采集用：路径写死、不走 shell，避免注入面。
enum LocalCommand {

    /// 同步执行；失败返回空字符串（由调用方决定是否降级）
    nonisolated static func run(path: String, arguments: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
