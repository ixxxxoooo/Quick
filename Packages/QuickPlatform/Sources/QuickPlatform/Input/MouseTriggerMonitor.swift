// MouseTriggerMonitor.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import ApplicationServices
import CoreGraphics
import Foundation
import QuickCore

/// 鼠标触发种类（对齐 Fasty 超级面板）
public enum MouseTriggerKind: Sendable {
    /// 右键长按达到阈值
    case rightLongPress
    /// 中键（滚轮键）单击
    case middleClick
}

/// 全局鼠标触发监听（右键长按 / 中键单击）
///
/// 对齐 Fasty `mouse_listener.rs`：
/// - `CGEventTap` 主动模式优先（可吞掉事件，保护划词选中、阻止右键菜单）
/// - 失败则降级为 listen-only（仍能触发，但无法拦截）
/// - 右键移动超过约 20pt 取消长按
/// - 中键触发时吞掉 down/up，避免宿主取消文本选中
///
/// 需要**辅助功能权限**才能创建 event tap。本类型不认识任何插件，只回调 `onTrigger`。
public final class MouseTriggerMonitor: @unchecked Sendable {

    /// 运行时配置（可热更新）
    public struct Configuration: Sendable, Equatable {
        public var rightLongPressEnabled: Bool
        public var middleClickEnabled: Bool
        /// 右键长按阈值（毫秒），夹紧到 50…1500；中键不受此限制
        public var thresholdMilliseconds: UInt64

        public init(
            rightLongPressEnabled: Bool = true,
            middleClickEnabled: Bool = true,
            thresholdMilliseconds: UInt64 = 450
        ) {
            self.rightLongPressEnabled = rightLongPressEnabled
            self.middleClickEnabled = middleClickEnabled
            self.thresholdMilliseconds = Self.clampedThreshold(thresholdMilliseconds)
        }

        public var needsListening: Bool {
            rightLongPressEnabled || middleClickEnabled
        }

        /// 将阈值夹紧到合法区间
        public static func clampedThreshold(_ ms: UInt64) -> UInt64 {
            min(1500, max(50, ms))
        }
    }

    /// 触发回调（可能来自后台线程，调用方自行 hop 到主线程）
    public var onTrigger: (@Sendable (MouseTriggerKind) -> Void)?

    private let log = QuickLog.platform
    private let lock = NSLock()
    private var configuration = Configuration()

    private var isRunning = false
    private var tapThread: Thread?
    private var runLoop: CFRunLoop?
    private var eventTap: CFMachPort?
    private var longPressTimer: DispatchSourceTimer?

    // 右键状态
    private var rightButtonDown = false
    private var rightDownTimeMs: UInt64 = 0
    private var rightDownX: CGFloat = 0
    private var rightDownY: CGFloat = 0
    private var rightLongPressFired = false
    private var middleClickFired = false

    /// 微动取消阈值的平方（20pt）
    private static let moveCancelThresholdSquared: CGFloat = 400

    public init() {}

    /// 当前配置快照
    public var currentConfiguration: Configuration {
        lock.lock()
        defer { lock.unlock() }
        return configuration
    }

