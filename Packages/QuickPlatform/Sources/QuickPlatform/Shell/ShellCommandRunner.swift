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
    /// ## 为什么是「写一个脚本文件、交给 LaunchServices 打开」而不是 AppleScript
    ///
    /// 这里原来用的是 `tell application "Terminal" … do script "…"`，它有两个坑，
    /// 而且失败时都是**静默**的，表现出来正是「终端打开了、命令没跑」：
    ///
    /// 1. **它要「自动化」权限。** 这个权限按代码签名授予，而每重新构建一次 dev 版就换了
    ///    一份签名，授权随之失效 —— 开发期这个功能基本是坏的。
    /// 2. **命令文本是拼进 AppleScript 源码里的字符串字面量。** 命令里带 `"` 或换行就会把
    ///    脚本本身拆坏，`NSAppleScript(source:)` 直接返回 nil，连一条日志都没有。
    ///
    /// 交给 LaunchServices 打开 `.command` 文件不需要任何权限；命令也只是文件内容，
    /// 不再是谁的源码，所以不需要转义。做法与 Tinycast 同向：那条路完全不碰 AppleEvents。
    @MainActor
    public static func runInTerminal(
        _ command: String,
        workingDirectory: String? = nil,
        terminal: PreferredTerminal = .terminal
    ) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let cwd = workingDirectory ?? NSHomeDirectory()

        guard let script = try? writeScript(command: trimmed, workingDirectory: cwd) else {
            log.error("终端脚本创建失败，命令未执行")
            EventBus.shared.post(ShowHUDEvent(message: "无法创建终端脚本，命令未执行", tone: .warning))
            return
        }

        open(script: script, in: terminal, command: trimmed)
    }

    /// 把命令写成一个 `.command` 脚本
    ///
    /// 终端是在文件被打开之后才去读它的，所以这里不能删；改为每次写新脚本前先清掉上一个，
    /// 免得在用户的临时目录里越积越多。
    private static func writeScript(command: String, workingDirectory: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Quick/TerminalCommands", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let stale =
            (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
            ?? []
        for url in stale { try? FileManager.default.removeItem(at: url) }

        let script = directory.appendingPathComponent("command.command")
        try scriptBody(command: command, workingDirectory: workingDirectory)
            .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        return script
    }

    /// `.command` 脚本的内容
    ///
    /// 抽成纯函数是为了能直接断言它：上一版把命令拼进 AppleScript 源码的字符串字面量，
    /// 命令里带 `"` 或换行就把整段拆坏 —— 这里不存在那种可能。
    ///
    /// - Parameters:
    ///   - command: 用户输入的命令，**原样**写进脚本
    ///   - workingDirectory: 工作目录，作为 `cd` 的参数
    /// - Returns: 脚本全文
    static func scriptBody(command: String, workingDirectory: String) -> String {
        // `-l` 起登录 Shell：用户终端里的 PATH 与别名才在
        """
        #!/bin/zsh -l
        cd \(quoted(workingDirectory)) || exit 1
        \(command)
        """
    }

    /// 单引号包裹，只用在脚本里的 `cd`
    ///
    /// 命令本身不转义 —— 它写在脚本文件里，不再是被谁解析的字符串。
    private static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// 交给指定的终端打开脚本
    ///
    /// 没装、或者它不处理 `.command` 文件（Warp / Kitty 之类），就交给系统默认的处理程序 ——
    /// 命令已经写好在文件里了，不该因为选错终端就把它丢掉。
    @MainActor
    private static func open(script: URL, in terminal: PreferredTerminal, command: String) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.rawValue) else {
            log.notice("未安装 \(terminal.displayName, privacy: .public)，改用系统默认终端")
            openWithDefaultHandler(script: script, command: command)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([script], withApplicationAt: app, configuration: configuration) { _, error in
            guard let error else { return }
            Task { @MainActor in
                log.warning(
                    """
                    \(terminal.displayName, privacy: .public) 打不开终端脚本，改用默认终端：\
                    \(error.localizedDescription, privacy: .public)
                    """)
                openWithDefaultHandler(script: script, command: command)
            }
        }
    }

    /// 交给系统默认的 `.command` 处理程序
    @MainActor
    private static func openWithDefaultHandler(script: URL, command: String) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(script, configuration: configuration) { _, error in
            guard let error else {
                log.info("命令已交给终端：\(command.prefix(50), privacy: .public)")
                return
            }
            Task { @MainActor in
                log.error("没有终端能运行脚本：\(error.localizedDescription, privacy: .public)")
                EventBus.shared.post(ShowHUDEvent(message: "没有可用的终端，命令未执行", tone: .warning))
            }
        }
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
