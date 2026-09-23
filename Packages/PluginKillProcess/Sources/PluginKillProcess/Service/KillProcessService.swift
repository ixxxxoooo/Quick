// KillProcessService.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// 进程列表刷新与结束
@MainActor
@Observable
final class KillProcessService {

    private(set) var processes: [ProcessRecord] = []
    private(set) var sortMode: KillProcessSortMode = KillProcessPreferences.defaultSort

    private let defaults: UserDefaults
    private let log = QuickLog.plugin(KillProcessPlugin.id)
    private let selfPID = ProcessInfo.processInfo.processIdentifier

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.sortMode = KillProcessPreferences.configuredSort(defaults: defaults)
    }

    var refreshInterval: Int {
        KillProcessPreferences.configuredInterval(defaults: defaults)
    }

    func setSortMode(_ mode: KillProcessSortMode) {
        sortMode = mode
        defaults.set(mode.rawValue, forKey: PluginSettingKey.KillProcess.sortMode)
    }

    /// 按设置间隔连续刷新，直到取消
    func startSampling() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(refreshInterval))
        }
    }

    func refresh() async {
        let mode = sortMode
        let records = await Task.detached(priority: .userInitiated) {
            KillProcessService.scan(sort: mode)
        }.value
        // 永远不展示自己，避免误杀宿主
        processes = records.filter { $0.id != selfPID }
    }

    /// 结束进程
    /// - Parameters:
    ///   - record: 目标进程
    ///   - force: `true` 发 SIGKILL，否则 SIGTERM
    /// - Returns: 是否成功发出信号
    @discardableResult
    func kill(_ record: ProcessRecord, force: Bool) -> Bool {
        let signal = force ? SIGKILL : SIGTERM
        let result = Darwin.kill(record.id, signal)
        if result == 0 {
            log.notice(
                "已\(force ? "强制" : "")结束进程 \(record.name, privacy: .public) (PID \(record.id))"
            )
            processes.removeAll { $0.id == record.id }
            EventBus.shared.post(
                ShowHUDEvent(
                    message: "已\(force ? "强制" : "")结束 \(record.name)",
                    tone: .success
                )
            )
            return true
        }

        let errnoValue = errno
        log.error(
            "结束进程失败 PID \(record.id)：errno=\(errnoValue)"
        )
        EventBus.shared.post(
            ShowHUDEvent(message: "无法结束 \(record.name)", tone: .danger)
        )
        return false
    }

    nonisolated private static func scan(sort: KillProcessSortMode) -> [ProcessRecord] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: KillProcessListing.commandPath)
        task.arguments = KillProcessListing.arguments(sort: sort)
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return KillProcessListing.parse(output)
    }
}
