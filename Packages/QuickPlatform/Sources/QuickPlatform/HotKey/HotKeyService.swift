// HotKeyService.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Carbon.HIToolbox
import QuickCore

/// C 语言 Carbon 热键事件回调
private func hotKeyCarbonCallback(
    _: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let error = GetEventParameter(
        event,
        UInt32(kEventParamDirectObject),
        UInt32(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard error == noErr else { return error }
    let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
    return MainActor.assumeIsolated {
        service.handleCarbonEvent(hotKeyID)
        return noErr
    }
}

/// 全局快捷键服务
///
/// 使用 Carbon HotKey API 注册系统级全局快捷键。
/// 支持：
/// - 默认 ⌥Space 呼出主面板
/// - 各应用独立绑定热键（直接启动/激活应用）
/// - 各系统控制操作绑定热键
/// - 自定义 Shell 命令绑定热键
/// - 录制时自动暂停全局监听，防止冲突
@MainActor
public final class HotKeyService {

    public static let defaultHotKeyDescription = "⌥Space"

    /// 面板切换回调
    public var onTogglePalette: (() -> Void)?

    /// 启动应用回调
    public var onLaunchApp: ((String) -> Void)?

    /// 执行系统操作回调
    public var onRunSystemAction: ((String) -> Void)?

    /// 运行自定义 Shell 命令回调
    public var onRunCustomCommand: ((UUID) -> Void)?

    /// 导航到功能插件回调
    public var onNavigateToPlugin: ((String) -> Void)?

    private let log = QuickLog.hotKey

    private struct Entry {
        let action: HotKeyAction
        let shortcut: KeyShortcut
        let carbonID: UInt32
        var ref: EventHotKeyRef?
    }

    private var entries: [String: Entry] = [:]
    private var idToKey: [UInt32: String] = [:]
    private var nextCarbonID: UInt32 = 0
    private var eventHandlerRef: EventHandlerRef?
    private let signature: OSType = 0x5155434B  // "QUCK"

    /// 内存中保存的所有当前绑定
    private var bindings: [HotKeyAction: KeyShortcut] = [:]

    /// 是否暂停监听（录制快捷键时为 true）
    public var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            for key in entries.keys {
                if isPaused {
                    deactivate(key)
                } else {
                    activate(key)
                }
            }
        }
    }

    public init() {}

    /// 启动快捷键监听
    public func start() {
        installCarbonHandlerIfNeeded()
        // 注册默认面板快捷键
        if binding(for: .togglePalette) == nil {
            // ⌥Space: Space is 49, Option is optionKey
            let defaultShortcut = KeyShortcut(
                carbonKeyCode: kVK_Space,
                carbonModifiers: optionKey
            )
            setBinding(defaultShortcut, for: .togglePalette)
        } else {
            // 恢复已保存的快捷键
            register(.togglePalette)
        }
        log.info("全局快捷键服务已启动")
    }

    /// 停止快捷键监听，释放所有注册
    public func stop() {
        for key in Array(entries.keys) {
            unregister(key)
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
        log.info("已注销所有全局快捷键")
    }

    /// 测试用：模拟触发主面板热键
    func handleHotKeyPressedForTesting() {
        onTogglePalette?()
    }

    // MARK: - 绑定管理

    /// 获取某操作当前绑定的快捷键
    public func binding(for action: HotKeyAction) -> KeyShortcut? {
        if let memory = bindings[action] {
            return memory
        }
        // 从 UserDefaults 读取
        if let data = UserDefaults.standard.data(forKey: action.defaultsKey),
            let shortcut = try? JSONDecoder().decode(KeyShortcut.self, from: data)
        {
            bindings[action] = shortcut
            return shortcut
        }
        return nil
    }

    /// 设置并保存快捷键绑定（传 nil 表示清除）
    public func setBinding(_ shortcut: KeyShortcut?, for action: HotKeyAction) {
        if let shortcut {
            bindings[action] = shortcut
            if let data = try? JSONEncoder().encode(shortcut) {
                UserDefaults.standard.set(data, forKey: action.defaultsKey)
            }
            register(action)
        } else {
            bindings.removeValue(forKey: action)
            UserDefaults.standard.removeObject(forKey: action.defaultsKey)
            unregister(action.defaultsKey)
        }
    }

    /// 注册某个 action 的热键
    public func register(_ action: HotKeyAction) {
        guard let shortcut = binding(for: action) else { return }
        register(action: action, shortcut: shortcut)
    }

    /// 恢复已持久化的热键绑定
    public func restoreHotKeys(
        appBundleIDs: [String], systemActionIDs: [String],
        customCommandIDs: [UUID], pluginIDs: [String] = []
    ) {
        for bundleID in appBundleIDs {
            let action = HotKeyAction.app(bundleID: bundleID)
            if binding(for: action) != nil {
                register(action)
            }
        }
        for id in systemActionIDs {
            let action = HotKeyAction.systemAction(id: id)
            if binding(for: action) != nil {
                register(action)
            }
        }
        for id in customCommandIDs {
            let action = HotKeyAction.customCommand(id: id)
            if binding(for: action) != nil {
                register(action)
            }
        }
        for id in pluginIDs {
            let action = HotKeyAction.plugin(id: id)
            if binding(for: action) != nil {
                register(action)
            }
        }
    }

    private func register(action: HotKeyAction, shortcut: KeyShortcut) {
        let key = action.defaultsKey
        unregister(key)

        nextCarbonID += 1
        let entry = Entry(action: action, shortcut: shortcut, carbonID: nextCarbonID, ref: nil)
        entries[key] = entry
        idToKey[nextCarbonID] = key

        if !isPaused {
            activate(key)
        }
    }

    private func unregister(_ key: String) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        if let ref = entry.ref {
            UnregisterEventHotKey(ref)
        }
        idToKey.removeValue(forKey: entry.carbonID)
    }

    private func activate(_ key: String) {
        guard var entry = entries[key], entry.ref == nil else { return }
        installCarbonHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(entry.shortcut.carbonKeyCode),
            UInt32(entry.shortcut.carbonModifiers),
            EventHotKeyID(signature: signature, id: entry.carbonID),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            log.warning("注册热键失败：\(key, privacy: .public)，status=\(status, privacy: .public)")
            return
        }
        entry.ref = ref
        entries[key] = entry
    }

    private func deactivate(_ key: String) {
        guard var entry = entries[key], let ref = entry.ref else { return }
        UnregisterEventHotKey(ref)
        entry.ref = nil
        entries[key] = entry
    }

    private func installCarbonHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let unmanaged = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyCarbonCallback,
            1,
            &eventType,
            unmanaged,
            &eventHandlerRef
        )
        if status != noErr {
            log.error("安装 Carbon 事件处理器失败，OSStatus=\(status, privacy: .public)")
        }
    }

    // MARK: - 事件分发

    fileprivate func handleCarbonEvent(_ hotKeyID: EventHotKeyID) {
        guard hotKeyID.signature == signature,
            let key = idToKey[hotKeyID.id],
            let entry = entries[key]
        else { return }

        log.info("触发全局快捷键：\(key, privacy: .public)")
        switch entry.action {
        case .togglePalette:
            onTogglePalette?()
        case .app(let bundleID):
            onLaunchApp?(bundleID)
        case .systemAction(let id):
            onRunSystemAction?(id)
        case .customCommand(let id):
            onRunCustomCommand?(id)
        case .plugin(let id):
            onNavigateToPlugin?(id)
        }
    }
}
