// HotKeyMigration.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// 把旧的五类热键键迁移成 `hotkey.command.<id>`
///
/// 只跑一次。迁移之后旧键删除，读取路径不再认识它们。
public enum HotKeyMigration {

    /// 迁移完成标记。改迁移规则时换一个新标记，不要复用这个
    public static let flag = "hotkey.migrated.command-id.v1"

    /// 把旧键抄到新键上
    ///
    /// - Parameter defaults: 偏好存储。测试传独立 suite
    public static func migrate(defaults: UserDefaults) {
        guard !defaults.bool(forKey: flag) else { return }

        let snapshot = defaults.dictionaryRepresentation()
        for (key, value) in snapshot {
            guard let data = value as? Data, let newKey = migratedKey(forLegacyKey: key) else { continue }
            if defaults.data(forKey: newKey) == nil {
                defaults.set(data, forKey: newKey)
            }
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: flag)
    }

    /// 旧键到新键。不认识的键返回 nil，调用方不要删
    public static func migratedKey(forLegacyKey key: String) -> String? {
        if key == "hotkey.togglePalette" {
            return HotKeyAction(commandID: CommandID.togglePalette).defaultsKey
        }
        if let id = suffix(of: key, prefix: "hotkey.plugin.") {
            return HotKeyAction(commandID: CommandID.openPlugin(id)).defaultsKey
        }
        if let id = suffix(of: key, prefix: "hotkey.systemAction.") {
            return HotKeyAction(commandID: CommandID.systemAction(id)).defaultsKey
        }
        if let id = suffix(of: key, prefix: "hotkey.app.") {
            return HotKeyAction(commandID: CommandID.launchApp(id)).defaultsKey
        }
        if let id = suffix(of: key, prefix: "hotkey.customCommand.") {
            return HotKeyAction(commandID: CommandID.shell(id)).defaultsKey
        }
        return nil
    }

    private static func suffix(of key: String, prefix: String) -> String? {
        guard key.hasPrefix(prefix) else { return nil }
        let rest = String(key.dropFirst(prefix.count))
        return rest.isEmpty ? nil : rest
    }
}
