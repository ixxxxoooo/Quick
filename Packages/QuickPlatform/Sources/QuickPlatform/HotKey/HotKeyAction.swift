// HotKeyAction.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// 一条全局快捷键绑定的目标
///
/// 以前按「唤出面板 / 应用 / 系统操作 / 终端命令 / 整个插件」分成五种。
/// 现在一律指向命令 id，热键和搜索执行的是同一条命令。
public struct HotKeyAction: Hashable, Sendable {

    /// 命令 id，对应 `CommandID`
    public let commandID: String

    /// UserDefaults 键。旧的 `hotkey.togglePalette` 等只在迁移时读一次
    public var defaultsKey: String { "hotkey.command.\(commandID)" }

    /// 用命令 id 构建
    public init(commandID: String) {
        self.commandID = commandID
    }

    /// 唤出主面板
    public static let togglePalette = HotKeyAction(commandID: CommandID.togglePalette)

    /// 持久化键前缀，用来扫出用户绑过的全部命令
    public static let commandKeyPrefix = "hotkey.command."
}
