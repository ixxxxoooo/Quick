// SettingsBackupTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import QuickPlatform

@Suite("设置备份")
struct SettingsBackupTests {

    private let exportedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private func roundTrip(_ domain: [String: Any]) throws -> SettingsBackup.ImportPlan {
        try SettingsBackup.parse(SettingsBackup.export(domain: domain, exportedAt: exportedAt))
    }

    @Test("导出不带系统与框架写进同一个域的键")
    func exportSkipsSystemKeys() throws {
        let plan = try roundTrip([
            "quick.global.appearance": "dark",
            "NSWindow Frame Settings": "1 2 3 4",
            "AppleLanguages": ["zh-Hans"],
            "com.apple.finder.x": 1
        ])
        #expect(Set(plan.values.keys) == ["quick.global.appearance"])
    }

    @Test("Bool / Int / Double / Data / 数组 / 字典往返后类型不变")
    func typesSurviveRoundTrip() throws {
        let blob = Data([1, 2, 3])
        let plan = try roundTrip([
            "a.bool": true,
            "a.int": 5,
            "a.double": 5.0,
            "a.string": "你好",
            "a.data": blob,
            "a.array": ["x", "y"],
            "a.dict": ["k": 1]
        ])
        #expect(plan.values["a.bool"] == .bool(true))
        #expect(plan.values["a.int"] == .integer(5))
        #expect(plan.values["a.double"] == .double(5.0))
        #expect(plan.values["a.string"] == .string("你好"))
        #expect(plan.values["a.data"] == .data(blob))
        #expect(plan.values["a.array"] == .array([.string("x"), .string("y")]))
        #expect(plan.values["a.dict"] == .dictionary(["k": .integer(1)]))
        #expect(plan.exportedAt == exportedAt)
    }

    @Test("Bool 与整数 0 / 1 不会混淆")
    func boolIsNotInteger() throws {
        let plan = try roundTrip(["x.flag": false, "x.zero": 0, "x.one": 1])
        #expect(plan.values["x.flag"] == .bool(false))
        #expect(plan.values["x.zero"] == .integer(0))
        #expect(plan.values["x.one"] == .integer(1))
    }

    @Test("导入不信任文件：被塞进去的系统键会被丢弃并计数")
    func importDropsForeignKeys() throws {
        let tampered: [String: Any] = [
            "format": SettingsBackup.formatIdentifier,
            "version": 1,
            "values": ["quick.ok": 1, "AppleLanguages": ["en"], "NSNavPanelExpandedStateForSaveMode": true]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: tampered, format: .xml, options: 0)
        let plan = try SettingsBackup.parse(data)
        #expect(Set(plan.values.keys) == ["quick.ok"])
        #expect(plan.skipped == 2)
    }

    @Test("超长键名被丢弃")
    func overlongKeyIsRejected() {
        #expect(!SettingsBackup.isPortable(key: String(repeating: "k", count: 201)))
        #expect(SettingsBackup.isPortable(key: String(repeating: "k", count: 200)))
        #expect(!SettingsBackup.isPortable(key: ""))
    }

    @Test("不是备份的文件被拒绝，不会崩")
    func garbageIsRejected() {
        for data in [Data(), Data("hello".utf8), Data("{\"a\":1}".utf8)] {
            #expect(throws: SettingsBackup.Failure.notABackup) { try SettingsBackup.parse(data) }
        }
        // 合法 plist 但不是 Quick 的格式
        let other = try? PropertyListSerialization.data(
            fromPropertyList: ["format": "other", "values": [String: Any]()], format: .xml, options: 0)
        #expect(throws: SettingsBackup.Failure.notABackup) { try SettingsBackup.parse(other ?? Data()) }
    }

    @Test("更高版本的备份被明确拒绝")
    func newerVersionIsRejected() throws {
        let doc: [String: Any] = [
            "format": SettingsBackup.formatIdentifier, "version": 99, "values": [String: Any]()
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: doc, format: .xml, options: 0)
        #expect(throws: SettingsBackup.Failure.unsupportedVersion(99)) { try SettingsBackup.parse(data) }
    }

    @Test("缺版本号视为不是备份")
    func missingVersionIsRejected() throws {
        let doc: [String: Any] = ["format": SettingsBackup.formatIdentifier, "values": [String: Any]()]
        let data = try PropertyListSerialization.data(fromPropertyList: doc, format: .xml, options: 0)
        #expect(throws: SettingsBackup.Failure.notABackup) { try SettingsBackup.parse(data) }
    }

    @Test("超过体积上限直接拒绝")
    func oversizedFileIsRejected() {
        let big = Data(count: SettingsBackup.maximumFileSize + 1)
        #expect(throws: SettingsBackup.Failure.tooLarge) { try SettingsBackup.parse(big) }
    }

    @Test("导入的值可以还原成 UserDefaults 能存的类型")
    func anyValueRestoresPlistTypes() throws {
        let suite = "SettingsBackupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let plan = try roundTrip(["t.flag": true, "t.count": 7, "t.list": ["a"]])
        for (key, value) in plan.values { defaults.set(value.anyValue, forKey: key) }
        #expect(defaults.bool(forKey: "t.flag"))
        #expect(defaults.integer(forKey: "t.count") == 7)
        #expect(defaults.stringArray(forKey: "t.list") == ["a"])
    }
}
