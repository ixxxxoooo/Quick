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

    /// 面板切换回调
    public var onTogglePalette: (() -> Void)?

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
    }

    /// Carbon 回调触发时调用
    fileprivate func handleHotKeyPressed() {
        onTogglePalette?()
    }

    // MARK: - 注册默认快捷键（⌥Space）

    private func registerDefaultHotKey() {
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x5155434B), // "QUCK"
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
            print("[HotKeyService] 安装事件处理器失败: \(status)")
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
            print("[HotKeyService] 注册快捷键失败: \(registerStatus)")
        }
    }
}
