// ScreenshotDelivery.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import ImageIO
import QuickCore

/// 截图产物的去向：保存到桌面、复制到剪贴板、贴图
///
/// 设置（格式、是否落盘）在动作发生的那一刻现读，用户改完不必重启。
@MainActor
enum ScreenshotDelivery {

    private static let log = QuickLog.plugin(ScreenshotPlugin.id)

    /// 桌面目录
    static var desktopDirectory: String {
        NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true).first
            ?? NSTemporaryDirectory()
    }

    /// 设置页上的「保存到桌面」：关掉就只进剪贴板
    static var savesToDesktop: Bool {
        setting(PluginSettingKey.Screenshot.saveToDesktop, default: true)
    }

    /// 本次截图用的图片格式
    static var format: CaptureFormat {
        CaptureFormat(settingValue: UserDefaults.standard.string(forKey: PluginSettingKey.Screenshot.format))
    }

    // MARK: - 交付

    /// 按设置交付：默认「落盘 + 复制」，关掉落盘后只复制
    ///
    /// - Returns: 落盘路径；只复制时为 nil
    @discardableResult
    static func deliver(_ image: CGImage) -> String? {
        copyToPasteboard(image)
        playShutterSound()

        guard savesToDesktop else {
            log.notice("截图已复制到剪贴板（未落盘）")
            return nil
        }

        let currentFormat = format
        let path = ScreenshotNaming.outputPath(
            in: desktopDirectory, for: Date(), timeZone: .current, format: currentFormat)
        guard let data = CaptureOutput.data(image, format: currentFormat) else {
            log.error("截图编码失败，已退回只复制到剪贴板")
            return nil
        }
        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            log.notice("截图已保存：\(path, privacy: .public)")
            return path
        } catch {
            log.error("截图写入失败：\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 复制到剪贴板（PNG + TIFF 两种表示：前者保真，后者兼容性最好）
    @discardableResult
    static func copyToPasteboard(_ image: CGImage) -> Bool {
        let item = NSPasteboardItem()
        if let png = CaptureOutput.pngData(image) { item.setData(png, forType: .png) }
        if let tiff = CaptureOutput.tiffData(image) { item.setData(tiff, forType: .tiff) }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    /// 从剪贴板读一张图（贴图入口用）
    static func imageFromPasteboard() -> CGImage? {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .png),
            let source = CGImageSourceCreateWithData(data as CFData, nil)
        {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        if let data = pasteboard.data(forType: .tiff),
            let source = CGImageSourceCreateWithData(data as CFData, nil)
        {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        return nil
    }

    // MARK: - 内部

    private static func setting(_ key: String, default defaultValue: Bool) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    private static let shutterSound: NSSound? = {
        let path =
            "/System/Library/Components/CoreAudio.component"
            + "/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        return NSSound(contentsOfFile: path, byReference: true) ?? NSSound(named: "Pop")
    }()

    private static func playShutterSound() {
        shutterSound?.stop()
        shutterSound?.play()
    }
}
