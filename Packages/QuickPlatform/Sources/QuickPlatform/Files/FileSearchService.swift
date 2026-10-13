// FileSearchService.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Foundation
import QuickCore

/// Spotlight 文件搜索服务
///
/// 用 `NSMetadataQuery` 走 macOS 自己的索引，因此不需要遍历磁盘，也不受目录深度影响。
/// **它属于宿主能力，不是插件**：文件搜索是面板的一种结果来源，不该有自己的面板。
///
/// ### 生命周期
/// 每次 `search` 都开一个独立的 `Session`，由 `SearchSessionGate` 发令牌：
/// - 新搜索开始 → 上一个会话立即作废（摘掉通知观察者、停掉查询、以空结果收尾）；
/// - 完成通知、超时、任务取消都先核对令牌，不是当前这一次就丢弃 —— 这样旧查询的
///   「完成」不可能把新查询提前收尾；
/// - 调用方的任务被取消（用户又敲了一个字）时，会话随之收尾，不会空等到超时。
@MainActor
public final class FileSearchService {

    /// 一条匹配的文件
    public struct FileResult: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let path: String
        public let icon: String
        public let size: Int64
        public let modifiedDate: Date?

        public init(id: String, name: String, path: String, icon: String, size: Int64, modifiedDate: Date?) {
            self.id = id
            self.name = name
            self.path = path
            self.icon = icon
            self.size = size
            self.modifiedDate = modifiedDate
        }
    }

    /// 查询超时
    ///
    /// Spotlight 有时会长时间不回报完成通知（索引正在重建、或磁盘完全没建过索引）。
    /// 超时之后返回已经拿到的部分，比让用户对着空面板等下去好。
    public static let queryTimeout = Duration.seconds(2)

    /// 过滤隐藏文件之前，最多向 Spotlight 多要几倍于上限的候选
    ///
    /// 先截断再过滤会让「忽略隐藏文件」把结果削到远低于上限；多取一些候选再过滤、
    /// 再截断，才能尽量凑满用户设定的条数。
    private static let candidateMultiplier = 5

    /// 候选总数的硬上限，防止一个很泛的关键词把主线程拖在拷贝结果上
    private static let candidateCeiling = 1000

    /// 一次搜索会话的全部可变状态
    private struct Session {
        let token: SearchSessionGate.Token
        let query: NSMetadataQuery
        let observer: NSObjectProtocol
        let timeout: Task<Void, Never>
        let continuation: CheckedContinuation<[FileResult], Never>
    }

    private var gate = SearchSessionGate()
    private var session: Session?

    private let defaults: UserDefaults
    private let log = QuickLog.app

    /// 构造一个搜索服务
    /// - Parameter defaults: 偏好域；测试传自己的 suite
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 本次查询生效的设置
    ///
    /// 公开是因为查询本身要跑 Spotlight，测试里不允许：设置只能在这里被断言。
    public var configuredSettings: FileSearchSettings {
        FileSearchPreferences.current(defaults: defaults)
    }

    /// 按关键词搜索文件
    ///
    /// 调用前应先经 `FileSearchQuery.keyword(in:)` 剥掉触发前缀。
    ///
    /// - Parameter keyword: 已经剥掉前缀的关键词
    /// - Returns: 已按设置过滤隐藏项并截断到上限的结果；被新搜索顶掉或任务被取消时为空
    public func search(keyword: String) async -> [FileResult] {
        // 先让上一个会话收尾，再领新令牌
        endSession(returning: [])
        let token = gate.begin()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.startSession(token: token, keyword: keyword, continuation: continuation)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel(token)
            }
        }
    }

    // MARK: - 会话

    private func startSession(
        token: SearchSessionGate.Token,
        keyword: String,
        continuation: CheckedContinuation<[FileResult], Never>
    ) {
        // 设置只在开始搜索时读一次：这一次查询的谓词与上限要相互一致
        let settings = configuredSettings

        let metadataQuery = NSMetadataQuery()
        metadataQuery.searchScopes = [NSMetadataQueryLocalComputerScope]
        let predicate = FileSearchQuery.predicate(
            for: keyword, includeContents: settings.includeContents)
        metadataQuery.predicate = NSPredicate(
            format: predicate.format, argumentArray: predicate.arguments)
        metadataQuery.sortDescriptors = [
            NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: true)
        ]
        metadataQuery.valueListAttributes = [
            NSMetadataItemFSSizeKey, NSMetadataItemFSContentChangeDateKey
        ]

        // `object:` 限定只收这个查询自己的通知；回调里再核一次令牌，双保险
        let observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: metadataQuery,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.complete(token, collectingResults: true)
            }
        }

        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.queryTimeout)
            guard !Task.isCancelled else { return }
            self?.complete(token, collectingResults: true)
        }

        session = Session(
            token: token, query: metadataQuery, observer: observer, timeout: timeout,
            continuation: continuation)
        metadataQuery.start()
    }

    /// 完成（或超时）：只有令牌仍是当前这一次才生效
    private func complete(_ token: SearchSessionGate.Token, collectingResults: Bool) {
        guard gate.isCurrent(token), let active = session, active.token == token else { return }
        let results = collectingResults ? collect(from: active.query) : []
        _ = gate.finish(token)
        tearDown(active)
        session = nil
        active.continuation.resume(returning: results)
    }

    /// 调用方任务被取消
    private func cancel(_ token: SearchSessionGate.Token) {
        complete(token, collectingResults: false)
    }

    /// 无条件结束当前会话（新搜索到来时用）
    private func endSession(returning results: [FileResult]) {
        guard let active = session else { return }
        _ = gate.finish(active.token)
        tearDown(active)
        session = nil
        active.continuation.resume(returning: results)
    }

    /// 摘掉观察者、停掉计时与查询 —— 任何收尾路径都必须走这一步
    private func tearDown(_ active: Session) {
        NotificationCenter.default.removeObserver(active.observer)
        active.timeout.cancel()
        active.query.stop()
    }

    // MARK: - 结果

    private func collect(from query: NSMetadataQuery) -> [FileResult] {
        let settings = configuredSettings
        let candidateLimit = min(
            query.resultCount,
            min(settings.maxResults * Self.candidateMultiplier, Self.candidateCeiling))

        var collected: [FileResult] = []
        collected.reserveCapacity(candidateLimit)
        for index in 0..<candidateLimit {
            guard let item = query.result(at: index) as? NSMetadataItem,
                let name = item.value(forAttribute: NSMetadataItemFSNameKey) as? String,
                let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
            else { continue }

            collected.append(
                FileResult(
                    id: path,
                    name: name,
                    path: path,
                    icon: FileIconMapper.icon(forFileName: name),
                    size: item.value(forAttribute: NSMetadataItemFSSizeKey) as? Int64 ?? 0,
                    modifiedDate: item.value(forAttribute: NSMetadataItemFSContentChangeDateKey)
                        as? Date
                ))
        }

        // 过滤与截断是纯逻辑（见 FileSearchFiltering）：隐藏文件开关与上限都在这里生效
        let results = FileSearchFiltering.applying(
            ignoringHidden: settings.ignoreHidden,
            limit: settings.maxResults,
            to: collected,
            path: { $0.path }
        )
        log.debug(
            "文件搜索收集 \(query.resultCount, privacy: .public) 条原始结果，过滤后 \(results.count, privacy: .public) 条")
        return results
    }
}
