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
    public static let triggerWords = ["截图", "screenshot", "屏幕截图", "截屏", "capture"]

    public var isEnabled = true

    private let log = QuickLog.plugin(ScreenshotPlugin.id)

    private let capture = ScreenCapture()

    public init() {}

    public func searchItems(query: String) async -> [SearchableItem] {
        guard Self.triggerWords.contains(where: { query.lowercased().contains($0) }) else { return [] }

        return [
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
            ),
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
        ]
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
