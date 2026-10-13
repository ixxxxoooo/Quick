// SearchSessionGate.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 「同一时刻只有一次搜索算数」的门闸
///
/// Spotlight 的完成通知是异步到达的：用户连敲几个字时，前一次查询的
/// `DidFinishGathering` 完全可能在后一次查询已经开始之后才到。如果完成回调不核对
/// 「我是不是当前这一次」，旧查询就会把新查询提前收尾，结果串台。
///
/// 每次开始搜索领一个单调递增的令牌；任何回调（完成、超时、取消）都先问
/// `isCurrent(_:)`，不是当前令牌就直接丢弃。纯逻辑，所以乱序场景能被测试固定。
public struct SearchSessionGate: Sendable {

    /// 一次搜索的凭证
    public struct Token: Equatable, Sendable {
        fileprivate let value: UInt64
    }

    private var counter: UInt64 = 0
    private var current: Token?

    public init() {}

    /// 开始新一次搜索，同时让之前所有令牌作废
    public mutating func begin() -> Token {
        counter += 1
        let token = Token(value: counter)
        current = token
        return token
    }

    /// 令牌是否仍是当前这一次
    public func isCurrent(_ token: Token) -> Bool {
        current == token
    }

    /// 结束当前搜索（令牌作废，但不开始新的）
    ///
    /// - Returns: `token` 是当前令牌时返回 true 并清空；已经过期则返回 false
    public mutating func finish(_ token: Token) -> Bool {
        guard current == token else { return false }
        current = nil
        return true
    }
}
