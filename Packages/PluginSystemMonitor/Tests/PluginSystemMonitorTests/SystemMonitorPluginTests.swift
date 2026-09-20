// SystemMonitorPluginTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import PluginSystemMonitor

@Suite("运行时间格式化")
struct SystemMetricsUptimeTests {

    @Test("零值和不足一分钟都显示 0 小时 0 分钟")
    func zeroAndSubMinute() {
        #expect(SystemMetrics.uptime(0) == "0 小时 0 分钟")
        #expect(SystemMetrics.uptime(1) == "0 小时 0 分钟")
        #expect(SystemMetrics.uptime(59) == "0 小时 0 分钟")
    }

    @Test("分钟数向下取整，秒被丢掉")
    func minutesTruncate() {
        #expect(SystemMetrics.uptime(60) == "0 小时 1 分钟")
        #expect(SystemMetrics.uptime(119) == "0 小时 1 分钟")
        #expect(SystemMetrics.uptime(3599) == "0 小时 59 分钟")
    }

    @Test("整小时")
    func wholeHours() {
        #expect(SystemMetrics.uptime(3600) == "1 小时 0 分钟")
        #expect(SystemMetrics.uptime(3660) == "1 小时 1 分钟")
        #expect(SystemMetrics.uptime(86399) == "23 小时 59 分钟")
    }

    @Test("判据是「超过 24 小时」：恰好 24 小时仍按小时显示")
    func exactlyOneDayIsStillHours() {
        // 边界不做特判，24 小时整显示 "24 小时 0 分钟"，第 25 小时才切成「天」
        #expect(SystemMetrics.uptime(86400) == "24 小时 0 分钟")
        #expect(SystemMetrics.uptime(86401) == "24 小时 0 分钟")
        // 24 小时 59 秒：秒被丢掉，但分钟照常显示
        #expect(SystemMetrics.uptime(86459) == "24 小时 0 分钟")
        // 24 小时 59 分 59 秒仍在小时分支里，分钟是 59 而不是进位成 1 天
        #expect(SystemMetrics.uptime(89999) == "24 小时 59 分钟")
    }

    @Test("超过 24 小时后切成天 + 小时，不再显示分钟")
    func beyondOneDaySwitchesToDays() {
        #expect(SystemMetrics.uptime(90000) == "1 天 1 小时")  // 25 小时
        #expect(SystemMetrics.uptime(90060) == "1 天 1 小时")  // 25 小时 1 分
        #expect(SystemMetrics.uptime(172799) == "1 天 23 小时")  // 47 小时 59 分
        #expect(SystemMetrics.uptime(172800) == "2 天 0 小时")
        #expect(SystemMetrics.uptime(31536000) == "365 天 0 小时")
    }

    @Test("负值走同一条分支，结果如实反映负小时")
    func negativeSeconds() {
        // 没有做非负校验：-1 秒被截断成 0，-25 小时则原样显示
        #expect(SystemMetrics.uptime(-1) == "0 小时 0 分钟")
        #expect(SystemMetrics.uptime(-90000) == "-25 小时 0 分钟")
    }
}

@Suite("内存容量格式化")
struct SystemMetricsBytesTests {

    @Test("零与不足半个刻度都显示 0.0 GB")
    func zeroAndTinyValues() {
        #expect(SystemMetrics.bytes(0) == "0.0 GB")
        #expect(SystemMetrics.bytes(1) == "0.0 GB")
        #expect(SystemMetrics.bytes(1023) == "0.0 GB")
        // 1023/1024 的进位发生在 1 GiB 上，而不是 1000 上
        #expect(SystemMetrics.bytes(1024) == "0.0 GB")
    }

    @Test("1 GiB 正好是 1.0 GB")
    func oneGigabyte() {
        #expect(SystemMetrics.bytes(1_073_741_824) == "1.0 GB")
        #expect(SystemMetrics.bytes(536_870_912) == "0.5 GB")
        #expect(SystemMetrics.bytes(1_610_612_736) == "1.5 GB")
        #expect(SystemMetrics.bytes(10_737_418_240) == "10.0 GB")
    }

    @Test("保留一位小数，超过一位的按四舍五入")
    func roundingToOneDecimal() {
        // 2.1 GiB
        #expect(SystemMetrics.bytes(2_254_857_830) == "2.1 GB")
        // 1.1 GiB
        #expect(SystemMetrics.bytes(1_181_116_006) == "1.1 GB")
        // 标的是 GB 但按 1024 换算，所以 1 TiB 会显示成 1024.0 GB
        #expect(SystemMetrics.bytes(1_099_511_627_776) == "1024.0 GB")
    }

