// ScreenshotPluginTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

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

@Suite("截图命令行构造")
struct ScreenshotCommandTests {

    // 这些断言只是为了把「路径排在最后」这条约定钉住，值本身不重要
    private let path = "/tmp/Quick_20240102_030405.png"

    @Test("区域截图用交互式框选开关，路径在最后")
    func areaArguments() {
        #expect(
            ScreenshotCommand.arguments(
                mode: .area, destination: .file(path: path), format: .png, includePointer: false)
                == ["-i", "-s", "-t", "png", path])
    }

    @Test("全屏截图只有一个位置参数")
    func fullScreenArguments() {
        #expect(
            ScreenshotCommand.arguments(
                mode: .fullScreen, destination: .file(path: path), format: .png, includePointer: false)
                == ["-t", "png", path])
    }

    @Test("窗口截图用交互式窗口选择开关")
    func windowArguments() {
        #expect(
            ScreenshotCommand.arguments(
                mode: .window, destination: .file(path: path), format: .png, includePointer: false)
                == ["-i", "-W", "-t", "png", path])
    }

    @Test("延时截图把秒数放在 -T 后面，路径仍在最后")
    func delayedArguments() {
        #expect(
            ScreenshotCommand.arguments(
                mode: .delayed(seconds: 3), destination: .file(path: path), format: .png,
                includePointer: false)
                == ["-T", "3", "-t", "png", path])
        // 0 秒不做特判，照样传 -T 0
        #expect(
            ScreenshotCommand.arguments(
                mode: .delayed(seconds: 0), destination: .file(path: path), format: .png,
                includePointer: false)
                == ["-T", "0", "-t", "png", path])
    }

    @Test("负数秒数原样透传，不做校验")
    func negativeDelayIsPassedThrough() {
        // 现有行为就是把 Int 直接插值，不在这一层拦截非法输入
        #expect(
            ScreenshotCommand.arguments(
                mode: .delayed(seconds: -1), destination: .file(path: path), format: .png,
                includePointer: false)
                == ["-T", "-1", "-t", "png", path])
    }

    @Test("所有模式的最后一个参数都是输出路径")
    func outputPathIsAlwaysLast() {
        // screencapture 只认最后一个位置参数作为输出文件，任何模式都不能破坏它
        let modes: [CaptureMode] = [.area, .fullScreen, .window, .delayed(seconds: 5)]

        for mode in modes {
            #expect(
                ScreenshotCommand.arguments(
                    mode: mode, destination: .file(path: path), format: .png, includePointer: false
                ).last == path,
                "模式 \(mode) 没有把路径放在最后")
        }
    }

    @Test("截图可执行文件与输出格式固定")
    func executableAndFormat() {
        #expect(ScreenshotCommand.executablePath == "/usr/sbin/screencapture")
        #expect(CaptureFormat.png.fileExtension == "png")
        #expect(ScreenshotCommand.fileNamePrefix == "Quick_")
        #expect(ScreenshotCommand.timestampFormat == "yyyyMMdd_HHmmss")
    }

    @Test("开关都排在输出路径前面")
    func flagsPrecedeTheOutputPath() {
        #expect(
            ScreenshotCommand.arguments(
                mode: .area, destination: .file(path: "/tmp/Quick_20240102_030405.jpg"),
                format: .jpeg, includePointer: true)
                == ["-i", "-s", "-C", "-t", "jpg", "/tmp/Quick_20240102_030405.jpg"])
    }

    @Test("进剪贴板时不传输出路径，只传 -c")
    func clipboardDestinationCarriesNoPath() {
        #expect(
            ScreenshotCommand.arguments(
                mode: .fullScreen, destination: .clipboard, format: .png, includePointer: false)
                == ["-c"])
    }

    @Test("认不出的格式值退回 PNG")
    func unknownFormatFallsBackToPNG() {
        // 设置值可能被手改过：为格式不符丢掉一整张截图不值得
        #expect(CaptureFormat(settingValue: "bmp") == .png)
        #expect(CaptureFormat(settingValue: nil) == .png)
        #expect(CaptureFormat(settingValue: "heic") == .heic)
    }

    @Test("模式相等性按关联值判断")
    func modeEquality() {
        #expect(CaptureMode.delayed(seconds: 3) == .delayed(seconds: 3))
        #expect(CaptureMode.delayed(seconds: 3) != .delayed(seconds: 5))
        #expect(CaptureMode.area != .fullScreen)
        #expect(CaptureMode.fullScreen != .delayed(seconds: 0))
        #expect(CaptureMode.window != .area)
        #expect(CaptureMode.window != .fullScreen)
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

        #expect(
            ScreenshotCommand.fileName(for: date, timeZone: utc, format: .png)
                == "Quick_20240102_030405.png")
    }

    @Test("输出路径把文件名拼到保存目录下")
    func outputPathJoinsDirectory() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let date = try anchorDate(utc)

        #expect(
            ScreenshotCommand.outputPath(in: "/Users/me/Desktop", for: date, timeZone: utc, format: .png)
                == "/Users/me/Desktop/Quick_20240102_030405.png")
        // 目录已经带尾斜杠时不产生双斜杠
        #expect(
            ScreenshotCommand.outputPath(in: "/Users/me/Desktop/", for: date, timeZone: utc, format: .png)
                == "/Users/me/Desktop/Quick_20240102_030405.png")
        // 空目录退化成纯文件名，而不是以 / 开头
        #expect(
            ScreenshotCommand.outputPath(in: "", for: date, timeZone: utc, format: .png)
                == "Quick_20240102_030405.png")
    }

    @Test("输出路径与参数一致：文件名真的出现在命令行里")
    func argumentsCarryTheGeneratedPath() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let date = try anchorDate(utc)
        let output = ScreenshotCommand.outputPath(in: "/tmp/shots", for: date, timeZone: utc, format: .png)

        for mode: CaptureMode in [.area, .fullScreen, .window, .delayed(seconds: 3)] {
            #expect(
                ScreenshotCommand.arguments(
                    mode: mode, destination: .file(path: output), format: .png, includePointer: false
                ).last == output)
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
        #expect(
            ScreenshotPlugin.triggerWords == [
                "截图工具", "截图", "截屏", "screenshot", "区域截图", "框选",
                "全屏截图",
                "窗口截图",
                "贴图", "钉在桌面", "pin"
            ])
        // 各组关键字之间不重叠
        #expect(Set(ScreenshotPlugin.areaKeywords).isDisjoint(with: ScreenshotPlugin.fullKeywords))
        #expect(Set(ScreenshotPlugin.areaKeywords).isDisjoint(with: ScreenshotPlugin.windowKeywords))
        #expect(Set(ScreenshotPlugin.areaKeywords).isDisjoint(with: ScreenshotPlugin.pinKeywords))
        #expect(ScreenshotPlugin.triggerWords.allSatisfy { !$0.isEmpty })
    }

    @Test("命中截图触发词时给出区域、全屏与窗口三个入口")
    func triggerWordYieldsMultipleEntries() async {
        let plugin = ScreenshotPlugin()
        let results = await plugin.searchItems(query: "截图")

        // 「截图」是区域、全屏、窗口三组关键字的子串
        #expect(results.count == 3)
        #expect(results.map(\.id) == ["screenshot.area", "screenshot.full", "screenshot.window"])
        #expect(results.allSatisfy { $0.pluginID == ScreenshotPlugin.id })
        #expect(results.map(\.relevance) == [0.8, 0.7, 0.7])
        #expect(results.allSatisfy { !$0.title.isEmpty && !$0.icon.isEmpty })
    }

    @Test("每个触发词都能唤醒插件")
    func everyTriggerWordMatches() async {
        let plugin = ScreenshotPlugin()

        for trigger in ScreenshotPlugin.areaKeywords {
            let results = await plugin.searchItems(query: trigger)
            #expect(results.contains { $0.id == "screenshot.area" }, "触发词「\(trigger)」没有命中区域截图")
        }
        for trigger in ScreenshotPlugin.fullKeywords {
            let results = await plugin.searchItems(query: trigger)
            #expect(results.contains { $0.id == "screenshot.full" }, "触发词「\(trigger)」没有命中全屏截图")
        }
        for trigger in ScreenshotPlugin.windowKeywords {
            let results = await plugin.searchItems(query: trigger)
            #expect(results.contains { $0.id == "screenshot.window" }, "触发词「\(trigger)」没有命中窗口截图")
        }
        for trigger in ScreenshotPlugin.pinKeywords {
            let results = await plugin.searchItems(query: trigger)
            #expect(results.contains { $0.id == "screenshot.pin" }, "触发词「\(trigger)」没有命中贴图")
        }
    }

    @Test("触发词大小写不敏感")
    func triggerWordIsCaseInsensitive() async {
        let plugin = ScreenshotPlugin()
        let results = await plugin.searchItems(query: "SCREENSHOT")

        #expect(results.count == 1)
        #expect(results.allSatisfy { $0.id == "screenshot.area" })
    }

    @Test("无关查询与空查询不返回结果")
    func unrelatedQueryYieldsNothing() async {
        let plugin = ScreenshotPlugin()

        #expect(await plugin.searchItems(query: "").isEmpty)
        #expect(await plugin.searchItems(query: "天气").isEmpty)
    }

    @Test("窗口截图触发词单独命中")
    func windowTriggerYieldsWindowEntry() async {
        let plugin = ScreenshotPlugin()
        let results = await plugin.searchItems(query: "窗口截图")

        #expect(results.contains { $0.id == "screenshot.window" })
    }

    @Test("贴图触发词单独命中")
    func pinTriggerYieldsPinEntry() async {
        let plugin = ScreenshotPlugin()
        let results = await plugin.searchItems(query: "贴图")

        #expect(results.contains { $0.id == "screenshot.pin" })
    }
}

