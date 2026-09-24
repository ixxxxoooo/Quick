// FileSearchService.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Foundation
import QuickCore

/// Spotlight 文件搜索服务
///
/// 用 `NSMetadataQuery` 走 macOS 自己的索引，因此不需要遍历磁盘，也不受目录深度影响。
/// **它属于宿主能力，不是插件**：文件搜索是面板的一种结果来源，不该被单独开关、
/// 也不该有自己的面板。
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
    private static let queryTimeout = Duration.seconds(2)

    private var query: NSMetadataQuery?

    /// 搜索完成的等待者
    private var searchContinuation: CheckedContinuation<[FileResult], Never>?

    private let defaults: UserDefaults

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
    /// - Returns: 已按设置过滤隐藏项并截断到上限的结果
    public func search(keyword: String) async -> [FileResult] {
        cancelPendingSearch()

        return await withCheckedContinuation { continuation in
            self.searchContinuation = continuation

            // 设置只在开始搜索时读一次：这一次查询的谓词与上限要相互一致
            let settings = self.configuredSettings

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
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(queryDidFinish(_:)),
                name: .NSMetadataQueryDidFinishGathering,
                object: metadataQuery
            )

            self.query = metadataQuery
            metadataQuery.start()

            Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.queryTimeout)
                self?.finishQuery()
            }
        }
    }

    @objc private func queryDidFinish(_ notification: Notification) {
        finishQuery()
    }

    private func finishQuery() {
        guard let query, let continuation = searchContinuation else { return }
        searchContinuation = nil
        query.stop()

        let settings = configuredSettings
        var collected: [FileResult] = []
        for index in 0..<min(query.resultCount, settings.maxResults) {
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

        NotificationCenter.default.removeObserver(
            self, name: .NSMetadataQueryDidFinishGathering, object: query)
        self.query = nil
        continuation.resume(returning: results)
    }

    /// 结束上一次还没完成的搜索
    ///
    /// 新输入到来时旧查询必须收尾：不收尾的话它的 continuation 永远不会 resume，
    /// 而且两个查询会同时往同一个 continuation 里写结果。
    private func cancelPendingSearch() {
        if let continuation = searchContinuation {
            searchContinuation = nil
            query?.stop()
            query = nil
            continuation.resume(returning: [])
        }
    }
}
