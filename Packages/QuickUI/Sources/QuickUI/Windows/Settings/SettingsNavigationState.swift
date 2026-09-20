// SettingsNavigationState.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Observation

/// 浏览器式导航历史
public struct SettingsHistory: Sendable {
    public private(set) var current: SettingsTab
    private var back: [SettingsTab] = []
    private var forward: [SettingsTab] = []

    public init(current: SettingsTab) {
        self.current = current
    }

    public var canGoBack: Bool { !back.isEmpty }
    public var canGoForward: Bool { !forward.isEmpty }

    public mutating func select(_ tab: SettingsTab) {
        guard tab != current else { return }
        back.append(current)
        forward.removeAll()
        current = tab
    }

    public mutating func goBack() {
        guard let previous = back.popLast() else { return }
        forward.append(current)
        current = previous
    }

    public mutating func goForward() {
        guard let next = forward.popLast() else { return }
        back.append(current)
        current = next
    }
}

/// 设置界面的导航状态
///
/// 独立持有选中的 Tab 与导航历史，供侧边栏、详情栏及工具栏多方共同观察。
@Observable
@MainActor
public final class SettingsNavigationState {

    private var history: SettingsHistory

    public init(tab: SettingsTab = .general) {
        self.history = SettingsHistory(current: tab)
    }

    /// 当前选中的标签页
    public var tab: SettingsTab {
        get { history.current }
        set { history.select(newValue) }
    }

    public var canGoBack: Bool { history.canGoBack }
    public var canGoForward: Bool { history.canGoForward }

    public func select(_ tab: SettingsTab) {
        history.select(tab)
    }

    public func goBack() {
        history.goBack()
    }

    public func goForward() {
        history.goForward()
    }
}
