// ScreenshotPluginTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
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

@Suite("截图命令行构造")
struct ScreenshotCommandTests {

    // 这些断言只是为了把「路径排在最后」这条约定钉住，值本身不重要
    private let path = "/tmp/Quick_20240102_030405.png"

    @Test("区域截图用交互式框选开关，路径在最后")
    func areaArguments() {
        #expect(
            ScreenshotCommand.arguments(mode: .area, outputPath: path)
                == ["-i", "-s", path])
    }

    @Test("全屏截图只有一个位置参数")
    func fullScreenArguments() {
        #expect(ScreenshotCommand.arguments(mode: .fullScreen, outputPath: path) == [path])
    }

    @Test("延时截图把秒数放在 -T 后面，路径仍在最后")
    func delayedArguments() {
        #expect(
            ScreenshotCommand.arguments(mode: .delayed(seconds: 3), outputPath: path)
                == ["-T", "3", path])
        // 0 秒不做特判，照样传 -T 0
        #expect(
            ScreenshotCommand.arguments(mode: .delayed(seconds: 0), outputPath: path)
                == ["-T", "0", path])
    }

    @Test("负数秒数原样透传，不做校验")
    func negativeDelayIsPassedThrough() {
        // 现有行为就是把 Int 直接插值，不在这一层拦截非法输入
        #expect(
            ScreenshotCommand.arguments(mode: .delayed(seconds: -1), outputPath: path)
                == ["-T", "-1", path])
    }

    @Test("所有模式的最后一个参数都是输出路径")
    func outputPathIsAlwaysLast() {
        // screencapture 只认最后一个位置参数作为输出文件，任何模式都不能破坏它
        let modes: [CaptureMode] = [.area, .fullScreen, .delayed(seconds: 5)]

        for mode in modes {
            #expect(
                ScreenshotCommand.arguments(mode: mode, outputPath: path).last == path,
                "模式 \(mode) 没有把路径放在最后")
        }
    }

    @Test("截图可执行文件与输出格式固定")
    func executableAndFormat() {
        #expect(ScreenshotCommand.executablePath == "/usr/sbin/screencapture")
        #expect(ScreenshotCommand.fileExtension == "png")
        #expect(ScreenshotCommand.fileNamePrefix == "Quick_")
        #expect(ScreenshotCommand.timestampFormat == "yyyyMMdd_HHmmss")
    }

    @Test("模式相等性按关联值判断")
    func modeEquality() {
        #expect(CaptureMode.delayed(seconds: 3) == .delayed(seconds: 3))
        #expect(CaptureMode.delayed(seconds: 3) != .delayed(seconds: 5))
        #expect(CaptureMode.area != .fullScreen)
        #expect(CaptureMode.fullScreen != .delayed(seconds: 0))
    }
}

@Suite("截图文件名与时间戳")
struct ScreenshotNamingTests {

    @Test("时间戳是紧凑的 yyyyMMdd_HHmmss")
    func timestampFormatting() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let date = try anchorDate(utc)

