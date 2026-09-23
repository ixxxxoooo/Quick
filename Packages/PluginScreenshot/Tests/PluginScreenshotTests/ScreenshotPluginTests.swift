// ScreenshotPluginTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import CoreGraphics
import Foundation
import QuickCore
import Testing

@testable import PluginScreenshot

/// 固定时区的锚点时刻：2024-01-02 03:04:05 UTC
private func anchorDate(_ timeZone: TimeZone) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let date = calendar.date(
        from: DateComponents(year: 2024, month: 1, day: 2, hour: 3, minute: 4, second: 5))
    return try #require(date)
}

/// 造一张纯色图，只为几何换算用
private func makeImage(width: Int, height: Int) throws -> CGImage {
    let context = try #require(
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    return try #require(context.makeImage())
}

// MARK: - 文件名与时间戳

@Suite("截图文件名与时间戳")
struct ScreenshotNamingTests {

    @Test("时间戳是紧凑的 yyyyMMdd_HHmmss")
    func timestampFormatting() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let date = try anchorDate(utc)
        #expect(ScreenshotNaming.timestamp(from: date, timeZone: utc) == "20240102_030405")
    }

    @Test("时间戳随时区变化，可以跨天")
    func timestampFollowsTimeZone() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let plusEight = try #require(TimeZone(secondsFromGMT: 8 * 3600))
        let date = try anchorDate(utc)

        #expect(ScreenshotNaming.timestamp(from: date, timeZone: utc) == "20240102_030405")
        #expect(ScreenshotNaming.timestamp(from: date, timeZone: plusEight) == "20240102_110405")
    }

    @Test("文件名是前缀 + 时间戳 + 扩展名")
    func fileNameShape() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let date = try anchorDate(utc)

        #expect(
            ScreenshotNaming.fileName(for: date, timeZone: utc, format: .png)
                == "Quick_20240102_030405.png")
        #expect(
            ScreenshotNaming.fileName(for: date, timeZone: utc, format: .jpeg)
                == "Quick_20240102_030405.jpg")
    }

    @Test("输出路径把文件名拼到保存目录下")
    func outputPathJoinsDirectory() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let date = try anchorDate(utc)

        #expect(
            ScreenshotNaming.outputPath(in: "/Users/me/Desktop", for: date, timeZone: utc, format: .png)
                == "/Users/me/Desktop/Quick_20240102_030405.png")
        #expect(
            ScreenshotNaming.outputPath(in: "/Users/me/Desktop/", for: date, timeZone: utc, format: .png)
                == "/Users/me/Desktop/Quick_20240102_030405.png")
        #expect(
            ScreenshotNaming.outputPath(in: "", for: date, timeZone: utc, format: .png)
                == "Quick_20240102_030405.png")
    }

    @Test("认不出的格式值退回 PNG")
    func unknownFormatFallsBackToPNG() {
        #expect(CaptureFormat(settingValue: "bmp") == .png)
        #expect(CaptureFormat(settingValue: nil) == .png)
        #expect(CaptureFormat(settingValue: "heic") == .heic)
    }
}

// MARK: - 几何

@Suite("截图几何换算")
struct ScreenshotGeometryTests {

