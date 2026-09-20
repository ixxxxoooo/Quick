// ShellCommandRunner.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
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

/// 用户偏好的终端应用
public enum PreferredTerminal: String, CaseIterable, Sendable {
    case terminal = "com.apple.Terminal"
    case iterm = "com.googlecode.iterm2"
    case warp = "dev.warp.Warp-Stable"
    case kitty = "net.kovidgoyal.kitty"
    case alacritty = "org.alacritty"

    public var displayName: String {
        switch self {
        case .terminal: "终端 (Terminal)"
        case .iterm: "iTerm2"
        case .warp: "Warp"
        case .kitty: "Kitty"
        case .alacritty: "Alacritty"
        }
    }

    /// 检测系统中是否安装了此终端
    @MainActor
    public var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue) != nil
    }
}

/// Shell 命令执行器
///
/// 支持两种模式：
/// 1. 后台执行（原始模式）：在后台以 `/bin/zsh -l -c` 运行，适合无交互命令。
/// 2. 终端执行（新模式）：打开用户偏好的终端应用执行，适合需要交互的命令。
public enum ShellCommandRunner {

    private static let log = QuickLog.platform

    /// 在用户偏好的终端中打开命令
    ///
    /// 隐藏面板后直接唤起终端，让用户看到完整的输出和交互。
    @MainActor
    public static func runInTerminal(
        _ command: String,
        workingDirectory: String? = nil,
        terminal: PreferredTerminal = .terminal
    ) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let cwd = workingDirectory ?? NSHomeDirectory()
        // 转义单引号
        let escapedCmd = trimmed.replacingOccurrences(of: "'", with: "'\\''")
        let escapedCwd = cwd.replacingOccurrences(of: "'", with: "'\\''")

        switch terminal {
        case .terminal:
            // 使用 AppleScript 在 Terminal.app 中执行
            let script = """
                tell application "Terminal"
                    activate
                    do script "cd '\(escapedCwd)' && \(escapedCmd)"
                end tell
                """
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if let error {
                    log.error("Terminal AppleScript 执行失败：\(error, privacy: .public)")
                }
            }

        case .iterm:
            let script = """
                tell application "iTerm"
                    activate
                    set newWindow to (create window with default profile)
                    tell current session of newWindow
                        write text "cd '\(escapedCwd)' && \(escapedCmd)"
                    end tell
                end tell
                """
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if let error {
                    log.error("iTerm AppleScript 执行失败：\(error, privacy: .public)")
                }
            }

        default:
            // 通用方式：用 open 打开终端应用，然后用后台 shell 写入
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.rawValue) {
                NSWorkspace.shared.openApplication(
                    at: url,
                    configuration: NSWorkspace.OpenConfiguration()
                )
                // 对于 Warp/Kitty/Alacritty，回退到后台执行
                Task {
                    _ = await run("cd '\(escapedCwd)' && \(trimmed)")
                }
            } else {
                // 终端不存在，回退到默认 Terminal.app
                runInTerminal(command, workingDirectory: workingDirectory, terminal: .terminal)
            }
        }

        log.info("命令已发送到终端 \(terminal.displayName, privacy: .public)：\(trimmed.prefix(50), privacy: .public)")
    }

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
