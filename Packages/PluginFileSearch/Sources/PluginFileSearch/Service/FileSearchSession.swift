// FileSearchSession.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit

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

    /// 搜索文件
    /// - Parameter query: 搜索关键词
    /// - Returns: 匹配的文件列表
    func search(query searchText: String) async -> [FileResult] {
        stopCurrentQuery()

        return await withCheckedContinuation { continuation in
            self.searchContinuation = continuation

            let metadataQuery = NSMetadataQuery()
            metadataQuery.searchScopes = [
                NSMetadataQueryLocalComputerScope
            ]
            metadataQuery.predicate = NSPredicate(
                format: "kMDItemDisplayName CONTAINS[cd] %@",
                searchText
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

        var results: [FileResult] = []
        for i in 0..<min(query.resultCount, 20) {
            guard let item = query.result(at: i) as? NSMetadataItem else { continue }
            guard let name = item.value(forAttribute: NSMetadataItemFSNameKey) as? String,
                let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
            else { continue }

            let size = item.value(forAttribute: NSMetadataItemFSSizeKey) as? Int64 ?? 0
            let modified = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date

            let icon = iconForFile(name)
            results.append(
                FileResult(
                    id: path,
                    name: name,
                    path: path,
                    icon: icon,
                    size: size,
                    modifiedDate: modified
                ))
        }

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

    /// 根据文件扩展名返回对应图标
    private func iconForFile(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext"
        case "jpg", "jpeg", "png", "gif", "webp", "heic": return "photo"
        case "mp4", "mov", "avi": return "film"
        case "mp3", "wav", "aac", "m4a": return "music.note"
        case "zip", "rar", "7z", "tar", "gz": return "archivebox"
        case "swift", "py", "js", "ts", "java", "c", "cpp", "rs":
            return "chevron.left.forwardslash.chevron.right"
        case "md", "txt": return "doc.text"
        case "html", "css": return "globe"
        default: return "doc"
        }
    }
}
