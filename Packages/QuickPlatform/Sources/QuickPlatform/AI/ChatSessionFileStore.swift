// ChatSessionFileStore.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// AI 对话会话的磁盘存储：一个会话一个 JSON 文件
///
/// 一个会话一个文件而不是一整份：流式回复结束、改标题、置顶都只重写那一个会话，
/// 不会因为历史很长而每次落盘都变慢；单个文件损坏也只丢那一个会话。
///
/// 值类型、`Sendable`：IO 由调用方放到 `Task.detached` 里做，不新增 actor。
public struct ChatSessionFileStore: Sendable {

    public let directory: URL

    private static let log = QuickLog.logger("ai-chat")

    public init(directory: URL = ChatSessionFileStore.defaultDirectory()) {
        self.directory = directory
    }

    public static func defaultDirectory() -> URL {
        AppPaths.applicationSupport().appendingPathComponent("AIChats", isDirectory: true)
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// 读出全部会话；损坏的文件跳过并记日志，不影响其余会话
    public func loadAll() -> [ChatSession] {
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = Self.makeDecoder()
        return urls.filter { $0.pathExtension == "json" }.compactMap { url in
            do {
                return try decoder.decode(ChatSession.self, from: Data(contentsOf: url))
            } catch {
                Self.log.error(
                    "会话文件无法读取，已跳过：\(url.lastPathComponent, privacy: .public)")
                return nil
            }
        }
    }

    /// 原子写入一个会话
    public func save(_ session: ChatSession) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.makeEncoder().encode(session)
        try data.write(to: fileURL(for: session.id), options: .atomic)
    }

    public func delete(id: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
    }

    /// 清空全部历史
    public func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