// MARK: - 设置接线

/// 这一组验证设置页上的三个截图开关真的改变了 `screencapture` 拿到的命令行。
///
/// 串行执行：`UserDefaults` 是进程级的，并行跑会让「开关是开还是关」取决于另一个
/// 测试的进度。真实截图（起进程、要屏幕录制权限）不在测试范围内，这里断言的是
/// 它拿到的参数 —— 参数错了，截图本身对不对就没有意义了。
@Suite("截图设置接线", .serialized)
@MainActor
struct ScreenshotSettingWiringTests {

    /// 临时改一个设置键并在结束时还原
    private func withSetting(_ key: String, value: Any, _ body: () throws -> Void) rethrows {
        let original = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(value, forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        try body()
    }

    @Test("格式设置决定 -t 参数与文件扩展名")
    func formatFollowsTheSetting() {
        // 设置页存的是 jpeg，命令行与扩展名用的是 jpg —— 两者不同，所以逐个钉住
        let cases: [(setting: String, argument: String, fileExtension: String)] = [
            ("png", "png", "png"),
            ("jpeg", "jpg", "jpg"),
            ("heic", "heic", "heic")
        ]

        for testCase in cases {
            withSetting(PluginSettingKey.Screenshot.format, value: testCase.setting) {
                let request = ScreenCapture().request(for: .fullScreen)
                let path = request.destination.filePath ?? ""

                #expect(request.format.rawValue == testCase.setting)
                #expect(request.arguments.contains("-t"), "格式没有进命令行")
                #expect(request.arguments.contains(testCase.argument))
                #expect(path.hasSuffix(".\(testCase.fileExtension)"), "扩展名与格式不符：\(path)")
            }
        }
    }

    @Test("「包含鼠标指针」开关决定有没有 -C")
    func pointerFollowsTheSetting() {
        withSetting(PluginSettingKey.Screenshot.includePointer, value: true) {
            let request = ScreenCapture().request(for: .fullScreen)

            #expect(request.includePointer)
            #expect(request.arguments.contains("-C"), "开着「包含鼠标指针」却没有传 -C")
        }

        withSetting(PluginSettingKey.Screenshot.includePointer, value: false) {
            let request = ScreenCapture().request(for: .fullScreen)

            #expect(request.includePointer == false)
            #expect(!request.arguments.contains("-C"), "关掉「包含鼠标指针」仍然传了 -C")
        }
    }

    @Test("关掉「保存到桌面」后截图进剪贴板，而不是落文件")
    func saveToDesktopFollowsTheSetting() throws {
        try withSetting(PluginSettingKey.Screenshot.saveToDesktop, value: true) {
            let request = ScreenCapture().request(for: .area)
            let path = try #require(request.destination.filePath)

            #expect(request.arguments.last == path, "写文件时路径必须是最后一个位置参数")
            #expect(!request.arguments.contains("-c"))
        }

        withSetting(PluginSettingKey.Screenshot.saveToDesktop, value: false) {
            let request = ScreenCapture().request(for: .area)

            #expect(request.destination == .clipboard)
            #expect(request.destination.filePath == nil)
            #expect(request.arguments.contains("-c"), "进剪贴板要传 -c")
            #expect(!request.arguments.contains { $0.hasPrefix("/") }, "进剪贴板时不该出现输出路径")
        }
    }
}
