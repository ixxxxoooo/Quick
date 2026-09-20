// EventBus.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 模块间通信的事件总线
///
/// Feature Module 之间绝不直接依赖。模块通过 EventBus 发布事件，
/// 由 AppCore（组装层）订阅并路由到目标模块或基础设施服务。
///
/// 用法：
/// ```swift
/// // 发布事件
/// EventBus.shared.post(NavigateEvent(moduleID: "devtools", context: ["tool": "json"]))
///
/// // 订阅事件（通常在 AppCore 中）
/// EventBus.shared.on(NavigateEvent.self) { event in
///     paletteCoordinator.navigate(to: event.moduleID)
/// }
/// ```
@MainActor
public final class EventBus: Sendable {

    /// 全局单例
    public static let shared = EventBus()

    private let log = QuickLog.eventBus

    /// 事件处理器存储（按事件名称索引）
    private var handlers: [String: [AnyEventHandler]] = [:]

    /// 注册 ID 计数器（用于取消订阅）
    private var nextHandlerID: Int = 0

    private init() {}

    // MARK: - 发布事件

    /// 发布一个事件，所有已订阅该事件类型的处理器都会被调用
    /// - Parameter event: 要发布的事件
    public func post<E: ModuleEvent>(_ event: E) {
        guard let eventHandlers = handlers[E.name] else {
            // 没有订阅者通常意味着接线漏了，但对高频事件来说是正常的，所以只记 debug。
            log.debug("事件 \(E.name, privacy: .public) 无订阅者，已丢弃")
            return
        }
        log.debug("发布事件 \(E.name, privacy: .public)，\(eventHandlers.count, privacy: .public) 个订阅者")
        for handler in eventHandlers {
            handler.handle(event)
        }
    }

    // MARK: - 订阅事件

    /// 订阅指定类型的事件
    /// - Parameters:
    ///   - type: 事件类型
    ///   - handler: 事件处理闭包
    /// - Returns: 订阅凭证，用于取消订阅
    @discardableResult
    public func on<E: ModuleEvent>(
        _ type: E.Type,
        handler: @escaping @MainActor (E) -> Void
    ) -> EventSubscription {
        let id = nextHandlerID
        nextHandlerID += 1

        let wrapper = TypedEventHandler<E>(id: id, handler: handler)

        if handlers[E.name] == nil {
            handlers[E.name] = []
        }
        handlers[E.name]?.append(wrapper)

        log.debug("订阅事件 \(E.name, privacy: .public)，handlerID=\(id, privacy: .public)")

        return EventSubscription(eventName: E.name, handlerID: id, bus: self)
    }

    // MARK: - 取消订阅

    /// 根据订阅凭证取消订阅
    /// - Parameter subscription: 订阅凭证
    public func unsubscribe(_ subscription: EventSubscription) {
        let before = handlers[subscription.eventName]?.count ?? 0
        handlers[subscription.eventName]?.removeAll { $0.id == subscription.handlerID }
        let after = handlers[subscription.eventName]?.count ?? 0

        if before == after {
            // 凭证被重复取消，或事件名已被 removeAll 清掉。不是致命问题，但值得留痕。
            log.warning(
                """
                取消订阅无效：事件=\(subscription.eventName, privacy: .public)，\
                handlerID=\(subscription.handlerID, privacy: .public)
                """)
        } else {
            log.debug("已取消订阅 \(subscription.eventName, privacy: .public)")
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
    func handle(_ event: any ModuleEvent)
}

/// 强类型事件处理器
@MainActor
private struct TypedEventHandler<E: ModuleEvent>: AnyEventHandler {
    let id: Int
    let handler: @MainActor (E) -> Void

    func handle(_ event: any ModuleEvent) {
        guard let typed = event as? E else { return }
        handler(typed)
    }
}

/// 事件订阅凭证（用于取消订阅）
@MainActor
public struct EventSubscription {
    let eventName: String
    let handlerID: Int
    weak var bus: EventBus?

    /// 取消此订阅
    public func cancel() {
        bus?.unsubscribe(self)
    }
}
