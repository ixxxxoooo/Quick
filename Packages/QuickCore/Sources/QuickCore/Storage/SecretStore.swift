// SecretStore.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 机密读写抽象（API Key 等）
///
/// 生产走 Keychain；测试注入内存实现，避免污染本机钥匙串。
public protocol SecretStoring: Sendable {
    func get(_ account: String) throws -> String?
    func set(_ value: String, for account: String) throws
    func delete(_ account: String) throws
}

/// 进程内内存机密存储（仅测试）
public final class InMemorySecretStore: SecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    public init() {}

    public func get(_ account: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[account]
    }

    public func set(_ value: String, for account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values[account] = value
    }

    public func delete(_ account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: account)
    }
}