    @Test("常见机型的总内存")
    func typicalMachineSizes() {
        #expect(SystemMetrics.bytes(8_589_934_592) == "8.0 GB")  // 8 GiB
        #expect(SystemMetrics.bytes(17_179_869_184) == "16.0 GB")  // 16 GiB
        #expect(SystemMetrics.bytes(2_147_483_648) == "2.0 GB")  // 2 GiB
    }

    @Test("负值与 Int64 上界不做保护")
    func extremesAreNotClamped() {
        #expect(SystemMetrics.bytes(-1_073_741_824) == "-1.0 GB")
        #expect(SystemMetrics.bytes(Int64.max) == "8589934592.0 GB")
    }
}

@Suite("ps 输出解析")
struct ProcessListingTests {

    @Test("命令契约固定")
    func commandContract() {
        #expect(ProcessListing.commandPath == "/bin/ps")
        #expect(ProcessListing.commandArguments == ["-eo", "pid,pcpu,pmem,comm", "-r"])
        #expect(ProcessListing.maximumCount == 50)
    }

    @Test("表头被丢掉，其余行按 pid/占用/名字解析")
    func parsesRowsAndDropsHeader() {
        let output = """
              PID  %CPU %MEM COMM
                1   0.0  0.1 /sbin/launchd
              532   1.5  2.3 /System/Library/CoreServices/Finder.app/Contents/MacOS/Finder
              900  12.5  8.0 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
            """

        #expect(
            ProcessListing.parse(output) == [
                ProcessEntry(id: 1, name: "launchd", cpuUsage: "0.0%", memoryUsage: "0.1%"),
                ProcessEntry(id: 532, name: "Finder", cpuUsage: "1.5%", memoryUsage: "2.3%"),
                ProcessEntry(
                    id: 900, name: "Google Chrome", cpuUsage: "12.5%", memoryUsage: "8.0%")
            ])
    }

    @Test("空输出只剩表头时结果为空")
    func emptyOutput() {
        #expect(ProcessListing.parse("").isEmpty)
        #expect(ProcessListing.parse("  PID %CPU %MEM COMM").isEmpty)
        #expect(ProcessListing.parse("  PID %CPU %MEM COMM\n").isEmpty)
    }

    @Test("不足四列的行被丢弃")
    func shortRowsAreDropped() {
        // 后半段的空格会被 filter 掉，所以「看起来够长」但只有 3 个字段的行同样无效
        let output = """
              PID %CPU %MEM COMM
              42  1.0  /bin/sh
              43  1.0  2.0
              44
              45  1.0  2.0  /bin/zsh
            """

        #expect(
            ProcessListing.parse(output) == [
                ProcessEntry(id: 45, name: "zsh", cpuUsage: "1.0%", memoryUsage: "2.0%")
            ])
    }

    @Test("pid 不是整数的行被丢弃，超范围也丢弃")
    func nonNumericPIDIsDropped() {
        let output = """
              PID %CPU %MEM COMM
              abc 1.0  2.0  /bin/sh
            99999999999 1.0 2.0 /bin/overflow
               1.5 1.0  2.0  /bin/float
              100  1.0  2.0  /bin/ok
            """

        #expect(
            ProcessListing.parse(output) == [
                ProcessEntry(id: 100, name: "ok", cpuUsage: "1.0%", memoryUsage: "2.0%")
            ])
    }

    @Test("CPU 与内存字段不做数值校验，原样带百分号")
    func usageFieldsAreNotValidated() {
        let output = """
              PID %CPU %MEM COMM
               77  abc  xyz  /bin/odd
            """

        #expect(
            ProcessListing.parse(output) == [
                ProcessEntry(id: 77, name: "odd", cpuUsage: "abc%", memoryUsage: "xyz%")
            ])
    }

    @Test("只保留前 50 行，丢弃非法行发生在截断之后")
    func maximumCountAppliesBeforeFiltering() {
        var lines = ["  PID %CPU %MEM COMM"]
        lines.append(contentsOf: (1...49).map { "\($0) 1.0 2.0 /bin/p\($0)" })
        // 第 50 行是非法行：它占掉一个名额，所以最终只有 49 条
        lines.append("bad row")
        lines.append(contentsOf: (100...110).map { "\($0) 1.0 2.0 /bin/p\($0)" })

        let entries = ProcessListing.parse(lines.joined(separator: "\n"))

        #expect(entries.count == 49)
        #expect(entries.first?.id == 1)
        #expect(entries.last?.id == 49)
    }

    @Test("超过 50 条时只保留前 50 条，顺序不变")
    func truncatesToFiftyPreservingOrder() {
        var lines = ["  PID %CPU %MEM COMM"]
        lines.append(contentsOf: (1...60).map { "\($0) 1.0 2.0 /bin/p\($0)" })

        let entries = ProcessListing.parse(lines.joined(separator: "\n"))

        #expect(entries.count == 50)
        #expect(entries.map(\.id) == Array(1...50).map { Int32($0) })
    }

    @Test("空行与纯空白行被跳过")
    func blankLinesAreSkipped() {
        let output = "  PID %CPU %MEM COMM\n\n   \n  7 1.0 2.0 /bin/a\n"

        #expect(
            ProcessListing.parse(output) == [
                ProcessEntry(id: 7, name: "a", cpuUsage: "1.0%", memoryUsage: "2.0%")
            ])
    }

    @Test("带空格的可执行路径只取文件名，负 pid 不拦截")
    func nameIsLastPathComponentAndPIDMayBeNegative() {
        let output = """
              PID %CPU %MEM COMM
               -5 0.0 0.1 /usr/libexec/some helper agent
            """

        // `Int32("-5")` 合法，代码没有非负校验；名字里的空格先拼回再取最后一段路径
        #expect(
            ProcessListing.parse(output) == [
                ProcessEntry(
                    id: -5, name: "some helper agent", cpuUsage: "0.0%", memoryUsage: "0.1%")
            ])
    }
}

