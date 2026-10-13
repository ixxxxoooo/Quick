// IconCacheTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Testing

@testable import QuickPlatform

@MainActor
@Suite("图标缓存")
struct IconCacheTests {

    @Test("未加载过时 cachedIcon 不读磁盘，返回 nil")
    func cachedIconMissDoesNotLoad() {
        let cache = IconCache()
        #expect(cache.cachedIcon(forBundlePath: "/System/Applications/Calculator.app") == nil)
    }

    @Test("icon 加载后 cachedIcon 命中同一个对象")
    func loadThenHit() throws {
        let cache = IconCache()
        let path = "/System/Applications/Calculator.app"
        let loaded = try #require(cache.icon(forBundlePath: path))
        #expect(cache.cachedIcon(forBundlePath: path) === loaded)
    }

    @Test("重复读取同一路径拿到的是缓存里的同一份")
    func repeatedReadsShareTheInstance() throws {
        let cache = IconCache()
        let path = "/System/Applications/Calculator.app"
        let first = try #require(cache.icon(forBundlePath: path))
        let second = try #require(cache.icon(forBundlePath: path))
        #expect(first === second)
    }
}
