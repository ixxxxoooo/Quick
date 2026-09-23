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

    /// 视图仍希望采样（面板隐藏时保留，以便再次显示时恢复）
    private var resumeWhenVisible = false

    /// 采样循环句柄；面板 `orderOut` 不会取消 SwiftUI `.task`，必须自己持有并取消
    private var samplingTask: Task<Void, Never>?

    /// 当前是否持有采样任务（测试与排查用）
    var isSampling: Bool { samplingTask != nil }

    /// 视图出现：标记需要采样并立刻开始
    func noteViewAppeared() {
        setResumeWhenVisible(true)
        startSamplingIfNeeded()
    }

    /// 视图消失（退回主搜索 / 分离后主面板 pop）：彻底停，且不再自动恢复
    func noteViewDisappeared() {
        setResumeWhenVisible(false)
        stopSampling()
    }

    /// 标记「视图仍挂着、面板再显示时应恢复采样」
    func setResumeWhenVisible(_ value: Bool) {
        resumeWhenVisible = value
    }

    /// 主面板显隐。隐藏一律停；显示时仅当视图仍挂着才恢复
    func notePanelVisibility(_ isVisible: Bool) {
        if isVisible {
            if resumeWhenVisible {
                startSamplingIfNeeded()
            }
        } else {
            stopSampling()
        }
    }

    /// 若尚未在采，启动采样循环
    func startSamplingIfNeeded(tick: (@MainActor () async -> Void)? = nil) {
        guard samplingTask == nil else { return }
        log.notice("开始进程采样，间隔 \(self.refreshInterval, privacy: .public) 秒")
        samplingTask = Task { [weak self] in
            await self?.runSamplingLoop(tick: tick)
        }
    }

    /// 取消采样循环
    func stopSampling() {
        guard samplingTask != nil else { return }
        samplingTask?.cancel()
        samplingTask = nil
        log.notice("已停止进程采样")
    }

    /// 按设置间隔连续刷新，直到任务被取消
    ///
    /// 测试可直接 `Task { await startSampling(tick:) }` 再 `cancel`；生产路径走
    /// `startSamplingIfNeeded` / `stopSampling`。
    func startSampling(tick: (@MainActor () async -> Void)? = nil) async {
        await runSamplingLoop(tick: tick)
    }

    private func runSamplingLoop(tick: (@MainActor () async -> Void)?) async {
        while !Task.isCancelled {
            if let tick {
                await tick()
            } else {
                await refresh()
            }
            try? await Task.sleep(for: .seconds(refreshInterval))
        }
    }

    func refresh() async {
        let mode = sortMode
        let records = await Task.detached(priority: .userInitiated) {
            KillProcessService.scan(sort: mode)
        }.value
        applyScanResults(records)
    }

    /// 把一次扫描结果落到状态
    ///
    /// internal 而不是 private：「永不列出宿主自身 PID」这条安全不变量要能在
    /// 不真的起 `ps` 的前提下被测试钉住。
    func applyScanResults(_ records: [ProcessRecord]) {
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

    /// `scan` 在 detached 任务里跑，不能碰 `@MainActor` 的 `KillProcessPlugin.id`
    nonisolated private static let scanLog = QuickLog.plugin("killprocess")

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
            scanLog.error(
                "进程列表扫描启动失败：\(error.localizedDescription, privacy: .public)"
            )
            return []
        }
        guard task.terminationStatus == 0 else {
            scanLog.error(
                "进程列表扫描失败：ps 退出码 \(task.terminationStatus, privacy: .public)"
            )
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return KillProcessListing.parse(output)
    }
}
