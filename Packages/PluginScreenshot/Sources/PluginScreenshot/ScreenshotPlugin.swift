// ScreenshotPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 截图工具插件
///
/// 屏幕截图 + 简单标注编辑器。
@MainActor
public final class ScreenshotPlugin: QuickPlugin {

    public static let id = "screenshot"
    public static let name = "截图工具"
    public static let icon = "camera"
    public static let description = "调用系统级截屏能力，支持全屏、交互式区域选区与独立窗口捕获，可选择存入剪贴板或桌面。"
    /// 区域截图的关键字，对齐 Fasty `plugins/screenshot` 的 area / capture。和全屏那组不能有相同的词
    public static let areaKeywords = ["截图工具", "截图", "截屏", "screenshot", "区域截图", "框选"]
    /// 全屏截图的关键字。`全屏` / `fullscreen` 是不与区域重叠的别名
    public static let fullKeywords = ["全屏截图", "全屏", "fullscreen"]
    public static let triggerWords = areaKeywords + fullKeywords

    public var isEnabled = true

    private let log = QuickLog.plugin(ScreenshotPlugin.id)

    private let capture = ScreenCapture()

    public init() {}

    public static var commands: [CommandDescriptor] {
        [
            CommandDescriptor(
                id: "screenshot.area",
                pluginID: id,
                pluginName: name,
                title: "区域截图",
                subtitle: "截取屏幕指定区域",
                keywords: areaKeywords,
                icon: "rectangle.dashed",
                showsWhenQueryEmpty: true
            ),
            CommandDescriptor(
                id: "screenshot.full",
                pluginID: id,
                pluginName: name,
                title: "全屏截图",
                subtitle: "截取整个屏幕",
                keywords: fullKeywords,
                icon: "rectangle.on.rectangle"
            )
        ]
    }

    public func perform(commandID: String) {
        switch commandID {
        case "screenshot.area":
            Task { await captureArea() }
        case "screenshot.full":
            Task { await captureFullScreen() }
        default:
            break
        }
    }

    public func searchItems(query: String) async -> [SearchableItem] {
        let area = Self.matches(Self.areaKeywords, query: query)
        let full = Self.matches(Self.fullKeywords, query: query)
        guard area || full else { return [] }

        var items: [SearchableItem] = []
        if area {
            items.append(
                SearchableItem(
                    id: "screenshot.area",
                    pluginID: Self.id,
                    title: "区域截图",
                    subtitle: "截取屏幕指定区域",
                    icon: "rectangle.dashed",
                    relevance: 0.8,
                    action: { [weak self] in
                        Task { await self?.captureArea() }
                    }
                )
            )
        }
        if full {
            items.append(
                SearchableItem(
                    id: "screenshot.full",
                    pluginID: Self.id,
                    title: "全屏截图",
                    subtitle: "截取整个屏幕",
                    icon: "rectangle.on.rectangle",
                    relevance: 0.7,
                    action: { [weak self] in
                        Task { await self?.captureFullScreen() }
                    }
                )
            )
        }
        return items
    }

    /// 查询包含关键字，或关键字包含查询。这样输入「截图」能看到区域和全屏，输入「全屏」只看到全屏
    static func matches(_ keywords: [String], query: String) -> Bool {
        let text = query.lowercased()
        guard !text.isEmpty else { return false }
        return keywords.contains { keyword in
            let word = keyword.lowercased()
            return text.contains(word) || word.contains(text)
        }
    }

    public func makeView() -> AnyView {
        AnyView(ScreenshotView(capture: capture))
    }

    public func activate() {
        log.notice("插件已激活")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }

    /// 区域截图
    private func captureArea() async {
        EventBus.shared.post(HidePaletteEvent(restoreFocus: false))
        try? await Task.sleep(for: .milliseconds(200))

        if await capture.captureArea() {
            EventBus.shared.post(ShowHUDEvent(message: successMessage, tone: .success))
        }
    }

    /// 全屏截图
    private func captureFullScreen() async {
        EventBus.shared.post(HidePaletteEvent(restoreFocus: false))
        try? await Task.sleep(for: .milliseconds(200))

        if await capture.captureFullScreen() {
            EventBus.shared.post(ShowHUDEvent(message: successMessage, tone: .success))
        }
    }

    /// 截图成功后的提示语
    ///
    /// 只进剪贴板的截图没有文件，这时还说「已保存到桌面」会让用户去桌面找一个不存在的文件。
    private var successMessage: String {
        capture.lastCapturePath == nil ? "截图已复制到剪贴板" : "截图已保存到桌面"
    }
}
