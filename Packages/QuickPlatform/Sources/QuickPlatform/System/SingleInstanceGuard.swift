// SingleInstanceGuard.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Darwin
import Foundation
import QuickCore

/// 单实例进程看门狗
///
/// 遵循 macOS 业界标准单实例应用方案（flock 内核级文件锁 + NSRunningApplication / DistributedNotificationCenter 跨进程协同）：
/// 1. 使用内核文件锁（`flock`）保证原子性互斥，杜绝竞态与重复启动；进程意外退出或崩溃时内核自动释放锁，无死锁与残留孤儿锁问题；
/// 2. 当检测到已有实例在运行，将已有实例激活并通知其唤出面板，随后次级进程立即静默退出；
/// 3. 安装 SIGTERM / SIGINT 信号监听，在被脚本或系统退出时优雅清理 NSStatusItem 托盘图标，防止菜单栏残留幽灵图标。
@MainActor
public final class SingleInstanceGuard {

    public static let shared = SingleInstanceGuard()

    private let log = QuickLog.platform
    private var lockFileDescriptor: Int32 = -1
    private var sigtermSource: (any DispatchSourceSignal)?
    private var sigintSource: (any DispatchSourceSignal)?

    /// 分布式唤醒通知名
    public static var wakeUpNotificationName: Notification.Name {
        Notification.Name("\(AppIdentity.bundleIdentifier).wakeUp")
    }

    private init() {}

    /// 尝试作为主实例获取排他锁；若已有实例运行，唤起旧实例后退出当前进程
    ///
    /// - Parameters:
    ///   - customLockURL: 可选自定义锁文件路径（单元测试用）
    ///   - launchArguments: 启动参数（用于转发给已有实例）
    /// - Returns: 是否作为主实例成功获取独占锁
    @discardableResult
    public func ensureSingleInstance(
        customLockURL: URL? = nil,
        launchArguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        let lockURL = customLockURL ?? AppPaths.applicationSupport().appendingPathComponent("instance.lock")
        let lockPath = lockURL.path(percentEncoded: false)

        let fd = open(lockPath, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else {
            log.error("无法打开单实例锁文件：\(lockPath, privacy: .public), errno=\(errno)")
            return true
        }

        // 尝试非阻塞排他锁
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            let errorNumber = errno
            close(fd)
            // macOS 上 EWOULDBLOCK 与 EAGAIN 是同一个值，写两个会让编译器报「永不执行」
            if errorNumber == EWOULDBLOCK {
                log.notice("检测到已有 Quick 实例在运行，转发唤起信号并退出次级进程")
                // `Never` 返回：这里不会再往下走，所以不写 `return false`
                notifyExistingInstanceAndExit(launchArguments: launchArguments)
            } else {
                log.error("flock 失败，errno=\(errorNumber)")
                return true
            }
        }

        // 成功获取锁：记录文件描述符并写入当前 PID
        self.lockFileDescriptor = fd
        let currentPID = ProcessInfo.processInfo.processIdentifier
        ftruncate(fd, 0)
        let pidString = "\(currentPID)\n"
        _ = pidString.withCString { ptr in
            write(fd, ptr, strlen(ptr))
        }

        log.notice("单实例锁获取成功，PID=\(currentPID, privacy: .public)")
        return true
    }

    /// 唤醒已有实例并退出当前进程
    private func notifyExistingInstanceAndExit(launchArguments: [String]) -> Never {
        let bundleID = AppIdentity.bundleIdentifier
        let currentPID = ProcessInfo.processInfo.processIdentifier

        // 1. 激活已有应用实例
        let otherApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != currentPID }

        if let existing = otherApps.first {
            existing.activate()
        }

        // 2. 发送分布式唤醒通知（让主实例显示面板）
        DistributedNotificationCenter.default().postNotificationName(
            Self.wakeUpNotificationName,
            object: nil,
            userInfo: ["arguments": launchArguments],
            deliverImmediately: true
        )

        // 3. 同时兼容原有的 com.ixxxxoooo.quick.togglePalette 通知
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.ixxxxoooo.quick.togglePalette"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )

        exit(0)
    }

    /// 安装 SIGTERM / SIGINT 信号监听，支持优雅终止（清理菜单栏托盘图标）
    public func installSignalHandlers(onTerminate: @escaping @MainActor () -> Void) {
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)

        let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termSource.setEventHandler { [weak self] in
            self?.log.notice("收到 SIGTERM 信号，执行清理并退出")
            onTerminate()
            self?.releaseLock()
            exit(0)
        }
        termSource.resume()
        self.sigtermSource = termSource

        let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        intSource.setEventHandler { [weak self] in
            self?.log.notice("收到 SIGINT 信号，执行清理并退出")
            onTerminate()
            self?.releaseLock()
            exit(0)
        }
        intSource.resume()
        self.sigintSource = intSource
    }

    /// 释放锁文件描述符
    public func releaseLock() {
        if lockFileDescriptor >= 0 {
            flock(lockFileDescriptor, LOCK_UN)
            close(lockFileDescriptor)
            lockFileDescriptor = -1
        }
    }

    deinit {
        if lockFileDescriptor >= 0 {
            close(lockFileDescriptor)
        }
    }
}
