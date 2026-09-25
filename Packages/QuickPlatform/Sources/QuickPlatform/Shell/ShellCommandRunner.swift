// ShellCommandRunner.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Darwin
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
/// 1. 后台执行：在后台以 `/bin/zsh` 运行，捕获输出交给 HUD，适合无交互命令。
/// 2. 终端执行：打开用户偏好的终端应用执行，适合需要交互的命令。
public enum ShellCommandRunner {

    private static let log = QuickLog.platform

    private static let shell = "/bin/zsh"

    /// 只留尾部：失败时最后几行才是全部信息，成功时只显示一行
    private static let standardOutputLimit = 4 * 1024
    private static let standardErrorLimit = 8 * 1024

    /// 后台执行的默认超时
    ///
    /// 后台执行面向「无交互、很快出结果」的命令；30 秒还没退出的几乎一定挂住了，
    /// 留着它只会一直占着执行线程与临时文件。
    public static let defaultTimeout: TimeInterval = 30

    /// 并发上限：每条在跑的命令占一个阻塞在 `waitUntilExit` 上的线程和两个临时文件，
    /// 不设限会让一批慢命令耗尽线程与文件描述符。4 条足够覆盖面板里并排触发的场景。
    private static let maxConcurrentCommands = 4
    private static let slots = DispatchSemaphore(value: maxConcurrentCommands)

    /// `waitUntilExit` 会阻塞线程，所以执行放在专用并发队列上
    ///
    /// 不能用 `Task.detached`：那占的是 Swift 协作线程池的线程，池子只有核心数个，
    /// 一条卡住的命令就可能让面板的其他异步活一起排队。
    private static let queue = DispatchQueue(
        label: "com.ixxxxoooo.quick.shell-command", qos: .userInitiated, attributes: .concurrent)

    // MARK: - 后台执行

    /// 异步运行 shell 命令并返回结果
    /// - Parameters:
    ///   - command: 待运行的命令行字符串
    ///   - workingDirectory: 可选的工作目录（默认为用户主目录）；不存在则不执行
    ///   - loadingShellEnvironment: 是否用 `-ilc`（交互式）起 shell，见 `shellArguments`
    ///   - timeout: 超时秒数（默认 `defaultTimeout`）；超时后 terminate 进程并返回失败结果
    /// - Returns: 执行结果；超时、取消、无法启动等失败以 exitCode -1 + standardError 描述返回
    public static func run(
        _ command: String,
        workingDirectory: String? = nil,
        loadingShellEnvironment: Bool = false,
        timeout: TimeInterval = defaultTimeout
    ) async -> ShellCommandResult {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ShellCommandResult(exitCode: 0, standardOutput: "", standardError: "")
        }

