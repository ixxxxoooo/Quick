// LaunchGuardTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import QuickPlatform

@Suite("启动状态机")
struct LaunchStateTests {

    @Test("全新状态启动不算异常")
    func freshLaunchIsClean() {
        var state = LaunchState()
        let outcome = state.begin()
        #expect(!outcome.previousExitWasUnclean)
        #expect(outcome.quarantine.isEmpty)
        #expect(outcome.consecutiveUnclean == 0)
    }

    @Test("正常退出后再启动不算异常")
    func cleanExitThenLaunch() {
        var state = LaunchState()
        _ = state.begin()
        state.cleanExit()
        #expect(!state.begin().previousExitWasUnclean)
    }

    @Test("没退干净再启动：判为异常并累计")
    func uncleanExitIsDetected() {
        var state = LaunchState()
        _ = state.begin()
        let second = state.begin()
        #expect(second.previousExitWasUnclean)
        #expect(second.consecutiveUnclean == 1)
        #expect(!second.isCrashLoop)
        _ = state.begin()
        let fourth = state.begin()
        #expect(fourth.consecutiveUnclean == 3)
        #expect(fourth.isCrashLoop)
    }

    @Test("同一插件第一次死在启动里只记一笔，第二次才隔离")
    func quarantineNeedsTwoStrikes() {
        var state = LaunchState()
        _ = state.begin()
        state.willStart("clipboard")
        // —— 崩溃 ——
        let first = state.begin()
        #expect(first.quarantine.isEmpty)
        #expect(state.strikes["clipboard"] == 1)

        state.willStart("clipboard")
        // —— 又崩溃 ——
        let second = state.begin()
        #expect(second.quarantine == ["clipboard"])
        #expect(state.strikes["clipboard"] == nil, "隔离后清零，用户重新启用时给它一次新机会")
    }

    @Test("两次崩溃不是同一个插件：谁都不隔离")
    func differentCulpritsAreNotQuarantined() {
        var state = LaunchState()
        _ = state.begin()
        state.willStart("a")
        _ = state.begin()
        state.willStart("b")
        let outcome = state.begin()
        #expect(outcome.quarantine.isEmpty)
    }

    @Test("启动完成的插件不会被冤枉")
    func finishedStartIsNotBlamed() {
        var state = LaunchState()
        _ = state.begin()
        state.willStart("calendar")
        state.didStart()
        // 之后在别处崩溃
        let outcome = state.begin()
        #expect(outcome.previousExitWasUnclean)
        #expect(outcome.quarantine.isEmpty)
        #expect(state.strikes.isEmpty)
    }

    @Test("核心插件豁免：再多次也不隔离")
    func exemptPluginIsNeverQuarantined() {
        var state = LaunchState()
        _ = state.begin(exempt: ["launcher"])
        for _ in 0..<5 {
            state.willStart("launcher")
            let outcome = state.begin(exempt: ["launcher"])
            #expect(outcome.quarantine.isEmpty)
        }
    }

    @Test("正常退出清掉所有嫌疑")
    func cleanExitClearsStrikes() {
        var state = LaunchState()
        _ = state.begin()
        state.willStart("x")
        _ = state.begin()
        #expect(state.strikes["x"] == 1)
        state.cleanExit()
        #expect(state.strikes.isEmpty)
        #expect(state.consecutiveUnclean == 0)
    }
}

@MainActor
@Suite("启动状态持久化")
struct LaunchGuardPersistenceTests {

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("launch-\(UUID().uuidString).json")
    }

    @Test("崩溃发生在 guardStart 里：下一个进程能从磁盘读出嫌疑插件")
    func crashInsideGuardStartIsRemembered() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        // 进程 1：启动插件时「崩溃」——body 里不返回的效果用「从未调用 didStart」模拟
        let first = LaunchGuard(fileURL: url)
        _ = first.begin()
        var snapshotDuringStart: LaunchState?
        _ = first.guardStart("translator") {
            snapshotDuringStart = (try? Data(contentsOf: url))
                .flatMap { try? JSONDecoder().decode(LaunchState.self, from: $0) }
        }
        // 执行 body 期间磁盘上已经写着嫌疑
        #expect(snapshotDuringStart?.startingPluginID == "translator")
        #expect(snapshotDuringStart?.running == true)
    }

    @Test("状态文件损坏：当作全新状态，不阻止启动")
    func corruptFileIsTreatedAsFresh() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)
        let guardian = LaunchGuard(fileURL: url)
        let outcome = guardian.begin()
        #expect(!outcome.previousExitWasUnclean)
    }

    @Test("跨实例：未正常退出会被下一个实例识别")
    func uncleanAcrossInstances() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        _ = LaunchGuard(fileURL: url).begin()
        #expect(LaunchGuard(fileURL: url).begin().previousExitWasUnclean)

        let clean = LaunchGuard(fileURL: url)
        _ = clean.begin()
        clean.markCleanExit()
        #expect(!LaunchGuard(fileURL: url).begin().previousExitWasUnclean)
    }
}
