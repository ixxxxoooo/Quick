// FileSearchSession.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Foundation

/// Spotlight 文件搜索会话
///
/// 使用 NSMetadataQuery 进行文件搜索，
/// 利用 macOS Spotlight 索引实现快速搜索。
@MainActor
final class FileSearchSession {

    /// 搜索结果
    struct FileResult: Identifiable, Sendable {
        let id: String
        let name: String
        let path: String
        let icon: String
        let size: Int64
        let modifiedDate: Date?
    }

    /// Metadata Query 实例
    private var query: NSMetadataQuery?

    /// 搜索完成的 continuation
    private var searchContinuation: CheckedContinuation<[FileResult], Never>?

    /// 偏好存储。注入是为了让结果上限与两个开关能被测试固定住 —— 默认就是标准偏好
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 当前设置
    ///
    /// internal 而不是 private：查询本身要跑 Spotlight，测试里不允许，
    /// 设置因此只能在这里被断言。
    var configuredSettings: FileSearchSettings {
        FileSearchPreferences.current(defaults: defaults)
    }

    /// 搜索文件
    /// - Parameter query: 搜索关键词
    /// - Returns: 匹配的文件列表（已按设置过滤隐藏文件并截断到上限）
    func search(query searchText: String) async -> [FileResult] {
        stopCurrentQuery()

        return await withCheckedContinuation { continuation in
            self.searchContinuation = continuation

            // 设置只在开始搜索时读一次：这一次查询的谓词与上限要相互一致
            let settings = configuredSettings

            let metadataQuery = NSMetadataQuery()
            metadataQuery.searchScopes = [
                NSMetadataQueryLocalComputerScope
            ]
            // 谓词是纯映射（见 FileSearchQuery.predicate）：「搜索文件内容」打开时
            // 除了文件名还匹配 kMDItemTextContent
            let predicate = FileSearchQuery.predicate(
                for: searchText,
                includeContents: settings.includeContents
            )
            metadataQuery.predicate = NSPredicate(
                format: predicate.format,
                argumentArray: predicate.arguments
            )
            metadataQuery.sortDescriptors = [
                NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: true)
            ]
            metadataQuery.valueListAttributes = [
                NSMetadataItemFSSizeKey,
                NSMetadataItemFSContentChangeDateKey
            ]

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(queryDidFinish(_:)),
                name: .NSMetadataQueryDidFinishGathering,
                object: metadataQuery
            )

            self.query = metadataQuery
            metadataQuery.start()

            // 超时保护：2 秒后返回已有结果
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                self.finishQuery()
            }
        }
    }

    @objc private func queryDidFinish(_ notification: Notification) {
        finishQuery()
    }

    /// 完成查询，返回结果
    private func finishQuery() {
        guard let query, let continuation = searchContinuation else { return }
        searchContinuation = nil

        query.stop()

        let settings = configuredSettings

        // 上限决定「读多少条」：读进来之后再按隐藏文件过滤，两者都用同一个上限，
        // 于是「最多返回 N 条」对用户始终成立
        var collected: [FileResult] = []
        for i in 0..<min(query.resultCount, settings.maxResults) {
            guard let item = query.result(at: i) as? NSMetadataItem else { continue }
            guard let name = item.value(forAttribute: NSMetadataItemFSNameKey) as? String,
                let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
            else { continue }

            let size = item.value(forAttribute: NSMetadataItemFSSizeKey) as? Int64 ?? 0
            let modified = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date

            let icon = FileIconMapper.icon(forFileName: name)
            collected.append(
                FileResult(
                    id: path,
                    name: name,
                    path: path,
                    icon: icon,
                    size: size,
                    modifiedDate: modified
                ))
        }

        // 过滤与截断是纯逻辑（见 FileSearchFiltering）：隐藏文件开关与结果上限都在这里生效
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

    /// 停止当前查询
    private func stopCurrentQuery() {
        if let continuation = searchContinuation {
            continuation.resume(returning: [])
            searchContinuation = nil
        }
        query?.stop()
        query = nil
    }
}