@Suite("系统监控插件契约")
@MainActor
struct SystemMonitorPluginTests {

    @Test("插件 id 是 kebab-case 且等于约定值")
    func identifierIsKebabCase() {
        let id = SystemMonitorPlugin.id

        #expect(id == "sysmonitor")
        #expect(id == id.lowercased())
        #expect(id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" })
        #expect(!id.hasPrefix("-") && !id.hasSuffix("-") && !id.contains("--"))
    }

    @Test("名称、图标、触发词齐备")
    func metadataIsComplete() {
        #expect(SystemMonitorPlugin.name == "系统监控")
        #expect(SystemMonitorPlugin.icon == "cpu")
        #expect(
            SystemMonitorPlugin.triggerWords
                == ["进程", "系统信息", "系统监控", "process", "monitor", "端口", "port", "cpu", "内存"])
        #expect(SystemMonitorPlugin.triggerWords.allSatisfy { !$0.isEmpty })
    }

    @Test("命中触发词时只返回一条入口结果")
    func triggerWordYieldsSingleEntry() async throws {
        let plugin = SystemMonitorPlugin()
        let results = await plugin.searchItems(query: "进程")

        #expect(results.count == 1)
        let item = try #require(results.first)
        #expect(item.id == "sysmonitor.overview")
        #expect(item.pluginID == SystemMonitorPlugin.id)
        #expect(item.relevance == 0.6)
        #expect(!item.title.isEmpty)
    }

    @Test("拉丁触发词按整词匹配：export / support 不命中 port")
    func latinTriggersMatchWholeWordsOnly() async {
        let plugin = SystemMonitorPlugin()

        // 用 contains 的话这三个都会误命中，注释里点名的就是这件事
        #expect(await plugin.searchItems(query: "export").isEmpty)
        #expect(await plugin.searchItems(query: "support").isEmpty)
        #expect(await plugin.searchItems(query: "memory").isEmpty)
        // 整词仍然命中
        #expect(await plugin.searchItems(query: "process").count == 1)
        #expect(await plugin.searchItems(query: "monitor").count == 1)
    }

    @Test("中文触发词按前缀匹配")
    func chineseTriggersMatchByPrefix() async {
        let plugin = SystemMonitorPlugin()

        #expect(await plugin.searchItems(query: "系统信息").count == 1)
        #expect(await plugin.searchItems(query: "内存").count == 1)
    }

    @Test("无关查询与空查询不返回结果")
    func unrelatedQueryYieldsNothing() async {
        let plugin = SystemMonitorPlugin()

        #expect(await plugin.searchItems(query: "").isEmpty)
        #expect(await plugin.searchItems(query: "天气").isEmpty)
        #expect(await plugin.searchItems(query: "screenshot").isEmpty)
    }
}
