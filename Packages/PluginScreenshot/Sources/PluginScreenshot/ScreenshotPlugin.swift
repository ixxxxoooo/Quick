// ScreenshotPlugin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 截图工具插件
///
/// 参考 jietu 项目与 Fasty screenshot 插件：
/// 支持区域截图、全屏截图、窗口截图与贴图功能。
@MainActor
public final class ScreenshotPlugin: QuickPlugin {

    public static let id = "screenshot"
    public static let name = "截图工具"
    public static let icon = "camera"
    public static let description = "调用系统级截屏能力，支持全屏、交互式区域选区、窗口截图与贴图，可选择存入剪贴板或桌面。"
    /// 区域截图的关键字，对齐 Fasty `plugins/screenshot` 的 area / capture。和全屏那组不能有相同的词
    public static let areaKeywords = ["截图工具", "截图", "截屏", "screenshot", "区域截图", "框选"]
    /// 全屏截图的关键字
    public static let fullKeywords = ["全屏截图"]
    /// 窗口截图的关键字（参考 jietu 的窗口截图功能）
    public static let windowKeywords = ["窗口截图"]
    /// 贴图的关键字（参考 jietu 的 PinWindowController 功能）
    public static let pinKeywords = ["贴图", "钉在桌面", "pin"]
    public static let triggerWords = areaKeywords + fullKeywords + windowKeywords + pinKeywords

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
            ),
            CommandDescriptor(
                id: "screenshot.window",
                pluginID: id,
                pluginName: name,
                title: "窗口截图",
                subtitle: "截取指定窗口",
                keywords: windowKeywords,
                icon: "macwindow"
            ),
            CommandDescriptor(
                id: "screenshot.pin",
                pluginID: id,
                pluginName: name,
                title: "贴图",
                subtitle: "将剪贴板图片钉在桌面",
                keywords: pinKeywords,
                icon: "pin"
            )
        ]
    }

    public func perform(commandID: String) {
        switch commandID {
        case "screenshot.area":
            Task { await captureArea() }
        case "screenshot.full":
            Task { await captureFullScreen() }
        case "screenshot.window":
            Task { await captureWindow() }
        case "screenshot.pin":
            pinFromClipboard()
        default:
            break
        }
    }

    public func searchItems(query: String) async -> [SearchableItem] {
        let area = Self.matches(Self.areaKeywords, query: query)
        let full = Self.matches(Self.fullKeywords, query: query)
        let window = Self.matches(Self.windowKeywords, query: query)
        let pin = Self.matches(Self.pinKeywords, query: query)
        guard area || full || window || pin else { return [] }

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
        if window {
            items.append(
                SearchableItem(
                    id: "screenshot.window",
                    pluginID: Self.id,
                    title: "窗口截图",
                    subtitle: "截取指定窗口",
                    icon: "macwindow",
                    relevance: 0.7,
                    action: { [weak self] in
                        Task { await self?.captureWindow() }
                    }
                )
            )
        }
        if pin {
            items.append(
                SearchableItem(
                    id: "screenshot.pin",
                    pluginID: Self.id,
                    title: "贴图",
                    subtitle: "将剪贴板图片钉在桌面",
                    icon: "pin",
                    relevance: 0.7,
                    action: { [weak self] in
                        self?.pinFromClipboard()
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

    /// 窗口截图（参考 jietu 的 handleWindowCapture，使用 screencapture -w 交互式窗口选择）
    private func captureWindow() async {
        EventBus.shared.post(HidePaletteEvent(restoreFocus: false))
        try? await Task.sleep(for: .milliseconds(200))

        if await capture.captureWindow() {
            EventBus.shared.post(ShowHUDEvent(message: successMessage, tone: .success))
        }
    }

    /// 贴图：从剪贴板读取图片并钉在桌面（参考 jietu 的 PinWindowController）
    private func pinFromClipboard() {
        EventBus.shared.post(HidePaletteEvent(restoreFocus: false))

        guard let image = NSPasteboard.general.readImage() else {
            EventBus.shared.post(ShowHUDEvent(message: "剪贴板中没有图片", tone: .warning))
            return
        }

        PinWindowController.pin(image: image)
        log.notice("已将剪贴板图片钉在桌面")
        EventBus.shared.post(ShowHUDEvent(message: "已钉在桌面", tone: .success))
    }

    /// 截图成功后的提示语
    ///
    /// 只进剪贴板的截图没有文件，这时还说「已保存到桌面」会让用户去桌面找一个不存在的文件。
    private var successMessage: String {
        capture.lastCapturePath == nil ? "截图已复制到剪贴板" : "截图已保存到桌面"
    }
}

/// NSPasteboard 图片读取扩展
private extension NSPasteboard {
    /// 从剪贴板读取图片
    func readImage() -> NSImage? {
        if let data = data(forType: .tiff), let image = NSImage(data: data) {
            return image
        }
        if let data = data(forType: .png), let image = NSImage(data: data) {
            return image
        }
        return nil
    }
}
