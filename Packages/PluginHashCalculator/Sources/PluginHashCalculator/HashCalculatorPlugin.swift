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
public final class HashCalculatorPlugin: QuickPlugin, PluginViewProviding {

    public static let id = "hash-calculator"
    public static let name = "Hash 计算器"
    public static let icon = "number.square.fill"
    public static let description = "实时计算文本数据的 MD5、SHA-1、SHA-256 与 SHA-512 校验散列值，支持大写切换与自动复制。"
    public static let triggerWords = ["Hash 计算器", "hash", "哈希", "md5", "sha"]

    public static var functionCommands: [CommandDescriptor] {
        [
            CommandDescriptor(
                id: "hash-calculator.md5", pluginID: id, pluginName: name, title: "MD5",
                subtitle: "计算 MD5 散列", keywords: ["md5", "md5计算"], icon: "number"),
            CommandDescriptor(
                id: "hash-calculator.sha1", pluginID: id, pluginName: name, title: "SHA-1",
                subtitle: "计算 SHA-1 散列", keywords: ["sha1", "sha1计算"], icon: "number.square"),
            CommandDescriptor(
                id: "hash-calculator.sha256", pluginID: id, pluginName: name, title: "SHA-256",
                subtitle: "计算 SHA-256 散列", keywords: ["sha256", "sha256计算"],
                icon: "number.square.fill"),
            CommandDescriptor(
                id: "hash-calculator.sha512", pluginID: id, pluginName: name, title: "SHA-512",
                subtitle: "计算 SHA-512 散列", keywords: ["sha512", "sha512计算"],
                icon: "number.circle")
        ]
    }

    public var isEnabled = true

    private let log = QuickLog.plugin(HashCalculatorPlugin.id)

    public init() {}

    /// 面板工作状态：主面板与分离窗口共享同一实例，分离时内容不丢
    private let buffer = TextBuffer()

    public func makeView() -> AnyView {
        AnyView(HashCalculatorView(buffer: buffer).prefillFromPluginContext(buffer))
    }

    public func activate() {
        log.notice("插件已激活")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
