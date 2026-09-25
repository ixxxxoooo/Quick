// SingleInstanceGuardTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Darwin
import Foundation
import Testing

@testable import QuickPlatform

@Suite("单实例看门狗测试")
@MainActor
struct SingleInstanceGuardTests {

    @Test("首次获取单实例锁成功，文件写入有效 PID")
    func acquireLockSuccess() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let lockURL = tempDir.appendingPathComponent("quick_test_\(UUID().uuidString).lock")
        defer {
            try? FileManager.default.removeItem(at: lockURL)
        }

        let guardInstance = SingleInstanceGuard.shared
        defer {
            guardInstance.releaseLock()
        }

        let success = guardInstance.ensureSingleInstance(customLockURL: lockURL)
        #expect(success)

        // 验证锁文件存在且包含当前进程 PID
        let content = try String(contentsOf: lockURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedPID = String(ProcessInfo.processInfo.processIdentifier)
        #expect(content == expectedPID)

        // 尝试通过独立句柄对同一文件加锁，必然被阻塞 (EWOULDBLOCK / EAGAIN)
        let secondFD = open(lockURL.path(percentEncoded: false), O_CREAT | O_RDWR, 0o600)
        #expect(secondFD >= 0)
        let secondLock = flock(secondFD, LOCK_EX | LOCK_NB)
        #expect(secondLock != 0)
        #expect(errno == EWOULDBLOCK || errno == EAGAIN)
        close(secondFD)

        // 释放锁后，其他文件描述符应可获取锁
        guardInstance.releaseLock()
        let thirdFD = open(lockURL.path(percentEncoded: false), O_CREAT | O_RDWR, 0o600)
        #expect(thirdFD >= 0)
        let thirdLock = flock(thirdFD, LOCK_EX | LOCK_NB)
        #expect(thirdLock == 0)
        flock(thirdFD, LOCK_UN)
        close(thirdFD)
    }

    @Test("唤醒通知名称包含 AppIdentity bundleIdentifier")
    func wakeUpNotificationNameFormat() {
        let name = SingleInstanceGuard.wakeUpNotificationName.rawValue
        #expect(name.contains("wakeUp"))
        #expect(name.hasPrefix(AppIdentity.bundleIdentifier))
    }
}