        let running = RunningProcess()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async {
                    slots.wait()
                    defer { slots.signal() }
                    continuation.resume(
                        returning: execute(
                            trimmed, workingDirectory: workingDirectory,
                            loadingShellEnvironment: loadingShellEnvironment,
                            timeout: timeout, running: running))
                }
            }
        } onCancel: {
            running.terminate()
        }
    }

    private static func execute(
        _ command: String, workingDirectory: String?, loadingShellEnvironment: Bool,
        timeout: TimeInterval, running: RunningProcess
    ) -> ShellCommandResult {
        guard !running.terminationRequested else {
            return failure("命令已取消")
        }
        guard let directory = resolvedWorkingDirectory(workingDirectory) else {
            log.error("工作目录不存在，命令未执行：\(workingDirectory ?? "", privacy: .public)")
            return failure(missingDirectory(workingDirectory))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = shellArguments(
            command: command, loadingShellEnvironment: loadingShellEnvironment)
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        // 让 shell 配置能识别出调用者是 Quick，跳过慢的那几段
        process.environment = ProcessInfo.processInfo.environment.merging(["QUICK": "1"]) { _, new in
            new
        }
        // 承载性的一行：会提示输入的配置读到 EOF 就走开，永远不会挂在这里等
        process.standardInput = FileHandle.nullDevice

        let output = StreamCapture.make()
        let errors = StreamCapture.make()
        process.standardOutput = output?.handle ?? FileHandle.nullDevice
        process.standardError = errors?.handle ?? FileHandle.nullDevice
        defer {
            output?.remove()
            errors?.remove()
        }

        do {
            try process.run()
        } catch {
            log.error("启动 Shell 进程失败：\(error.localizedDescription, privacy: .public)")
            return failure("无法启动 \(shell)：\(error.localizedDescription)")
        }
        running.attach(process)

        // 轮询而不是裸 waitUntilExit：超时与取消都得有机会插进来终止进程，
        // 否则永不退出的命令（如 cat 等输入）会把线程和 continuation 永久泄漏
        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while process.isRunning {
            if Date() >= deadline {
                timedOut = true
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        if timedOut || running.terminationRequested {
            process.terminate()
        }
        process.waitUntilExit()

        if timedOut {
            log.error("命令超过 \(Int(timeout), privacy: .public) 秒未退出，已终止")
            return failure("命令执行超时（超过 \(Int(timeout)) 秒），进程已终止")
        }
        if running.terminationRequested {
            log.info("命令已取消，进程已终止")
            return failure("命令已取消")
        }

        let status = process.terminationStatus
        log.info("命令执行完毕，退出码=\(status, privacy: .public)")
        return ShellCommandResult(
            exitCode: status,
            standardOutput: output?.readSuffix(limit: standardOutputLimit) ?? "",
            standardError: errors?.readSuffix(limit: standardErrorLimit) ?? "")
    }

    private static func failure(_ message: String) -> ShellCommandResult {
        ShellCommandResult(exitCode: -1, standardOutput: "", standardError: message)
    }

    /// 目录不存在就拒绝执行
    ///
    /// 在一个意料之外的地方跑用户的命令，比不跑更糟 —— 用户看到的是一条明确的原因，
    /// 而不是命令在别处静静跑完。
    private static func resolvedWorkingDirectory(_ path: String?) -> String? {
        guard let path, !path.isEmpty else {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        let expanded = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { return nil }
        return expanded
    }

    private static func missingDirectory(_ path: String?) -> String {
        "工作目录「\(path ?? "")」不存在，命令未执行"
    }

    /// 传给 zsh 的参数
    ///
    /// `-l` 只读 `.zprofile`。zsh 只在**交互式** shell 里 source `.zshrc`，所以别名、以及
    /// 写在 `.zshrc` 里的 PATH 段（nvm、pyenv 之类）在 `-lc` 下全都看不见 —— 用户在自己
    /// 终端里好好的命令，在这里会退化成「command not found」。
    ///
    /// 用户亲自输入的场合要带上 `-i`：`>` 直执行与终端兜底都是「用户当下打出来的一句话」，他打 `ll` 指的就是自己的别名，
    /// 所以这两种走 `-ilc`。存下来的自定义命令默认仍是 `-lc`：每次多付一份配置加载时间，
    /// 该由用户在编辑那条命令时自己决定（`CustomCommand.loadsShellEnvironment`）。
    ///
    /// 抽成纯函数是为了能直接断言参数，不必真的起进程。
    static func shellArguments(command: String, loadingShellEnvironment: Bool) -> [String] {
        [loadingShellEnvironment ? "-ilc" : "-lc", command]
    }

    // MARK: - 终端执行

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

        let cwd = workingDirectory.map { ($0 as NSString).expandingTildeInPath } ?? NSHomeDirectory()

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
    /// 抽成纯函数是为了能直接断言它。三件事都是有原因的：
    ///
    /// - **`-il` 而不是 `-l`：** 用户打的是自己终端里的一句话，别名与 `.zshrc` 里的 PATH
    ///   必须生效，否则 `cs`、`ll` 这种在他终端里好好的命令会说找不到。
    /// - **`cd … || exit 1`：** 切不过去就不往下跑，绝不在意料之外的目录里执行命令。
    /// - **末尾交接给交互式 shell：** 没有它，命令一返回登录 shell 就退出，终端随即结束会话
    ///   （Basic 配置是「干净退出即关窗」），用户连输出都来不及看 —— 表现是窗口一闪就没。
    ///   用 `-t 0` 守住：只有在真的挂在终端上时才交接，非终端调用（测试、被别的程序打开）
    ///   仍然是一次性执行，退出码不受影响。
    ///
    /// - Parameters:
    ///   - command: 用户输入的命令，**原样**写进脚本
    ///   - workingDirectory: 工作目录，作为 `cd` 的参数
    /// - Returns: 脚本全文
    static func scriptBody(command: String, workingDirectory: String) -> String {
        """
        #!/bin/zsh -il +m
        cd \(quoted(workingDirectory)) || exit 1
        \(command)
        if [ -t 0 ]; then exec /bin/zsh -il; fi
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
}

/// 一次后台执行的「终止请求」信箱
///
/// `onCancel` 回调与执行线程不在同一个线程上，而且取消可能先于进程创建到达，
/// 所以请求要记账（`NSLock` 保护），而不是直接对一个可能还不存在的 `Process` 发信号。
/// `@unchecked Sendable` 的依据：所有可变状态都在 `lock` 临界区内访问。
private final class RunningProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var requested = false

    var terminationRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return requested
    }

    func attach(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldTerminate = requested
        lock.unlock()
        if shouldTerminate { process.terminate() }
    }

    func terminate() {
        lock.lock()
        requested = true
        let process = self.process
        lock.unlock()
        process?.terminate()
    }
}

/// stdout / stderr 的收集器：一个临时文件，退出后按需读尾部
///
/// **不能用 `Pipe`。** 父进程先 `waitUntilExit()`，管道的读端就一直没人在读；子进程写满
/// 管道缓冲区（macOS 上 64 KiB）之后阻塞在 write 上 —— 子进程等父进程读，父进程等子进程
/// 退出，双方永远不动。任何输出超过 64 KiB 的命令（`git log`、`find`、`npm install`）
/// 都会把这次执行永久挂住，连一条日志都不会留下。
///
/// 临时文件没有这个上限，也没有「谁先读」的顺序问题：退出后从尾部读回上限内的内容即可。
/// 与 Tinycast 的做法一致（那里同样写着「A temp file, not a Pipe」）。
private final class StreamCapture: @unchecked Sendable {
    let url: URL
    let handle: FileHandle

    init(url: URL, handle: FileHandle) {
        self.url = url
        self.handle = handle
    }

    func readSuffix(limit: Int) -> String {
        try? handle.synchronize()
        guard let end = try? handle.seekToEnd() else { return "" }
        let start = end > UInt64(limit) ? end - UInt64(limit) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return "" }
        // 按字节偏移取尾可能落在字符中间；丢掉那些续字节，免得多出一个 U+FFFD
        let body = start > 0 ? data.drop { $0 & 0xC0 == 0x80 } : data[...]
        return String(decoding: body, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func remove() {
        try? handle.close()
        try? FileManager.default.removeItem(at: url)
    }

    static func make() -> StreamCapture? {
        let template = FileManager.default.temporaryDirectory
            .appendingPathComponent("quick-command-stream.XXXXXX").path
        var bytes = Array(template.utf8CString)
        let descriptor = bytes.withUnsafeMutableBufferPointer { buffer in
            mkstemp(buffer.baseAddress!)
        }
        guard descriptor >= 0 else { return nil }
        let path = String(
            decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return StreamCapture(
            url: URL(fileURLWithPath: path),
            handle: FileHandle(fileDescriptor: descriptor, closeOnDealloc: true))
    }
}
