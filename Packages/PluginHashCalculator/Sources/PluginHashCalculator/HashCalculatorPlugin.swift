// HashCalculatorPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 计算 MD5 / SHA1 / SHA256 / SHA512 摘要的插件
///
/// 参考 Fasty hash-calculator 布局：
/// 输入区 → 结果列表（自动计算）→ 空状态提示
@MainActor
public final class HashCalculatorPlugin: QuickPlugin, PluginViewProviding, PluginSettingsProviding {

    public static let id = "hash-calculator"
    public static let name = "Hash 计算器"
    public static let icon = "number.square.fill"
    public static let description = "实时计算文本数据的 MD5、SHA-1、SHA-256 与 SHA-512 校验散列值，支持大写切换与自动复制。"
    public static let triggerWords = ["hash", "哈希", "md5", "sha", "sha1", "sha256", "sha512"]

    public var isEnabled = true

    private let log = QuickLog.plugin(HashCalculatorPlugin.id)

    public init() {}

    /// 面板工作状态：主面板与分离窗口共享同一实例，分离时内容不丢
    private let buffer = TextBuffer()

    public func makeView() -> AnyView {
        AnyView(HashCalculatorView(buffer: buffer).prefillFromPluginContext(buffer))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(HashCalculatorSettingsView())
    }

    public func activate() {
        log.notice("插件已激活")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
