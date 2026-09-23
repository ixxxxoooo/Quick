// PasteServiceTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Testing

@testable import QuickPlatform

@Suite("PasteService")
@MainActor
struct PasteServiceTests {

    @Test("canSynthesize 与 paste 在无辅助功能权限时一致返回 false")
    func pasteFailsWithoutAccessibility() {
        let service = PasteService()
        if service.canSynthesize {
            #expect(service.paste())
        } else {
            #expect(!service.paste())
        }
    }
}
