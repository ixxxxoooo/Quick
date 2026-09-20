// SnippetStore.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickPlatform

/// 文本片段存储
@MainActor
final class SnippetStore: Observable {

    private(set) var snippets: [Snippet] = []

    private var storageURL: URL {
        AppPaths.moduleData("snippets").appendingPathComponent("snippets.json")
    }

    /// 搜索片段
    func search(_ query: String) -> [Snippet] {
        guard !query.isEmpty else { return snippets }
        let lower = query.lowercased()
        return snippets.filter {
            $0.title.lowercased().contains(lower) ||
            ($0.keyword?.lowercased().contains(lower) ?? false) ||
            $0.content.lowercased().contains(lower)
        }
    }

    /// 添加片段
    func add(_ snippet: Snippet) {
        snippets.insert(snippet, at: 0)
        save()
    }

    /// 更新片段
    func update(_ snippet: Snippet) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        snippets[index] = snippet
        save()
    }

    /// 删除片段
    func remove(_ id: UUID) {
        snippets.removeAll { $0.id == id }
        save()
    }

    // MARK: - 持久化

    func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([Snippet].self, from: data)
        else { return }
        snippets = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(snippets) else { return }
        try? data.write(to: storageURL)
    }
}
