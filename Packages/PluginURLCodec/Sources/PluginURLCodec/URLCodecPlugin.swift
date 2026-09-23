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
public final class URLCodecPlugin: QuickPlugin {

    public static let id = "url-codec"
    public static let name = "URL 编解码"
    public static let icon = "link.circle.fill"
    public static let description = "URL 百分号编码与解码工具，支持整条链接保留结构编码或纯参数组件编码。"
    public static let triggerWords = ["URL 编解码", "url", "编码", "解码", "encode", "decode"]

    public var isEnabled = true

    private let log = QuickLog.plugin(URLCodecPlugin.id)

    public init() {}

    public func searchItems(query: String) async -> [SearchableItem] {
        guard query.matchesAnyTrigger(Self.triggerWords) else { return [] }
        return [
            SearchableItem(
                id: "url-codec.open",
                pluginID: Self.id,
                title: Self.name,
                subtitle: "URL 百分号编码和解码",
                icon: Self.icon,
                relevance: 0.7,
                action: { EventBus.shared.post(NavigateEvent(pluginID: Self.id)) }
            )
        ]
    }

    /// 面板工作状态：主面板与分离窗口共享同一实例，分离时内容不丢
    private let buffer = TextBuffer()

    public func makeView() -> AnyView {
        AnyView(URLCodecView(buffer: buffer))
    }

    public func activate() {
        log.notice("插件已激活")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
