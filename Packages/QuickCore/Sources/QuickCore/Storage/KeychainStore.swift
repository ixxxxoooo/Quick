// KeychainStore.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Security

/// Keychain 机密存储
///
/// 服务名跟 bundle id 走，Debug（`.dev`）与 Release 互不覆盖。
public struct KeychainStore: SecretStoring, Sendable {

    public let service: String

    public init(service: String = KeychainStore.defaultService) {
        self.service = service
    }

    /// 默认服务名：`<bundleid>.secrets`
    public static var defaultService: String {
        let bundle = Bundle.main.bundleIdentifier ?? "com.ixxxxoooo.quick"
        return "\(bundle).secrets"
    }

    public static let shared = KeychainStore()

    public func get(_ account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func set(_ value: String, for account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let update: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        } else if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        } else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func delete(_ account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

/// Keychain 操作失败
public enum KeychainError: Error, Sendable {
    case unexpectedStatus(OSStatus)
}
