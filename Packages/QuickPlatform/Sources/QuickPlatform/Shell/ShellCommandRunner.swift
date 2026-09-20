// ShellCommandRunner.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// Shell 命令执行结果
public struct ShellCommandResult: Sendable, Equatable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public var succeeded: Bool { exitCode == 0 }

    public var summary: String {
        if !standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !standardError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return succeeded ? "执行成功" : "执行失败（退出码 \(exitCode)）"
    }

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

/// Shell 命令执行器
///
/// 参考 Tinycast，在后台以 `/bin/zsh -l -c` 运行命令，
/// 自动加载用户环境以支持别名与常用 PATH 工具（如 brew、node 等）。
public enum ShellCommandRunner {

    private static let log = QuickLog.platform

    /// 异步运行 shell 命令并返回结果
    /// - Parameters:
    ///   - command: 待运行的命令行字符串
    ///   - workingDirectory: 可选的工作目录（默认当前用户主目录）
    /// - Returns: 执行结果
    public static func run(
        _ command: String,
        workingDirectory: String? = nil
    ) async -> ShellCommandResult {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ShellCommandResult(exitCode: 0, standardOutput: "", standardError: "")
        }

        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            // -l 启动登录 Shell，继承 PATH 与环境变量
            process.arguments = ["-l", "-c", trimmed]

            let cwd = workingDirectory ?? NSHomeDirectory()
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
                process.waitUntilExit()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                log.info("命令执行完毕，退出码=\(process.terminationStatus, privacy: .public)")
                return ShellCommandResult(
                    exitCode: process.terminationStatus,
                    standardOutput: stdout,
                    standardError: stderr
                )
            } catch {
                log.error("启动 Shell 进程失败：\(error.localizedDescription, privacy: .public)")
                return ShellCommandResult(
                    exitCode: -1,
                    standardOutput: "",
                    standardError: error.localizedDescription
                )
            }
        }.value
    }
}
