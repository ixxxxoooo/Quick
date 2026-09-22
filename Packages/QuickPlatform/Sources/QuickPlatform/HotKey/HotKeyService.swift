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

/// 绑定结果
public enum HotKeyBindOutcome: Equatable, Sendable {
    /// 已写入并按需要注册
    case applied
    /// 同一组合键已经绑了别的命令，这次没有改
    case conflict(commandID: String)
}

/// 全局快捷键服务
///
/// 使用 Carbon HotKey API 注册系统级全局快捷键。一条组合键只对应一个命令；
/// 命令被关闭时绑定留在偏好里，但不向系统注册。
@MainActor
public final class HotKeyService {

    public static let defaultHotKeyDescription = "⌥Space"

    /// 热键触发时交出命令 id，由宿主执行
    public var onCommand: ((String) -> Void)?

    private let log = QuickLog.hotKey
    private let defaults: UserDefaults

    private struct Entry {
        let commandID: String
        let shortcut: KeyShortcut
        let carbonID: UInt32
        var ref: EventHotKeyRef?
    }

    private var entries: [String: Entry] = [:]
    private var idToKey: [UInt32: String] = [:]
    private var nextCarbonID: UInt32 = 0
    private var eventHandlerRef: EventHandlerRef?
    private let signature: OSType = 0x5155434B  // "QUCK"

    /// 内存中的绑定。键是命令 id
    private var bindings: [String: KeyShortcut] = [:]

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

    /// 初始化
    /// - Parameter defaults: 偏好存储。测试传独立 suite，避免污染用户的快捷键
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 启动快捷键监听，并做一次旧键迁移
    public func start() {
        HotKeyMigration.migrate(defaults: defaults)
        installCarbonHandlerIfNeeded()
        if binding(for: CommandID.togglePalette) == nil {
            let defaultShortcut = KeyShortcut(
                carbonKeyCode: kVK_Space,
                carbonModifiers: optionKey
            )
            _ = setBinding(defaultShortcut, for: CommandID.togglePalette, registerNow: true)
        }
        log.notice("全局快捷键服务已启动")
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
        log.notice("已注销所有全局快捷键")
    }

    /// 测试用：模拟触发主面板热键
    func handleHotKeyPressedForTesting() {
        onCommand?(CommandID.togglePalette)
    }

    // MARK: - 绑定管理

    /// 当前绑了快捷键的命令 id
    public func boundCommandIDs() -> [String] {
        let prefix = HotKeyAction.commandKeyPrefix
        return defaults.dictionaryRepresentation().keys.compactMap { key in
            guard key.hasPrefix(prefix) else { return nil }
            let id = String(key.dropFirst(prefix.count))
            return id.isEmpty ? nil : id
        }
    }

    /// 读取某条命令的快捷键
    public func binding(for commandID: String) -> KeyShortcut? {
        if let memory = bindings[commandID] {
            return memory
        }
        let key = HotKeyAction(commandID: commandID).defaultsKey
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            let shortcut = try JSONDecoder().decode(KeyShortcut.self, from: data)
            bindings[commandID] = shortcut
            return shortcut
        } catch {
            log.error(
                "快捷键解码失败 \(commandID, privacy: .public)：\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 设置快捷键。`shortcut == nil` 表示清除
    ///
    /// - Parameters:
    ///   - shortcut: 新组合键；nil 表示清除
    ///   - commandID: 命令 id
    ///   - registerNow: 命令当前是否允许注册。关闭的命令只存绑定
    /// - Returns: 冲突时偏好和注册都不变
    @discardableResult
    public func setBinding(
        _ shortcut: KeyShortcut?,
        for commandID: String,
        registerNow: Bool
    ) -> HotKeyBindOutcome {
        let action = HotKeyAction(commandID: commandID)
        if let shortcut {
            if let occupied = commandIDOccupying(shortcut, except: commandID) {
                log.notice(
                    "快捷键冲突，拒绝把 \(commandID, privacy: .public) 绑到已被 \(occupied, privacy: .public) 占用的组合键"
                )
                return .conflict(commandID: occupied)
            }
            bindings[commandID] = shortcut
            do {
                let data = try JSONEncoder().encode(shortcut)
                defaults.set(data, forKey: action.defaultsKey)
            } catch {
                log.error(
                    "快捷键写入失败 \(commandID, privacy: .public)：\(error.localizedDescription, privacy: .public)")
            }
            if registerNow {
                register(commandID)
                log.notice(
                    "已绑定快捷键 \(commandID, privacy: .public) \(shortcut.displayString, privacy: .public)")
            } else {
                unregister(action.defaultsKey)
                log.notice("命令 \(commandID, privacy: .public) 已关闭，快捷键已保存但未注册")
            }
        } else {
            bindings.removeValue(forKey: commandID)
            defaults.removeObject(forKey: action.defaultsKey)
            unregister(action.defaultsKey)
            log.notice("已清除快捷键 \(commandID, privacy: .public)")
        }
        return .applied
    }

    /// 按命令开关同步 Carbon 注册。绑定本身不删
    public func syncRegistrations(isEnabled: (String) -> Bool) {
        var registered = 0
        var skipped = 0
        for commandID in boundCommandIDs() {
            let allow = commandID == CommandID.togglePalette || isEnabled(commandID)
            if allow, binding(for: commandID) != nil {
                register(commandID)
                registered += 1
            } else {
                unregister(HotKeyAction(commandID: commandID).defaultsKey)
                skipped += 1
            }
        }
        log.notice(
            "热键同步完成，注册 \(registered, privacy: .public) 个，因命令关闭跳过 \(skipped, privacy: .public) 个"
        )
    }

    /// 注册某个已保存的命令热键
    public func register(_ commandID: String) {
        guard let shortcut = binding(for: commandID) else { return }
        register(commandID: commandID, shortcut: shortcut)
    }

    private func commandIDOccupying(_ shortcut: KeyShortcut, except commandID: String) -> String? {
        for id in boundCommandIDs() where id != commandID {
            if binding(for: id) == shortcut {
                return id
            }
        }
        return nil
    }

    private func register(commandID: String, shortcut: KeyShortcut) {
        let key = HotKeyAction(commandID: commandID).defaultsKey
        unregister(key)

        nextCarbonID += 1
        let entry = Entry(commandID: commandID, shortcut: shortcut, carbonID: nextCarbonID, ref: nil)
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
            log.error("注册热键失败：\(key, privacy: .public)，status=\(status, privacy: .public)")
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

        log.notice("触发全局快捷键：\(entry.commandID, privacy: .public)")
        onCommand?(entry.commandID)
    }
}
