// SecretStore.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Synchronization

/// 机密读写抽象（API Key 等）
///
/// 生产走 Keychain；测试注入内存实现，避免污染本机钥匙串。
public protocol SecretStoring: Sendable {
    func get(_ account: String) throws -> String?
    func set(_ value: String, for account: String) throws
    func delete(_ account: String) throws
}

/// 进程内内存机密存储（仅测试）
///
/// 用 `Mutex` 而不是 `NSLock` + `@unchecked Sendable`：`Mutex` 自身是 `Sendable`，
/// 编译器因此能自己验证这个类型的安全，不需要任何断言。本项目只允许 Carbon
/// C 回调跳板用 `@unchecked Sendable`。
public final class InMemorySecretStore: SecretStoring {
    private let values = Mutex<[String: String]>([:])

    public init() {}

    public func get(_ account: String) throws -> String? {
        values.withLock { $0[account] }
    }

    public func set(_ value: String, for account: String) throws {
        values.withLock { $0[account] = value }
    }

    public func delete(_ account: String) throws {
        // `removeValue` 返回被删掉的值，这里不关心，但必须显式丢弃
        _ = values.withLock { $0.removeValue(forKey: account) }
    }
}
