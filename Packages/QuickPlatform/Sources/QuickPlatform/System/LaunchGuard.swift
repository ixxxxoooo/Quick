// LaunchGuard.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// 启动状态机（纯值类型，不碰磁盘与时钟，可独立测）
///
/// 回答一个问题：**上次是不是没退干净，如果是，死在谁手上？**
///
/// - 启动时把 `running` 置位，正常退出时清掉。下次启动若发现 `running` 仍为真，
///   说明上次是崩溃 / 被强杀。
/// - 启动期间每个插件的实例化与 `activate()` 之前先记下 `startingPluginID`，
///   做完再清掉。崩溃时它还留在文件里，就指出了「死在哪个插件的启动里」。
/// - **同一个插件连续两次死在启动里才隔离它**（`strikeLimit`）。只死一次可能是别的线程
///   刚好在那个窗口里崩了，贸然停用用户的功能比多崩一次更糟。
public struct LaunchState: Codable, Equatable, Sendable {

    /// 同一插件累计多少次死在启动里就隔离
    public static let strikeLimit = 2

    /// 连续多少次异常退出算「崩溃循环」，用于提示用户
    public static let crashLoopThreshold = 3

    /// 上次启动之后是否还没有正常退出
    public var running = false
    /// 崩溃时正在启动的插件
    public var startingPluginID: String?
    /// 各插件死在启动里的次数
    public var strikes: [String: Int] = [:]
    /// 连续异常退出次数；一次正常退出就清零
    public var consecutiveUnclean = 0

    public init() {}

    /// 一次启动的判定结果
    public struct Outcome: Equatable, Sendable {
        /// 上次是否异常退出
        public let previousExitWasUnclean: Bool
        /// 本次启动应当自动停用的插件
        public let quarantine: [String]
        /// 连续异常退出次数（含上次）
        public let consecutiveUnclean: Int

        /// 是否已经是崩溃循环
        public var isCrashLoop: Bool { consecutiveUnclean >= LaunchState.crashLoopThreshold }
    }

    /// 记录一次启动
    ///
    /// - Parameter exempt: 不允许被隔离的插件（核心插件：隔离它等于把 Quick 变成空壳）
    public mutating func begin(exempt: Set<String> = []) -> Outcome {
        let wasUnclean = running
        var quarantine: [String] = []

        if wasUnclean {
            consecutiveUnclean += 1
            if let culprit = startingPluginID, !exempt.contains(culprit) {
                strikes[culprit, default: 0] += 1
                if strikes[culprit, default: 0] >= Self.strikeLimit {
                    quarantine.append(culprit)
                    strikes[culprit] = nil
                }
            }
        }

        running = true
        startingPluginID = nil
        return Outcome(
            previousExitWasUnclean: wasUnclean, quarantine: quarantine,
            consecutiveUnclean: consecutiveUnclean)
    }

    /// 某个插件即将开始启动
    public mutating func willStart(_ pluginID: String) { startingPluginID = pluginID }

    /// 当前插件启动完成
    public mutating func didStart() { startingPluginID = nil }

    /// 正常退出：把「崩溃」相关的一切清零
    public mutating func cleanExit() {
        running = false
        startingPluginID = nil
        strikes = [:]
        consecutiveUnclean = 0
    }
}

/// 启动状态的持久化外壳
///
/// 状态存在一个小 JSON 文件里。**读不出来就当全新状态**，绝不因此阻止启动 ——
/// 崩溃保护自己不能成为新的崩溃源。写失败只记日志。
@MainActor
public final class LaunchGuard {

    private let fileURL: URL
    private let log = QuickLog.app
    private(set) var state: LaunchState

    /// - Parameter fileURL: 状态文件位置；测试传临时目录
    public init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
            let loaded = try? JSONDecoder().decode(LaunchState.self, from: data)
        {
            state = loaded
        } else {
            state = LaunchState()
        }
    }

    /// 记录本次启动并返回判定
    public func begin(exempt: Set<String> = []) -> LaunchState.Outcome {
        let outcome = state.begin(exempt: exempt)
        persist()
        if outcome.previousExitWasUnclean {
            log.error(
                "上次异常退出（连续 \(outcome.consecutiveUnclean, privacy: .public) 次），隔离插件：\(outcome.quarantine.joined(separator: ","), privacy: .public)"
            )
        }
        return outcome
    }

    /// 在 `body` 执行期间把 `pluginID` 标记为「正在启动」
    ///
    /// 先落盘再执行：崩溃发生在 `body` 里时，磁盘上已经有它的名字。
    public func guardStart<T>(_ pluginID: String, _ body: () -> T) -> T {
        state.willStart(pluginID)
        persist()
        let result = body()
        state.didStart()
        persist()
        return result
    }

    /// 正常退出
    public func markCleanExit() {
        state.cleanExit()
        persist()
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("启动状态写入失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}
