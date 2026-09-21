// ShellCommandScriptTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import QuickPlatform

@Suite("终端命令脚本")
struct ShellCommandScriptTests {

    @Test("脚本以登录 Shell 起头，并先切到工作目录")
    func scriptStartsWithShebangAndCd() {
        let body = ShellCommandRunner.scriptBody(command: "ls", workingDirectory: "/tmp")
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)

        #expect(lines.first == "#!/bin/zsh -l")
        #expect(lines[1] == "cd '/tmp' || exit 1")
        #expect(lines[2] == "ls")
    }

    /// 工作目录里的空格与单引号必须被挡住，否则 `cd` 会跑偏
    @Test("工作目录按单引号包裹并转义")
    func workingDirectoryIsQuoted() {
        let plain = ShellCommandRunner.scriptBody(command: "ls", workingDirectory: "/My Apps")
        #expect(plain.contains("cd '/My Apps' || exit 1"))

        let tricky = ShellCommandRunner.scriptBody(command: "ls", workingDirectory: "/it's here")
        #expect(tricky.contains("cd '/it'\\''s here' || exit 1"))
    }

    /// 工作目录不存在时不该继续往下跑命令
    @Test("切不过去就退出，不执行命令")
    func cdFailureStopsTheScript() {
        let body = ShellCommandRunner.scriptBody(command: "rm -rf /", workingDirectory: "/nope")
        #expect(body.contains("|| exit 1"))
    }

    /// 这条是回归测试。
    ///
    /// 上一版是把命令拼进 AppleScript 源码的字符串字面量（`do script "cd '…' && \(命令)"`），
    /// 命令里带 `"` 就会把整段脚本拆坏 —— `NSAppleScript(source:)` 直接返回 nil，
    /// 连一条日志都没有，用户看到的就是「终端打开了、命令没跑」。
    ///
    /// 所以这里不满足于断言字符串长什么样，而是**真的让 zsh 跑一遍**：
    /// 带双引号、单引号和多行的命令必须原样生效。
    @Test("生成的脚本能被 zsh 真的执行，引号与多行都不走样")
    func generatedScriptActuallyRuns() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quick-shell-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let output = directory.appendingPathComponent("output.txt")
        let command = """
            echo "双引号 $((1 + 1))" > \(output.path)
            echo '单引号' >> \(output.path)
            """

        let script = directory.appendingPathComponent("command.command")
        try ShellCommandRunner.scriptBody(command: command, workingDirectory: directory.path)
            .write(to: script, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script.path]
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0, "脚本必须是一份 zsh 能跑通的脚本")
        let written = try String(contentsOf: output, encoding: .utf8)
        #expect(written == "双引号 2\n单引号\n", "命令要原样生效：引号不能被吞，变量要被展开")
    }
}
