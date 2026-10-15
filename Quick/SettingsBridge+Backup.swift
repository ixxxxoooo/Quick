// SettingsBridge+Backup.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import QuickPlatform
import QuickUI

// MARK: - 设置备份与恢复

extension SettingsBridge {

    /// 当前应用的偏好域名
    private var preferencesDomain: String {
        Bundle.main.bundleIdentifier ?? AppPaths.rootFolderName
    }

    func exportSettings() throws -> Data {
        let domain = UserDefaults.standard.persistentDomain(forName: preferencesDomain) ?? [:]
        let data = try SettingsBackup.export(domain: domain, exportedAt: Date())
        QuickLog.app.notice("已导出设置：\(domain.count, privacy: .public) 个键（过滤前）")
        return data
    }

    func importSettings(_ data: Data) throws -> SettingsImportSummary {
        // 先解析再动手：解析失败时一个键都不会写
        let plan = try SettingsBackup.parse(data)

        // 导入是覆盖式的，写之前先把现有设置另存一份，导入错了能救回来
        let safety = AppPaths.applicationSupport().appendingPathComponent("settings-before-import.plist")
        do {
            let current = UserDefaults.standard.persistentDomain(forName: preferencesDomain) ?? [:]
            try SettingsBackup.export(domain: current, exportedAt: Date()).write(to: safety, options: .atomic)
        } catch {
            // 保险副本写不出来就不要继续覆盖用户设置
            QuickLog.app.error("导入前备份当前设置失败，已中止导入：\(error.localizedDescription, privacy: .public)")
            throw error
        }

        for (key, value) in plan.values {
            UserDefaults.standard.set(value.anyValue, forKey: key)
        }
        QuickLog.app.notice(
            "已导入设置：写入 \(plan.values.count, privacy: .public) 项，丢弃 \(plan.skipped, privacy: .public) 项"
        )
        return SettingsImportSummary(applied: plan.values.count, skipped: plan.skipped)
    }

    func restartApplication() {
        core.statusItemController.restartApplication()
    }
}
