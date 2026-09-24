// URLCodecPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// URL 百分号编码和解码插件
///
/// 参考 Fasty url-codec 布局：
/// 工具栏（模式切换 + 操作按钮）→ 编辑区 → 状态栏
@MainActor
public final class URLCodecPlugin: QuickPlugin, PluginViewProviding {

    public static let id = "url-codec"
    public static let name = "URL 编解码"
    public static let icon = "link.circle.fill"
    public static let description = "URL 百分号编码与解码工具，支持整条链接保留结构编码或纯参数组件编码。"
    /// 通用词「编码 / 解码 / encode / decode」归 Base64 插件，这里只保留带 URL 限定的词，
    /// 否则两个插件会在同一条查询上撞车
    public static let triggerWords = [
        "URL 编解码", "url", "url编码", "url解码", "网址编码", "网址解码", "urlencode", "urldecode"
    ]

    public static var functionCommands: [CommandDescriptor] {
        [
            CommandDescriptor(
                id: "url-codec.encode", pluginID: id, pluginName: name, title: "URL 编码",
                subtitle: "把文本编码为百分号形式", keywords: ["urlencode", "url编码"], icon: "link"),
            CommandDescriptor(
                id: "url-codec.decode", pluginID: id, pluginName: name, title: "URL 解码",
                subtitle: "把百分号编码还原为文本", keywords: ["urldecode", "url解码"],
                icon: "arrow.uturn.left")
        ]
    }

    public var isEnabled = true

    private let log = QuickLog.plugin(URLCodecPlugin.id)

    public init() {}

    /// 面板工作状态：主面板与分离窗口共享同一实例，分离时内容不丢
    private let buffer = TextBuffer()

    public func makeView() -> AnyView {
        AnyView(URLCodecView(buffer: buffer).prefillFromPluginContext(buffer))
    }

    public func activate() {
        log.notice("插件已激活")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