    @Test("画布局部矩形翻成图像像素矩形（Y 轴翻转）")
    func pixelRectFlipsY() throws {
        let image = try makeImage(width: 200, height: 100)
        // 一块 100×50 的显示器，画面 200×100 → scale = 2
        let snapshot = DisplaySnapshot(
            displayID: 1,
            screenFrameInPoints: CGRect(x: 0, y: 0, width: 100, height: 50),
            nominalScaleFactor: 2,
            image: image)

        #expect(snapshot.effectiveScale == 2)
        // 左下角 (0,0)-(10,10) → 像素 (0, 80)-(20, 100)
        let rect = snapshot.pixelRect(fromLocalRect: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(rect == CGRect(x: 0, y: 80, width: 20, height: 20))
    }

    @Test("标注平移 + 缩放到目标坐标系")
    func annotationTransformsToTargetSpace() {
        let annotation = Annotation(
            kind: .rectangle(CGRect(x: 20, y: 30, width: 10, height: 5)), color: .red, lineWidth: 3)

        // 以 (10,10) 为原点、放大 2 倍
        let transformed = annotation.transformed(offset: CGPoint(x: 10, y: 10), scale: 2)

        #expect(transformed.kind == .rectangle(CGRect(x: 20, y: 40, width: 20, height: 10)))
        #expect(transformed.lineWidth == 6)
    }

    @Test("文字标注随缩放改变字号")
    func textAnnotationScalesFont() {
        let annotation = Annotation(
            kind: .text(origin: CGPoint(x: 5, y: 5), string: "hi", fontSize: 18), color: .black)

        let transformed = annotation.transformed(offset: .zero, scale: 2)
        #expect(transformed.kind == .text(origin: CGPoint(x: 10, y: 10), string: "hi", fontSize: 36))
    }
}

// MARK: - 插件契约

@Suite("截图插件契约")
@MainActor
struct ScreenshotPluginContractTests {

    @Test("名称、图标、触发词齐备")
    func metadataIsComplete() {
        #expect(ScreenshotPlugin.name == "截图工具")
        #expect(ScreenshotPlugin.icon == "camera.fill")
        #expect(
            ScreenshotPlugin.triggerWords == [
                "截图工具", "截图", "截屏", "screenshot", "区域截图", "框选",
                "全屏截图",
                "窗口截图",
                "贴图", "钉在桌面", "pin"
            ])
        #expect(Set(ScreenshotPlugin.areaKeywords).isDisjoint(with: ScreenshotPlugin.fullKeywords))
        #expect(Set(ScreenshotPlugin.areaKeywords).isDisjoint(with: ScreenshotPlugin.windowKeywords))
        #expect(Set(ScreenshotPlugin.areaKeywords).isDisjoint(with: ScreenshotPlugin.pinKeywords))
    }

    @Test("「截图」同时给出区域、全屏、窗口三个入口")
    func triggerWordYieldsMultipleEntries() async {
        let results = await ScreenshotPlugin().searchItems(query: "截图")

        #expect(results.count == 3)
        #expect(results.map(\.id) == ["screenshot.area", "screenshot.full", "screenshot.window"])
        #expect(results.map(\.relevance) == [0.8, 0.7, 0.7])
    }

    @Test("每个触发词都能唤醒对应入口")
    func everyTriggerWordMatches() async {
        let plugin = ScreenshotPlugin()

        for trigger in ScreenshotPlugin.areaKeywords {
            #expect(
                await plugin.searchItems(query: trigger).contains { $0.id == "screenshot.area" },
                "触发词「\(trigger)」没有命中区域截图")
        }
        for trigger in ScreenshotPlugin.fullKeywords {
            #expect(
                await plugin.searchItems(query: trigger).contains { $0.id == "screenshot.full" },
                "触发词「\(trigger)」没有命中全屏截图")
        }
        for trigger in ScreenshotPlugin.windowKeywords {
            #expect(
                await plugin.searchItems(query: trigger).contains { $0.id == "screenshot.window" },
                "触发词「\(trigger)」没有命中窗口截图")
        }
        for trigger in ScreenshotPlugin.pinKeywords {
            #expect(
                await plugin.searchItems(query: trigger).contains { $0.id == "screenshot.pin" },
                "触发词「\(trigger)」没有命中贴图")
        }
    }

    @Test("触发词大小写不敏感")
    func triggerWordIsCaseInsensitive() async {
        let results = await ScreenshotPlugin().searchItems(query: "SCREENSHOT")

        #expect(results.count == 1)
        #expect(results.allSatisfy { $0.id == "screenshot.area" })
    }

    @Test("无关查询与空查询不返回结果")
    func unrelatedQueryYieldsNothing() async {
        let plugin = ScreenshotPlugin()

        #expect(await plugin.searchItems(query: "").isEmpty)
        #expect(await plugin.searchItems(query: "天气").isEmpty)
    }
}
