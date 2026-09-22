// ColorComparePlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 颜色对比插件
///
/// 参考 Fasty color-compare 布局：
/// 输入区 → 颜色卡片网格（HEX/RGB/HSL）→ 亮度排序和对比度矩阵
@MainActor
public final class ColorComparePlugin: QuickPlugin {

    public static let id = "color-compare"
    public static let name = "颜色工具"
    public static let icon = "paintpalette"
    public static let description = "HEX、RGB、HSL 色彩格式解析互转与色板对比，支持色彩明暗微调与一键复制颜色代码。"
    public static let triggerWords = ["颜色", "color", "hex", "rgb", "色值", "取色"]

    public var isEnabled = true

    private let log = QuickLog.plugin(ColorComparePlugin.id)

    public init() {}

    public func searchItems(query: String) async -> [SearchableItem] {
        guard query.matchesAnyTrigger(Self.triggerWords) else { return [] }
        return [
            SearchableItem(
                id: "color-compare.open",
                pluginID: Self.id,
                title: Self.name,
                subtitle: "HEX/RGB 颜色识别、转换和亮度对比",
                icon: Self.icon,
                relevance: 0.7,
                action: { EventBus.shared.post(NavigateEvent(pluginID: Self.id)) }
            )
        ]
    }

    /// 面板工作状态：主面板与分离窗口共享同一实例，分离时内容不丢
    private let buffer = TextBuffer()

    public func makeView() -> AnyView {
        AnyView(ColorCompareView(buffer: buffer))
    }

    public func activate() {
        log.notice("插件已激活")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
