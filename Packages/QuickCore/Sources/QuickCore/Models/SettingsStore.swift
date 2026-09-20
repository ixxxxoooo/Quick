// SettingsStore.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 用户设置的持久化存储
///
/// 只负责读写，不含任何 UI，也不认识模块实例 —— 模块启用状态由组装层在注册时
/// 从这里读出来应用。这样「设置」和「模块」之间没有反向依赖。
///
/// 由 `AppCore` 持有并注入，**不是单例**。
@MainActor
public final class SettingsStore {

    private let defaults: UserDefaults
    private let log = QuickLog.app

    /// 初始化
    /// - Parameter defaults: 存储后端。测试传一个独立的 suite，避免污染真实偏好。
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - 模块开关

    /// 模块是否启用
    ///
    /// **未设置过一律视为启用**：新模块默认就该能用，用户没有主动关过它。
    /// 所以这里不能用 `bool(forKey:)` 直接读 —— 那会把「没设置过」读成 `false`。
    ///
    /// - Parameter moduleID: 模块 ID
    /// - Returns: 是否启用
    public func isModuleEnabled(_ moduleID: String) -> Bool {
        let key = SettingsKey.moduleEnabled(moduleID)
        guard defaults.object(forKey: key) != nil else { return true }
        return defaults.bool(forKey: key)
    }

    /// 设置模块启用状态
    /// - Parameters:
    ///   - moduleID: 模块 ID
    ///   - enabled: 是否启用
    public func setModuleEnabled(_ moduleID: String, enabled: Bool) {
        defaults.set(enabled, forKey: SettingsKey.moduleEnabled(moduleID))
        log.notice("模块 \(moduleID, privacy: .public) 已\(enabled ? "启用" : "停用", privacy: .public)")
    }

    /// 所有被显式停用过的模块 ID
    ///
    /// 用于排查「某个功能怎么没了」：日志里一眼能看到哪些模块是被用户关掉的。
    /// - Parameter candidateIDs: 当前存在的模块 ID
    /// - Returns: 其中被停用的那些
    public func disabledModuleIDs(among candidateIDs: [String]) -> [String] {
        candidateIDs.filter { !isModuleEnabled($0) }
    }

    // MARK: - 启动器与别名

    /// 获取存储的搜索范围（若未设置则返回默认值）
    public func searchScopes(defaultScopes: [String]) -> [String] {
        defaults.stringArray(forKey: SettingsKey.launcherSearchScopes) ?? defaultScopes
    }

    /// 设置搜索范围
    public func setSearchScopes(_ scopes: [String]) {
        defaults.set(scopes, forKey: SettingsKey.launcherSearchScopes)
    }

    /// 获取条目的别名
    public func alias(for key: String) -> String? {
        defaults.string(forKey: SettingsKey.alias(for: key))
    }

    /// 设置条目的别名
    public func setAlias(_ alias: String?, for key: String) {
        if let alias, !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            defaults.set(
                alias.trimmingCharacters(in: .whitespacesAndNewlines), forKey: SettingsKey.alias(for: key))
        } else {
            defaults.removeObject(forKey: SettingsKey.alias(for: key))
        }
    }

    /// 是否开启运行 Shell 命令兜底
    public var isRunShellFallbackEnabled: Bool {
        guard defaults.object(forKey: SettingsKey.launcherRunShellFallback) != nil else { return true }
        return defaults.bool(forKey: SettingsKey.launcherRunShellFallback)
    }

    public func setRunShellFallbackEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: SettingsKey.launcherRunShellFallback)
    }

    /// 自定义命令持久化数据
    public var customCommandsData: Data? {
        defaults.data(forKey: SettingsKey.launcherCustomCommands)
    }

    public func setCustomCommandsData(_ data: Data?) {
        if let data {
            defaults.set(data, forKey: SettingsKey.launcherCustomCommands)
        } else {
            defaults.removeObject(forKey: SettingsKey.launcherCustomCommands)
        }
    }
}
