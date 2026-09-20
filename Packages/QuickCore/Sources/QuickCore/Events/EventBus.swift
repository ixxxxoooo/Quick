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

    /// 事件处理器存储（按事件名称索引）
    private var handlers: [String: [AnyEventHandler]] = [:]

    /// 注册 ID 计数器（用于取消订阅）
    private var nextHandlerID: Int = 0

    private init() {}

    // MARK: - 发布事件

    /// 发布一个事件，所有已订阅该事件类型的处理器都会被调用
    /// - Parameter event: 要发布的事件
    public func post<E: ModuleEvent>(_ event: E) {
        guard let eventHandlers = handlers[E.name] else { return }
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

        return EventSubscription(eventName: E.name, handlerID: id, bus: self)
    }

    // MARK: - 取消订阅

    /// 根据订阅凭证取消订阅
    /// - Parameter subscription: 订阅凭证
    public func unsubscribe(_ subscription: EventSubscription) {
        handlers[subscription.eventName]?.removeAll { $0.id == subscription.handlerID }
    }

    /// 移除所有订阅（通常在应用退出时调用）
    public func removeAll() {
        handlers.removeAll()
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
