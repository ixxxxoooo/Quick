// ScreenshotModule.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 截图工具模块
///
/// 屏幕截图 + 简单标注编辑器。
@MainActor
public final class ScreenshotModule: QuickModule {

    public static let id = "screenshot"
    public static let name = "截图工具"
    public static let icon = "camera"

    public var isEnabled = true

    private let log = QuickLog.module(ScreenshotModule.id)

    private let capture = ScreenCapture()

    public init() {}

    public func searchItems(query: String) async -> [SearchableItem] {
        let triggers = ["截图", "screenshot", "屏幕截图", "截屏", "capture"]
        guard triggers.contains(where: { query.lowercased().contains($0) }) else { return [] }

        return [
            SearchableItem(
                id: "screenshot.area",
                moduleID: Self.id,
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
                moduleID: Self.id,
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
        log.notice("模块已激活")
    }

    public func deactivate() {
        log.notice("模块已停用")
    }

    /// 区域截图
    private func captureArea() async {
        EventBus.shared.post(HidePaletteEvent(restoreFocus: false))
        try? await Task.sleep(for: .milliseconds(200))

        if await capture.captureArea() {
            EventBus.shared.post(ShowHUDEvent(message: "截图已保存到桌面", tone: .success))
        }
    }

    /// 全屏截图
    private func captureFullScreen() async {
        EventBus.shared.post(HidePaletteEvent(restoreFocus: false))
        try? await Task.sleep(for: .milliseconds(200))

        if await capture.captureFullScreen() {
            EventBus.shared.post(ShowHUDEvent(message: "截图已保存到桌面", tone: .success))
        }
    }
}
