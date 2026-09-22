// Base64CodecPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// Base64 编解码插件
///
/// 参考 Fasty base64-codec 布局：
/// 工具栏（模式切换 + 操作按钮）→ 编辑区 → 状态栏
@MainActor
public final class Base64CodecPlugin: QuickPlugin {

    public static let id = "base64-codec"
    public static let name = "Base64 编解码"
    public static let icon = "lock.rectangle"
    public static let description = "普通文本与 Base64 互相转换，支持标准 RFC 4648 与 URL-Safe 编码格式。"
    public static let triggerWords = ["base64", "编码", "解码", "encode", "decode"]

    public var isEnabled = true

    private let log = QuickLog.plugin(Base64CodecPlugin.id)

    public init() {}

    public func searchItems(query: String) async -> [SearchableItem] {
        guard query.matchesAnyTrigger(Self.triggerWords) else { return [] }
        return [
            SearchableItem(
                id: "base64-codec.open",
                pluginID: Self.id,
                title: Self.name,
                subtitle: "Base64 编码和解码",
                icon: Self.icon,
                relevance: 0.7,
                action: { EventBus.shared.post(NavigateEvent(pluginID: Self.id)) }
            )
        ]
    }

    public func makeView() -> AnyView {
        AnyView(Base64CodecView())
    }

    public func activate() {
        log.notice("插件已激活")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
