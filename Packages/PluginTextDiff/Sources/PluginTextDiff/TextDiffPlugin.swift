// TextDiffPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 文本对比工具
///
/// 参考 Fasty text-diff 布局：
/// 工具栏（互换/复制/清空 + 差异统计）→ 左右双栏编辑区 → 差异结果
@MainActor
public final class TextDiffPlugin: QuickPlugin, PluginViewProviding {

    public static let id = "text-diff"
    public static let name = "文本对比"
    public static let icon = "arrow.left.arrow.right"
    public static let description = "双栏文本内容直观比对，高亮新增、删除与变动字符，支持忽略空白字符与大小写差异。"
    public static let triggerWords = ["文本对比", "diff", "对比", "比较", "差异"]

    public static var functionCommands: [CommandDescriptor] {
        [
            CommandDescriptor(
                id: "text-diff.compare", pluginID: id, pluginName: name, title: "文本对比",
                subtitle: "左右两栏对比差异", keywords: ["文本对比", "对比文本", "diff"],
                icon: "arrow.left.arrow.right")
        ]
    }

    public var isEnabled = true

    private let log = QuickLog.plugin(TextDiffPlugin.id)

    public init() {}

    /// 面板工作状态：主面板与分离窗口共享同一实例，分离时内容不丢
    private let bufferA = TextBuffer()
    private let bufferB = TextBuffer()

    public func makeView() -> AnyView {
        AnyView(
            TextDiffView(bufferA: bufferA, bufferB: bufferB)
                .prefillFromPluginContext(bufferA))
    }

    public func activate() {
        log.notice("插件已激活")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
