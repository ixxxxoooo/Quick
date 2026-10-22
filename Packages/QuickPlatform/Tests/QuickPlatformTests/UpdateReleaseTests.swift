// UpdateReleaseTests.swift
// @author ixxxxoooo

import Foundation
import Testing

@testable import QuickPlatform

@Suite("UpdateRelease")
struct UpdateReleaseTests {

    @Test("版本比较按数字段而非字典序")
    func compare() {
        #expect(UpdateRelease.isNewer("1.10.0", than: "1.9.9"))
        #expect(UpdateRelease.isNewer("1.2", than: "1.1.9"))
        #expect(!UpdateRelease.isNewer("1.1.1", than: "1.1.1"))
        #expect(!UpdateRelease.isNewer("1.1.0", than: "1.1.1"))
        #expect(!UpdateRelease.isNewer("beta", than: "1.0"))
    }

    @Test("解析 release JSON，去掉 v 前缀并只接受 github.com 的 DMG")
    func parse() {
        let ok = """
            {"tag_name":"v1.2.0","body":"notes","assets":[{"name":"Quick-1.2.0.dmg",
            "browser_download_url":"https://github.com/x/y/releases/download/v1.2.0/Quick-1.2.0.dmg"}]}
            """
        #expect(UpdateRelease.parse(Data(ok.utf8))?.version == "1.2.0")
        let evil = ok.replacingOccurrences(of: "github.com", with: "evil.example")
        #expect(UpdateRelease.parse(Data(evil.utf8)) == nil)
        #expect(UpdateRelease.parse(Data("{}".utf8)) == nil)
    }
}
