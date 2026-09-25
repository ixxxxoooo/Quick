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
public final class ColorComparePlugin: QuickPlugin, PluginViewProviding, PluginSettingsProviding {

    public static let id = "color-compare"
    public static let name = "颜色工具"
    public static let icon = "paintpalette.fill"
    public static let description = "HEX、RGB、HSL 色彩格式解析互转与色板对比，支持色彩明暗微调与一键复制颜色代码。"
    public static let triggerWords = ["颜色", "色值", "对比度", "color", "contrast"]

    public var isEnabled = true

    private let log = QuickLog.plugin(ColorComparePlugin.id)

    public init() {}

    /// 面板工作状态：主面板与分离窗口共享同一实例，分离时内容不丢
    private let buffer = TextBuffer()

    public func makeView() -> AnyView {
        AnyView(ColorCompareView(buffer: buffer).prefillFromPluginContext(buffer))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(ColorCompareSettingsView())
    }

    public func activate() {
        log.notice("插件已激活")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
