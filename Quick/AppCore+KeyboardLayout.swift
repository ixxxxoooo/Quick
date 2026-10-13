// AppCore+KeyboardLayout.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Carbon.HIToolbox
import Foundation
import QuickCore
import QuickPlatform
import QuickUI
import SwiftUI

/// 键盘布局：面板打开期间强制切换输入法
///
/// 从 `AppCore.swift` 按职责拆出的扩展：状态仍然只属于 `AppCore`（唯一所有者），
/// 这里只放行为。拆文件是为了让每个文件能一次读完，不是为了拆出新的所有者。
extension AppCore {

    // MARK: - 键盘布局

    /// 面板打开时切到用户指定的键盘布局
    ///
    /// 中文输入法用户按 ⌥Space 时往往还停在拼音状态，输入的其实是拼音串 ——
    /// 强制切到 ABC 才能直接打命令。关闭面板时还原（见 restoreKeyboardLayout）。
    func applyForcedKeyboardLayout() {
        let configured = UserDefaults.standard.string(forKey: SettingsKey.paletteForceKeyboardLayout) ?? ""
        guard !configured.isEmpty else { return }

        let current = keyboardLayoutService.currentLayoutID()
        // 已经在目标布局上就不动：既省一次切换，也保证「还原」不会记错原值
        guard current != configured else { return }

        layoutBeforePanel = current
        if keyboardLayoutService.select(layoutID: configured) {
            log.notice("面板打开，键盘布局已切到 \(configured, privacy: .public)")
        } else {
            // 用户可能已经删掉了那个布局：留个 warning，不要静默
            log.warning("指定的键盘布局不存在，未切换：\(configured, privacy: .public)")
            layoutBeforePanel = nil
        }
    }

    /// 面板关闭时还原原来的键盘布局
    func restoreKeyboardLayout() {
        guard let previous = layoutBeforePanel else { return }
        layoutBeforePanel = nil
        if keyboardLayoutService.select(layoutID: previous) {
            log.debug("面板关闭，键盘布局已还原：\(previous, privacy: .public)")
        }
    }
}