    /// 是否正在监听
    public var running: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRunning
    }

    /// 热更新配置；若两边都关则停止，有任意一边开则确保在跑
    public func apply(_ configuration: Configuration) {
        let next = Configuration(
            rightLongPressEnabled: configuration.rightLongPressEnabled,
            middleClickEnabled: configuration.middleClickEnabled,
            thresholdMilliseconds: configuration.thresholdMilliseconds
        )
        lock.lock()
        self.configuration = next
        let shouldRun = next.needsListening
        let currentlyRunning = isRunning
        lock.unlock()

        if shouldRun {
            if !currentlyRunning {
                start()
            }
        } else if currentlyRunning {
            stop()
        }
    }

    /// 启动监听（幂等）
    public func start() {
        lock.lock()
        guard !isRunning else {
            lock.unlock()
            return
        }
        guard configuration.needsListening else {
            lock.unlock()
            log.debug("鼠标触发未启用，跳过启动")
            return
        }
        isRunning = true
        lock.unlock()

        guard AXIsProcessTrusted() else {
            lock.lock()
            isRunning = false
            lock.unlock()
            log.warning("鼠标触发需要辅助功能权限，CGEventTap 未创建")
            return
        }

        let thread = Thread { [weak self] in
            self?.runEventTapLoop()
        }
        thread.name = "quick.mouse-trigger"
        thread.qualityOfService = .userInteractive
        lock.lock()
        tapThread = thread
        lock.unlock()
        thread.start()

        startLongPressTimer()
        log.notice("鼠标触发监听已启动（右键长按 / 中键）")
    }

    /// 停止监听（幂等）
    public func stop() {
        lock.lock()
        guard isRunning else {
            lock.unlock()
            return
        }
        isRunning = false
        let loop = runLoop
        lock.unlock()

        longPressTimer?.cancel()
        longPressTimer = nil

        if let loop {
            CFRunLoopStop(loop)
        }

        lock.lock()
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        runLoop = nil
        tapThread = nil
        rightButtonDown = false
        rightLongPressFired = false
        middleClickFired = false
        lock.unlock()

        log.notice("鼠标触发监听已停止")
    }

    // MARK: - Event tap

    private func runEventTapLoop() {
        let mask: CGEventMask =
            (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.rightMouseUp.rawValue)
            | (1 << CGEventType.mouseMoved.rawValue)
            | (1 << CGEventType.rightMouseDragged.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.otherMouseUp.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        var tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: mouseTriggerTapCallback,
            userInfo: refcon
        )

        if tap == nil {
            log.warning("DEFAULT 模式创建 CGEventTap 失败，降级 LISTEN_ONLY")
            tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: mouseTriggerTapCallback,
                userInfo: refcon
            )
        }

        guard let tap else {
            log.error("创建 CGEventTap 失败（请检查辅助功能权限）")
            lock.lock()
            isRunning = false
            lock.unlock()
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            log.error("创建 CFRunLoopSource 失败")
            lock.lock()
            isRunning = false
            lock.unlock()
            return
        }

        let loop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(loop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        lock.lock()
        eventTap = tap
        runLoop = loop
        lock.unlock()

        CFRunLoopRun()

        CFRunLoopRemoveSource(loop, source, .commonModes)
        lock.lock()
        eventTap = nil
        runLoop = nil
        isRunning = false
        lock.unlock()
    }

    fileprivate func handleTap(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // 系统挂起后重新启用
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let tap = eventTap
            lock.unlock()
            if let tap {
                log.warning("CGEventTap 被系统挂起，正在重新启用")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let location = event.location

        lock.lock()
        let config = configuration
        lock.unlock()

        switch type {
        case .rightMouseDown:
            guard config.rightLongPressEnabled else {
                return Unmanaged.passUnretained(event)
            }
            lock.lock()
            rightDownX = location.x
            rightDownY = location.y
            rightDownTimeMs = Self.nowMilliseconds()
            rightButtonDown = true
            rightLongPressFired = false
            lock.unlock()

        case .rightMouseUp:
            lock.lock()
            let shouldSwallow = rightLongPressFired
            rightButtonDown = false
            rightLongPressFired = false
            lock.unlock()
            if shouldSwallow {
                log.debug("拦截 rightMouseUp（长按已触发超级面板）")
                return nil
            }

        case .mouseMoved, .rightMouseDragged:
            lock.lock()
            if rightButtonDown {
                let dx = location.x - rightDownX
                let dy = location.y - rightDownY
                if dx * dx + dy * dy > Self.moveCancelThresholdSquared {
                    rightButtonDown = false
                    rightLongPressFired = false
                }
            }
            lock.unlock()

        case .otherMouseDown:
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            if button == 2, config.middleClickEnabled {
                lock.lock()
                middleClickFired = true
                lock.unlock()
                log.notice("鼠标中键触发超级面板")
                fire(.middleClick)
                return nil
            }

        case .otherMouseUp:
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            if button == 2 {
                lock.lock()
                let shouldSwallow = middleClickFired
                middleClickFired = false
                lock.unlock()
                if shouldSwallow {
                    log.debug("拦截 otherMouseUp（中键已触发）")
                    return nil
                }
            }

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Long press timer

    private func startLongPressTimer() {
        longPressTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: .milliseconds(20))
        timer.setEventHandler { [weak self] in
            self?.pollLongPress()
        }
        longPressTimer = timer
        timer.resume()
    }

    private func pollLongPress() {
        lock.lock()
        let config = configuration
        let down = rightButtonDown
        let fired = rightLongPressFired
        let downTimeMs = rightDownTimeMs
        let threshold = config.thresholdMilliseconds
        let enabled = config.rightLongPressEnabled
        lock.unlock()

        guard enabled, down, !fired, downTimeMs > 0 else { return }

        let elapsedMs = Self.nowMilliseconds().saturatingSubtraction(downTimeMs)
        if elapsedMs >= threshold {
            lock.lock()
            rightLongPressFired = true
            lock.unlock()
            log.notice("右键长按触发超级面板（\(elapsedMs)ms）")
            fire(.rightLongPress)
        }
    }

    private func fire(_ kind: MouseTriggerKind) {
        onTrigger?(kind)
    }

    private static func nowMilliseconds() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1000)
    }
}

extension UInt64 {
    fileprivate func saturatingSubtraction(_ other: UInt64) -> UInt64 {
        self > other ? self - other : 0
    }
}

/// CGEventTap 回调（必须是全局函数）
private func mouseTriggerTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else {
        return Unmanaged.passUnretained(event)
    }
    let monitor = Unmanaged<MouseTriggerMonitor>.fromOpaque(refcon).takeUnretainedValue()
    return monitor.handleTap(type: type, event: event)
}
