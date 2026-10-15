// AppDirectoryWatcherTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Testing

@testable import QuickPlatform

@Suite("应用程序目录监听器测试")
struct AppDirectoryWatcherTests {

    @Test("应用目录新增文件触发防抖回调")
    func directoryChangeTriggersDebouncedCallback() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("quick_watch_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let expectation = ManagedAtomicFlag()

        let watcher = AppDirectoryWatcher(
            paths: [tempDir.path],
            debounceInterval: 0.1
        ) {
            expectation.set()
        }
        defer { watcher.stop() }

        // 等待监听器就绪
        try await Task.sleep(nanoseconds: 50_000_000)

        // 模拟目录新增文件
        let testFile = tempDir.appendingPathComponent("TestApp.app")
        try "dummy".write(to: testFile, atomically: true, encoding: .utf8)

        // 轮询等待防抖回调：固定睡眠在全量测试并行、机器繁忙时会偶发超时，
        // 轮询既不拖慢正常路径，也给了繁忙时足够的余量（上限 3 秒）。
        for _ in 0..<60 where !expectation.isSet {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(expectation.isSet)
    }

    @Test("AppIndex 通过 checkAndRefreshIfNeeded 检测到目录修改并刷新")
    @MainActor
    func appIndexDetectsMtimeChangeAndRefreshes() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("quick_appindex_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // 创建第一个测试 App 结构
        let app1 = tempDir.appendingPathComponent("AppOne.app")
        let app1Contents = app1.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: app1Contents, withIntermediateDirectories: true)
        let infoPlist1: [String: Any] = [
            "CFBundleIdentifier": "com.test.appone",
            "CFBundleDisplayName": "App One",
            "CFBundlePackageType": "APPL",
        ]
        let plistData1 = try PropertyListSerialization.data(fromPropertyList: infoPlist1, format: .xml, options: 0)
        try plistData1.write(to: app1Contents.appendingPathComponent("Info.plist"))

        let index = AppIndex(scopes: [tempDir.path], autoWatch: false)
        await index.refresh()
        #expect(index.apps.count == 1)
        #expect(index.apps.first?.name == "App One")

        // 稍微等待确保 mtime 时间戳前进
        try await Task.sleep(nanoseconds: 1_100_000_000)

        // 模拟用户新装了第二个 App
        let app2 = tempDir.appendingPathComponent("AppTwo.app")
        let app2Contents = app2.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: app2Contents, withIntermediateDirectories: true)
        let infoPlist2: [String: Any] = [
            "CFBundleIdentifier": "com.test.apptwo",
            "CFBundleDisplayName": "App Two",
            "CFBundlePackageType": "APPL",
        ]
        let plistData2 = try PropertyListSerialization.data(fromPropertyList: infoPlist2, format: .xml, options: 0)
        try plistData2.write(to: app2Contents.appendingPathComponent("Info.plist"))

        // 在未主动 refresh 的情况下，调用 checkAndRefreshIfNeeded
        await index.checkAndRefreshIfNeeded()

        #expect(index.apps.count == 2)
        let names = Set(index.apps.map(\.name))
        #expect(names.contains("App One"))
        #expect(names.contains("App Two"))
    }
}

/// 线程安全的简单原子布尔标记
private final class ManagedAtomicFlag: @unchecked Sendable {
    private var flag = false
    private let lock = NSLock()

    func set() {
        lock.lock()
        defer { lock.unlock() }
        flag = true
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }
}
