// HotKeyService.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Carbon.HIToolbox
import QuickCore

/// 全局快捷键服务
///
/// 使用 Carbon HotKey API 注册系统级全局快捷键。
/// 默认注册 ⌥Space 唤醒面板，支持用户自定义。
@MainActor
public final class HotKeyService {

    /// 默认组合键的可读描述
    ///
    /// 目前只注册这一个固定组合键，所以是常量。设置界面与日志都用它，
    /// 免得同一件事在三个地方各写一遍字符串。
    /// 等支持自定义快捷键时，它应该变成反映**实际注册值**的属性。
    public static let defaultHotKeyDescription = "⌥Space"

    /// 面板切换回调
    public var onTogglePalette: (() -> Void)?

    private let log = QuickLog.hotKey

    /// 已注册的快捷键引用
    private var hotKeyRef: EventHotKeyRef?

    /// Carbon 事件处理器引用
    private var eventHandlerRef: EventHandlerRef?

    /// 全局弱引用（Carbon C 回调需要静态访问）
    nonisolated(unsafe) private static weak var _instance: HotKeyService?

    public init() {
        HotKeyService._instance = self
    }

    /// 启动快捷键监听
    ///
    /// 默认注册 ⌥Space（Option + Space）作为全局唤醒快捷键。
    public func start() {
        registerDefaultHotKey()
    }

    /// 停止快捷键监听，释放所有注册
    public func stop() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
        log.info("已注销全局快捷键")
    }

    /// Carbon 回调触发时调用
    fileprivate func handleHotKeyPressed() {
        onTogglePalette?()
    }

    /// 测试用：模拟热键按下
    func handleHotKeyPressedForTesting() {
        handleHotKeyPressed()
    }

    // MARK: - 注册默认快捷键（⌥Space）

    private func registerDefaultHotKey() {
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x5155434B),  // "QUCK"
            id: 1
        )

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // 安装 Carbon 事件处理器
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                MainActor.assumeIsolated {
                    HotKeyService._instance?.handleHotKeyPressed()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        guard status == noErr else {
            log.error("安装 Carbon 事件处理器失败，OSStatus=\(status, privacy: .public)")
            return
        }

        // 注册 ⌥Space
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus != noErr {
            // 最常见的原因是组合键已被别的应用占用。用户报「快捷键没反应」先看这条。
            log.error("注册全局快捷键 ⌥Space 失败，OSStatus=\(registerStatus, privacy: .public)")
        } else {
            // notice 而不是 info：info 不落盘，事后查不到，而这条正是排障的第一现场。
            log.notice("已注册全局快捷键 ⌥Space")
        }
    }
}
