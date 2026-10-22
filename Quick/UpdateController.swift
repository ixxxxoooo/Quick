// UpdateController.swift
// Quick — 原生 macOS 效率启动器
// @author ixxxxoooo

import AppKit
import QuickCore
import QuickPlatform

/// 自动更新的交互层：启动时每天静默检查一次，菜单可手动检查
@MainActor
final class UpdateController {

    private static let lastCheckKey = "quick.update.lastCheck"
    private let service = UpdateService()
    private let log = QuickLog.app
    private var isBusy = false

    /// 启动时调用：距上次检查不足 24 小时则跳过；有更新才弹窗
    func checkInBackground() {
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        guard Date().timeIntervalSince1970 - last > 86_400 else { return }
        Task { await check(userInitiated: false) }
    }

    /// 手动检查更新（菜单项）
    func checkNow() {
        Task { await check(userInitiated: true) }
    }

    /// 检查并按需弹窗
    /// - Parameter userInitiated: 手动触发时，「已是最新」和失败也会提示
    private func check(userInitiated: Bool) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let release = try await service.checkForUpdate()
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
            guard let release else {
                if userInitiated { alert("已是最新版本", "当前版本 \(UpdateService.currentVersion)。") }
                return
            }
            guard confirm(release) else { return }
            try await service.prepareInstall(release)
            NSApp.terminate(nil)
        } catch {
            log.error("更新失败：\(error.localizedDescription, privacy: .public)")
            if userInitiated { alert("更新失败", error.localizedDescription) }
        }
    }

    /// 询问是否安装
    private func confirm(_ release: UpdateRelease) -> Bool {
        let alert = NSAlert()
        alert.messageText = "发现新版本 \(release.version)"
        alert.informativeText = "当前版本 \(UpdateService.currentVersion)。更新后 Quick 会自动重启。"
        alert.addButton(withTitle: "立即更新")
        alert.addButton(withTitle: "稍后")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }
}
