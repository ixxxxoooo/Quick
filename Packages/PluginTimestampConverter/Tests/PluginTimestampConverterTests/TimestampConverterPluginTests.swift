// TimestampConverterPluginTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import PluginTimestampConverter

@Suite("时间戳转换逻辑")
struct TimestampConverterLogicTests {

    /// 时区一律固定注入：跨机器、跨时区都必须得到同一结果
    private let utc = TimeZone(identifier: "UTC")!
    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    private func value(_ key: String, in conversion: TimestampConverterLogic.Conversion) -> String? {
        conversion.rows.first { $0.key == key }?.value
    }

    // MARK: - 时间戳 → 日期

    @Test("Unix 纪元在 UTC 下就是 1970-01-01 00:00:00")
    func epochInUTC() {
        let conversion = TimestampConverterLogic.convert("0", timeZone: utc)

        #expect(conversion.inputType == .timestamp)
        #expect(
            conversion.rows == [
                .init(key: "local", label: "本地时间", value: "1970-01-01 00:00:00"),
                .init(key: "iso", label: "ISO 8601", value: "1970-01-01T00:00:00Z"),
                .init(key: "unix", label: "Unix 时间戳（秒）", value: "0"),
                .init(key: "unixms", label: "Unix 时间戳（毫秒）", value: "0")
            ])
    }

    @Test("同一个时间戳在上海按 +08 显示")
    func epochInShanghai() {
        let conversion = TimestampConverterLogic.convert("0", timeZone: shanghai)

        #expect(conversion.inputType == .timestamp)
        #expect(value("local", in: conversion) == "1970-01-01 08:00:00")
        // ISO 8601 始终输出 UTC，与时区无关
        #expect(value("iso", in: conversion) == "1970-01-01T00:00:00Z")
    }

    @Test("毫秒时间戳按 1000 倍识别")
    func millisecondTimestamp() {
        let conversion = TimestampConverterLogic.convert("1700000000000", timeZone: utc)

        #expect(conversion.inputType == .timestamp)
        #expect(value("unix", in: conversion) == "1700000000")
        #expect(value("unixms", in: conversion) == "1700000000000")
    }

    @Test("1e12 是秒与毫秒的分界，边界本身按秒处理")
    func millisecondsThresholdBoundary() {
        let atThreshold = TimestampConverterLogic.convert("1000000000000", timeZone: utc)
        #expect(value("unix", in: atThreshold) == "1000000000000")

        let justOver = TimestampConverterLogic.convert("1000000000001", timeZone: utc)
        #expect(value("unix", in: justOver) == "1000000000")
    }

    @Test("负数时间戳（1970 之前）按秒处理")
    func negativeTimestamp() {
        let conversion = TimestampConverterLogic.convert("-86400", timeZone: utc)

        #expect(conversion.inputType == .timestamp)
        #expect(value("local", in: conversion) == "1969-12-31 00:00:00")
        #expect(value("unix", in: conversion) == "-86400")
    }

    @Test("负数毫秒时间戳同样按毫秒识别")
    func negativeMillisecondTimestamp() {
        let conversion = TimestampConverterLogic.convert("-1700000000000", timeZone: utc)

        #expect(conversion.inputType == .timestamp)
        #expect(value("unix", in: conversion) == "-1700000000")
        #expect(value("unixms", in: conversion) == "-1700000000000")
    }

    @Test("非有限输入不当作时间戳，也不会崩")
    func nonFiniteInputIsRejected() {
        // Double("inf") / Double("nan") 都能解析成功，若直接交给 Int() 会崩掉进程
        for text in ["inf", "-inf", "infinity", "nan"] {
            let conversion = TimestampConverterLogic.convert(text, timeZone: utc)
            #expect(conversion.inputType == .empty, "输入 \(text) 不该被当成时间戳")
            #expect(conversion.rows.isEmpty)
        }
    }

    @Test("大到溢出的数值不当作时间戳")
    func oversizedMagnitudeIsRejected() {
        let conversion = TimestampConverterLogic.convert("1e20", timeZone: utc)

        #expect(conversion.inputType == .empty)
        #expect(conversion.rows.isEmpty)
    }

    @Test("小数时间戳保留亚秒精度到毫秒")
    func fractionalTimestamp() {
        let conversion = TimestampConverterLogic.convert("1.5", timeZone: utc)

        #expect(conversion.inputType == .timestamp)
        #expect(value("local", in: conversion) == "1970-01-01 00:00:01")
        #expect(value("unixms", in: conversion) == "1500")
    }

    // MARK: - 日期 → 时间戳

    @Test("日期解析使用注入的时区")
    func dateParsingUsesInjectedTimeZone() {
        let inUTC = TimestampConverterLogic.convert("1970-01-01", timeZone: utc)
        #expect(inUTC.inputType == .date)
        #expect(value("unix", in: inUTC) == "0")

        // 东八区的 1970-01-01 00:00 等于 UTC 的 1969-12-31 16:00
        let inShanghai = TimestampConverterLogic.convert("1970-01-01", timeZone: shanghai)
        #expect(inShanghai.inputType == .date)
        #expect(value("unix", in: inShanghai) == "-28800")
        #expect(value("local", in: inShanghai) == "1970-01-01 00:00:00")
        #expect(value("iso", in: inShanghai) == "1969-12-31T16:00:00Z")
    }

    @Test("日期输入的结果行顺序为 秒/毫秒/本地/ISO")
    func dateRowsOrder() {
        let conversion = TimestampConverterLogic.convert("2023-11-15 06:13:20", timeZone: utc)

        #expect(conversion.inputType == .date)
        #expect(conversion.rows.map(\.key) == ["unix", "unixms", "local", "iso"])
        #expect(value("unix", in: conversion) == "1700028800")
        #expect(value("local", in: conversion) == "2023-11-15 06:13:20")
    }

    @Test("支持的所有日期格式都能解析")
    func everySupportedDateFormatParses() {
        let samples = [
            "2023-11-15 06:13:20", "2023-11-15", "2023/11/15 06:13:20",
            "2023/11/15", "11/15/2023"
        ]
        for sample in samples {
            let conversion = TimestampConverterLogic.convert(sample, timeZone: utc)
            #expect(conversion.inputType == .date, "\(sample) 应当能被识别为日期")
            #expect(!conversion.rows.isEmpty, "\(sample) 应当有结果行")
        }
    }

    // MARK: - 无效输入

    @Test("空输入、纯空白与无法识别的输入都返回空结果")
    func invalidInputYieldsEmptyResult() {
        for text in ["", "   ", "\n", "\t\n ", "hello", "上个月", "2023年11月"] {
            let conversion = TimestampConverterLogic.convert(text, timeZone: utc)
            #expect(conversion.inputType == .empty, "\(text.debugDescription) 不应被识别")
            #expect(conversion.rows.isEmpty)
        }
    }

    // MARK: - 当前时间戳

    @Test("填入当前使用注入的时刻")
    func currentTimestampUsesInjectedDate() {
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(TimestampConverterLogic.currentTimestamp(now: fixed) == "1700000000")
    }
}

