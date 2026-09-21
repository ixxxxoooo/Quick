// ShellCommandRunnerTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import QuickPlatform

@Suite("Shell 命令执行")
struct ShellCommandRunnerTests {

    /// 大输出必须能返回
    ///
    /// 这条是回归测试，盯着一个**已经发生过的**故障：收输出的 `Pipe` 从来没人读，子进程
    /// 写满管道缓冲区（macOS 上 64 KiB）后就阻塞在 write 上，而父进程正卡在 `waitUntilExit`
    /// —— 双方永远不动。任何输出超过 64 KiB 的命令（`git log`、`find`、`npm install`）都会
    /// 把这次执行永久挂住，连一条日志都不留，用户看到的就是「按了回车，什么都没发生」。
    ///
    /// 断言方式是把执行和 20 秒的定时器放进同一个任务组里赛跑：先返回的那一边说了算。
    /// 卡住时这个测试会失败而不是把整个测试进程拖住。
    @Test("输出超过 64 KiB 的命令不会把执行挂住")
    func largeOutputDoesNotHang() async {
        let finished = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                let result = await ShellCommandRunner.run("yes aaaa | head -c 200000")
                return result.succeeded
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(20))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        #expect(finished, "输出 200000 字节的命令必须正常返回，不能挂在管道上")
    }

    @Test("stdout 与 stderr 分开收集，退出码原样带回来")
    func streamsAndExitCodeAreCaptured() async {
        let result = await ShellCommandRunner.run("echo 到标准输出; echo 到标准错误 >&2; exit 3")

        #expect(result.exitCode == 3)
        #expect(!result.succeeded)
        #expect(result.standardOutput.contains("到标准输出"))
        #expect(result.standardError.contains("到标准错误"))
    }

    /// 在一个意料之外的地方跑用户的命令，比不跑更糟
    @Test("工作目录不存在时拒绝执行，且命令真的没跑")
    func missingWorkingDirectoryRefusesToRun() async throws {
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("quick-missing-cwd-\(UUID().uuidString).txt")
        let result = await ShellCommandRunner.run(
            "touch \(marker.path)", workingDirectory: "/no/such/directory/at/all")

        #expect(!result.succeeded)
        #expect(result.standardError.contains("/no/such/directory/at/all"))
        #expect(!FileManager.default.fileExists(atPath: marker.path), "目录不存在时命令不该被执行")
    }

    @Test("工作目录接受波浪号，并在该目录里执行")
    func workingDirectoryExpandsTilde() async {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let result = await ShellCommandRunner.run("pwd", workingDirectory: "~")

        #expect(result.succeeded)
        #expect(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == home)
    }

    /// 用户亲自输入的场合要走交互式 shell
    ///
    /// zsh 只在交互式 shell 里 source `.zshrc`，而别名与 nvm / pyenv 那类 PATH 段都写在
    /// 那里 —— `-lc` 下它们全都不存在，用户在自己终端里好好的命令会退化成
    /// 「command not found」。命令串本身不参与拼装，所以这里只断言参数。
    @Test("交互式开关决定用 -ilc 还是 -lc")
    func shellArgumentsHonourTheInteractiveFlag() {
        #expect(
            ShellCommandRunner.shellArguments(command: "ll", loadingShellEnvironment: true) == ["-ilc", "ll"])
        #expect(
            ShellCommandRunner.shellArguments(command: "ll", loadingShellEnvironment: false) == ["-lc", "ll"])
    }
}
