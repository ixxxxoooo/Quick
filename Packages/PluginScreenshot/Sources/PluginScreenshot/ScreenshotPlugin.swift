// ScreenshotPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore
import QuickUI
import SwiftUI

/// 截图工具插件
///
/// 参考 jietu 项目：自绘遮罩冻结屏幕 → 原地框选与标注 → 保存 / 复制 / 钉图。
/// 抓屏走 ScreenCaptureKit（不再用系统 `screencapture`），因为原地标注需要拿到
/// 冻结的那一帧画面。
@MainActor
public final class ScreenshotPlugin: QuickPlugin, PluginViewProviding, PluginSettingsProviding {

    public nonisolated static let id = "screenshot"
    public nonisolated static let name = "截图工具"
    public nonisolated static let icon = "camera.fill"
    public nonisolated static let description =
        "自绘遮罩截图，支持原地框选与标注（矩形、箭头、画笔、文字、马赛克、序号），可保存、复制或钉在桌面。"
    public nonisolated static let areaKeywords = ["截图工具", "截图", "截屏", "screenshot", "区域截图", "框选"]
    public nonisolated static let fullKeywords = ["全屏截图"]
    public nonisolated static let windowKeywords = ["窗口截图"]
    public nonisolated static let pinKeywords = ["贴图", "钉在桌面", "pin"]
    public nonisolated static let triggerWords =
        areaKeywords + fullKeywords + windowKeywords + pinKeywords

    public var isEnabled = true

    private let log = QuickLog.plugin(ScreenshotPlugin.id)
    private let overlay = OverlayCoordinator()

    public init() {}

    // MARK: - 命令

    public static var functionCommands: [CommandDescriptor] {
        [
            CommandDescriptor(
                id: "screenshot.area",
                pluginID: id,
                pluginName: name,
                title: "区域截图",
                subtitle: "框选屏幕区域并标注",
                keywords: areaKeywords,
                icon: "rectangle.dashed"
            ),
            CommandDescriptor(
                id: "screenshot.full",
                pluginID: id,
                pluginName: name,
                title: "全屏截图",
                subtitle: "截取整个屏幕并可标注",
                keywords: fullKeywords,
                icon: "rectangle.on.rectangle"
            ),
            CommandDescriptor(
                id: "screenshot.window",
                pluginID: id,
                pluginName: name,
                title: "窗口截图",
                subtitle: "点击选择要截取的窗口",
                keywords: windowKeywords,
                icon: "macwindow"
            ),
            CommandDescriptor(
                id: "screenshot.pin",
                pluginID: id,
                pluginName: name,
                title: "贴图",
                subtitle: "将剪贴板里的图片钉在桌面",
                keywords: pinKeywords,
                icon: "pin"
            )
        ]
    }

    public func perform(commandID: String) {
        switch commandID {
        case "screenshot.area":
            Task { await overlay.begin(windowMode: false) }
        case "screenshot.full":
            Task { await overlay.begin(windowMode: false, preselectFullScreen: true) }
        case "screenshot.window":
            Task { await overlay.begin(windowMode: true) }
        case "screenshot.pin":
            overlay.pinExistingImage()
        default:
            break
        }
    }

    /// 查询包含关键字，或关键字包含查询
    static func matches(_ keywords: [String], query: String) -> Bool {
        let text = query.lowercased()
        guard !text.isEmpty else { return false }
        return keywords.contains { keyword in
            let word = keyword.lowercased()
            return text.contains(word) || word.contains(text)
        }
    }

    public func makeView() -> AnyView {
        AnyView(
            ScreenshotView(
                onArea: { [weak self] in Task { await self?.overlay.begin(windowMode: false) } },
                onFullScreen: { [weak self] in
                    Task { await self?.overlay.begin(windowMode: false, preselectFullScreen: true) }
                },
                onWindow: { [weak self] in Task { await self?.overlay.begin(windowMode: true) } },
                onPin: { [weak self] in self?.overlay.pinExistingImage() }
            )
        )
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(ScreenshotSettingsView())
    }

    public func activate() {
        log.notice("插件已激活")
    }

    public func deactivate() {
        log.notice("插件已停用")
    }
}
