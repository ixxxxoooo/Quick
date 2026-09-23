// EventBus.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Synchronization

/// 插件间通信的事件总线
///
/// Feature Plugin 之间绝不直接依赖。插件通过 EventBus 发布事件，
/// 由 AppCore（组装层）订阅并路由到目标插件或基础设施服务。
///
/// **生产代码**用全局单例 `EventBus.shared`。**测试**应 `let bus = EventBus()` 构造独立实例，
/// 避免与 `shared` 或其它用例的订阅互相串线。
///
/// 用法：
/// ```swift
/// // 发布事件
/// EventBus.shared.post(NavigateEvent(pluginID: "devtools", context: ["tool": "json"]))
///
/// // 订阅事件（通常在 AppCore 中）
/// EventBus.shared.on(NavigateEvent.self) { event in
///     paletteCoordinator.navigate(to: event.pluginID)
/// }
/// ```
@MainActor
public final class EventBus: Sendable {

    /// 全局单例
    public static let shared = EventBus()

    private let log = QuickLog.eventBus

    /// 事件处理器存储（按事件类型索引；名字只用于日志与撞名检测，不参与路由）
    private var handlers: [ObjectIdentifier: [AnyEventHandler]] = [:]

    /// 事件名 → 首次注册它的事件类型（两个类型共用同一个 name 是编程错误）
    private var nameOwners: [String: ObjectIdentifier] = [:]

    /// 正在同步派发中的事件类型（handler 里再 post 同类事件会无限递归）
    private var dispatching: Set<ObjectIdentifier> = []

    /// 注册 ID 计数器（用于取消订阅）
    private var nextHandlerID: Int = 0

    public init() {}

    // MARK: - 发布事件

    /// 发布一个事件，所有已订阅该事件类型的处理器都会被调用
    /// - Parameter event: 要发布的事件
    public func post<E: PluginEvent>(_ event: E) {
        let key = ObjectIdentifier(E.self)
        guard let eventHandlers = handlers[key] else {
            // 没有订阅者通常意味着接线漏了，但对高频事件来说是正常的，所以只记 debug。
            log.debug("事件 \(E.name, privacy: .public) 无订阅者，已丢弃")
            return
        }
        guard !dispatching.contains(key) else {
            // 同步直调下重入同类事件会无限递归，延后一轮派发以打断循环。
            log.warning("事件 \(E.name, privacy: .public) 在自身派发中被重入发布，已延后一轮")
            Task { @MainActor [weak self] in self?.post(event) }
            return
        }
        log.debug("发布事件 \(E.name, privacy: .public)，\(eventHandlers.count, privacy: .public) 个订阅者")
        dispatching.insert(key)
        for handler in eventHandlers {
            handler.handle(event)
        }
        dispatching.remove(key)
    }

    // MARK: - 订阅事件

    /// 订阅指定类型的事件
    /// - Parameters:
    ///   - type: 事件类型
    ///   - handler: 事件处理闭包
    /// - Returns: 订阅凭证；持有即订阅，释放或 `cancel()` 即退订
    @discardableResult
    public func on<E: PluginEvent>(
        _ type: E.Type,
        handler: @escaping @MainActor (E) -> Void
    ) -> EventSubscription {
        let key = ObjectIdentifier(E.self)
        if let owner = nameOwners[E.name], owner != key {
            // 撞名不会让事件丢（路由按类型），但日志里的名字会张冠李戴，必须修。
            log.fault("事件名撞车：\(E.name, privacy: .public) 被两个事件类型同时使用")
        }
        nameOwners[E.name] = key

        let id = nextHandlerID
        nextHandlerID += 1

        let wrapper = TypedEventHandler<E>(id: id, handler: handler)
        handlers[key, default: []].append(wrapper)

        log.debug("订阅事件 \(E.name, privacy: .public)，handlerID=\(id, privacy: .public)")

        return EventSubscription(bus: self, eventKey: key, eventName: E.name, handlerID: id)
    }

    // MARK: - 取消订阅

    /// 根据订阅凭证取消订阅
    ///
    /// 一般不需要手动调：凭证释放时会自动退订。只在「对象还活着但要提前退订」时用。
    /// - Parameter subscription: 订阅凭证
    public func unsubscribe(_ subscription: EventSubscription) {
        removeHandler(
            eventKey: subscription.eventKey, eventName: subscription.eventName,
            handlerID: subscription.handlerID)
    }

    /// 按事件类型与 handler id 移除一条订阅
    func removeHandler(eventKey: ObjectIdentifier, eventName: String, handlerID: Int) {
        let before = handlers[eventKey]?.count ?? 0
        handlers[eventKey]?.removeAll { $0.id == handlerID }
        let after = handlers[eventKey]?.count ?? 0

        if before == after {
            // 订阅已被 removeAll 清掉。不是致命问题，但值得留痕。
            log.debug("取消订阅时处理器已不存在：事件=\(eventName, privacy: .public)，handlerID=\(handlerID, privacy: .public)")
        } else {
            log.debug("已取消订阅 \(eventName, privacy: .public)")
        }
    }

    /// 移除所有订阅（通常在应用退出时调用）
    public func removeAll() {
        let counts = handlers.values.reduce(0) { $0 + $1.count }
        handlers.removeAll()
        log.info("已清空事件总线，移除 \(counts, privacy: .public) 条订阅")
    }
}

// MARK: - 内部类型

/// 类型擦除的事件处理器
@MainActor
private protocol AnyEventHandler {
    var id: Int { get }
    func handle(_ event: any PluginEvent)
}

/// 强类型事件处理器
@MainActor
private struct TypedEventHandler<E: PluginEvent>: AnyEventHandler {
    let id: Int
    let handler: @MainActor (E) -> Void

    func handle(_ event: any PluginEvent) {
        guard let typed = event as? E else { return }
        handler(typed)
    }
}

/// 事件订阅凭证：持有即订阅，释放（或显式 `cancel()`）即退订
///
/// 不保存返回值的话订阅会随凭证一起销毁 —— 想长期收听就把它存下来。
public final class EventSubscription: Sendable {

    let eventKey: ObjectIdentifier
    let eventName: String
    let handlerID: Int

    /// 总线是单例，强引用不影响任何生命周期；弱引用反而让 cancel 的语义变得不可靠
    let bus: EventBus

    /// cancel 与 deinit 只允许生效一次
    private let isCancelled = Mutex(false)

    init(bus: EventBus, eventKey: ObjectIdentifier, eventName: String, handlerID: Int) {
        self.bus = bus
        self.eventKey = eventKey
        self.eventName = eventName
        self.handlerID = handlerID
    }

    /// 立即退订；之后凭证释放时不会再重复退订
    @MainActor
    public func cancel() {
        guard markCancelled() else { return }
        bus.removeHandler(eventKey: eventKey, eventName: eventName, handlerID: handlerID)
    }

    deinit {
        guard markCancelled() else { return }
        let bus = bus, eventKey = eventKey, eventName = eventName, handlerID = handlerID
        // deinit 不在任何 actor 上，退订跳回主 actor 执行
        Task { @MainActor in
            bus.removeHandler(eventKey: eventKey, eventName: eventName, handlerID: handlerID)
        }
    }

    private func markCancelled() -> Bool {
        isCancelled.withLock { cancelled in
            if cancelled { return false }
            cancelled = true
            return true
        }
    }
}