@Suite("时间戳转换插件契约")
@MainActor
struct TimestampConverterPluginTests {

    @Test("插件 id 是 kebab-case 且与约定一致")
    func identifierIsKebabCase() {
        let id = TimestampConverterPlugin.id
        #expect(id == "timestamp-converter")
        #expect(id == id.lowercased())
        #expect(id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" })
        #expect(!id.hasPrefix("-") && !id.hasSuffix("-"))
    }

    @Test("名称、图标、触发词都不为空")
    func metadataIsPresent() {
        #expect(!TimestampConverterPlugin.name.isEmpty)
        #expect(!TimestampConverterPlugin.icon.isEmpty)
        #expect(!TimestampConverterPlugin.triggerWords.isEmpty)
    }

    /// 入口由静态命令承载，不再由搜索现算 —— 原来这条测试问的是 `searchItems` 的返回，
    /// 那个遗留 API 已删除（见 docs/refactor-plan.md Phase 0）。
    @Test("时间戳转日期与当前时间戳各一条命令，且功能命令带插件前缀")
    func commandsCoverBothDirections() {
        let commands = TimestampConverterPlugin.commands
        let ids = commands.map(\.id)

        #expect(ids.contains("timestamp-converter.toDate"))
        #expect(ids.contains("timestamp-converter.now"))
        let functionIDs = commands.filter { !$0.id.hasPrefix("plugin.open.") }.map(\.id)
        #expect(functionIDs.allSatisfy { $0.hasPrefix("timestamp-converter.") })
        #expect(commands.allSatisfy { $0.pluginID == TimestampConverterPlugin.id })
    }

    @Test("插件不参与按查询现算")
    func doesNotTakePartInDynamicSearch() async {
        let plugin = TimestampConverterPlugin()

        #expect(!plugin.accepts(query: "时间戳"))
        #expect(await plugin.dynamicSearch(query: "zzzz").isEmpty)
    }
}