        #expect(ScreenshotCommand.timestamp(from: date, timeZone: utc) == "20240102_030405")
    }

    @Test("月、日、时、分、秒都补零到两位")
    func timestampComponentsAreZeroPadded() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let date = try #require(
            calendar.date(
                from: DateComponents(year: 2024, month: 3, day: 4, hour: 5, minute: 6, second: 7)))

        #expect(ScreenshotCommand.timestamp(from: date, timeZone: utc) == "20240304_050607")
    }

    @Test("时间戳随时区变化，可以跨天")
    func timestampFollowsTimeZone() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let plusEight = try #require(TimeZone(secondsFromGMT: 8 * 3600))
        let date = try anchorDate(utc)

        #expect(ScreenshotCommand.timestamp(from: date, timeZone: utc) == "20240102_030405")
        #expect(ScreenshotCommand.timestamp(from: date, timeZone: plusEight) == "20240102_110405")

        // UTC 当晚 23:30 在东八区已经是第二天
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let lateNight = try #require(
            calendar.date(from: DateComponents(year: 2024, month: 1, day: 2, hour: 23, minute: 30)))
        #expect(
            ScreenshotCommand.timestamp(from: lateNight, timeZone: plusEight) == "20240103_073000")
    }

    @Test("文件名是前缀 + 时间戳 + png")
    func fileNameShape() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let date = try anchorDate(utc)

        #expect(ScreenshotCommand.fileName(for: date, timeZone: utc) == "Quick_20240102_030405.png")
    }

    @Test("输出路径把文件名拼到保存目录下")
    func outputPathJoinsDirectory() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let date = try anchorDate(utc)

        #expect(
            ScreenshotCommand.outputPath(in: "/Users/me/Desktop", for: date, timeZone: utc)
                == "/Users/me/Desktop/Quick_20240102_030405.png")
        // 目录已经带尾斜杠时不产生双斜杠
        #expect(
            ScreenshotCommand.outputPath(in: "/Users/me/Desktop/", for: date, timeZone: utc)
                == "/Users/me/Desktop/Quick_20240102_030405.png")
        // 空目录退化成纯文件名，而不是以 / 开头
        #expect(
            ScreenshotCommand.outputPath(in: "", for: date, timeZone: utc)
                == "Quick_20240102_030405.png")
    }

    @Test("输出路径与参数一致：文件名真的出现在命令行里")
    func argumentsCarryTheGeneratedPath() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let date = try anchorDate(utc)
        let output = ScreenshotCommand.outputPath(in: "/tmp/shots", for: date, timeZone: utc)

        for mode: CaptureMode in [.area, .fullScreen, .delayed(seconds: 3)] {
            #expect(ScreenshotCommand.arguments(mode: mode, outputPath: output).last == output)
        }
        #expect(output.hasSuffix(".png"))
    }
}

@Suite("截图插件契约")
@MainActor
struct ScreenshotPluginTests {

    @Test("插件 id 是 kebab-case 且等于约定值")
    func identifierIsKebabCase() {
        let id = ScreenshotPlugin.id

        #expect(id == "screenshot")
        #expect(id == id.lowercased())
        #expect(id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" })
        #expect(!id.hasPrefix("-") && !id.hasSuffix("-") && !id.contains("--"))
    }

    @Test("名称、图标、触发词齐备")
    func metadataIsComplete() {
        #expect(ScreenshotPlugin.name == "截图工具")
        #expect(ScreenshotPlugin.icon == "camera")
        #expect(ScreenshotPlugin.triggerWords == ["截图", "screenshot", "屏幕截图", "截屏", "capture"])
        #expect(ScreenshotPlugin.triggerWords.allSatisfy { !$0.isEmpty })
    }

    @Test("命中触发词时给出区域与全屏两个入口")
    func triggerWordYieldsTwoEntries() async {
        let plugin = ScreenshotPlugin()
        let results = await plugin.searchItems(query: "截图")

        #expect(results.count == 2)
        #expect(results.map(\.id) == ["screenshot.area", "screenshot.full"])
        #expect(results.allSatisfy { $0.pluginID == ScreenshotPlugin.id })
        #expect(results.map(\.relevance) == [0.8, 0.7])
        #expect(results.allSatisfy { !$0.title.isEmpty && !$0.icon.isEmpty })
    }

    @Test("每个触发词都能唤醒插件")
    func everyTriggerWordMatches() async {
        let plugin = ScreenshotPlugin()

        for trigger in ScreenshotPlugin.triggerWords {
            let results = await plugin.searchItems(query: trigger)
            #expect(results.count == 2, "触发词「\(trigger)」没有命中")
        }
    }

    @Test("触发词大小写不敏感")
    func triggerWordIsCaseInsensitive() async {
        let plugin = ScreenshotPlugin()
        let results = await plugin.searchItems(query: "SCREENSHOT")

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.pluginID == ScreenshotPlugin.id })
    }

    @Test("无关查询与空查询不返回结果")
    func unrelatedQueryYieldsNothing() async {
        let plugin = ScreenshotPlugin()

        #expect(await plugin.searchItems(query: "").isEmpty)
        #expect(await plugin.searchItems(query: "天气").isEmpty)
        #expect(await plugin.searchItems(query: "window").isEmpty)
    }
}
