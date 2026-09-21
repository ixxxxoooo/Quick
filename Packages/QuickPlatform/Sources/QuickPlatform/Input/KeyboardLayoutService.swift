// KeyboardLayoutService.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Carbon.HIToolbox
import Foundation
import QuickCore

/// 键盘输入源（键盘布局 / 输入法）服务
///
/// 提供「列出可选择的键盘布局」「读取当前布局」「切换到指定布局」三件事，
/// 供「强制键盘布局」设置使用：面板打开时切到用户指定的布局，关闭时切回原布局。
///
/// ## 为什么用 Carbon 而不是现代 API
///
/// 这里用的是 Carbon 的 Text Input Source API（`TIS*`）。它和 `HotKeyService` 里的
/// `RegisterEventHotKey` 属于同一类**有意的能力缺口依赖**：AppKit / SwiftUI 里没有任何
/// 等价替代 —— `NSTextInputContext` 只描述「某个响应者怎么收键」，既不能枚举系统里
/// 装了什么输入源，也不能程序化地把它切成当前输入源。所以虽然本仓库的立场是「只面向
/// 最新、被废弃的 API 是缺陷」，这一处仍然必须走 Carbon，理由与全局快捷键一致。
///
/// ## 健壮性
///
/// 输入源列表是系统全局状态，随时可能变化（用户在系统设置里增删输入法）。任何属性都
/// 可能缺失，任何 id 都可能已经失效。因此本服务对「没有输入源」「属性缺失」「保存的 id
/// 已被删除」一律返回 nil / false，绝不崩溃、绝不写坏系统状态。
@MainActor
public final class KeyboardLayoutService {

    /// 一个可选择的键盘布局（纯值类型，不含「是否当前」这类会变化的状态）
    public struct KeyboardLayout: Identifiable, Sendable, Equatable {
        /// 输入源的稳定标识（`kTISPropertyInputSourceID`），如 `com.apple.keylayout.ABC`。
        /// 它是持久化到设置里的主键，跨启动不变。
        public let id: String
        /// 本地化显示名（`kTISPropertyLocalizedName`），如 "ABC"、"拼音 - 简体"。
        public let name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    private let log = QuickLog.platform

    public init() {}

    // MARK: - 查询

    /// 所有**可选择的**键盘布局，按显示名排序
    ///
    /// 过滤条件：类别是键盘、`kTISPropertyInputSourceIsSelectCapable` 为真，
    /// 且当前已启用（`kTISPropertyInputSourceIsEnabled`）。未启用的输入源即使装了也不该
    /// 出现在设置里 —— 选中它 `TISSelectInputSource` 也不会生效。
    /// 同名布局按 id 兜底排序，保证 UI 顺序稳定。
    public func availableLayouts() -> [KeyboardLayout] {
        var seen = Set<String>()
        var layouts: [KeyboardLayout] = []
        for source in selectableSources() {
            // 已启用是「能真正切过去」的前提；输入源被禁用时属性可能直接缺失，故用 flag 默认 false。
            guard flag(source, kTISPropertyInputSourceIsEnabled),
                let id = string(source, kTISPropertyInputSourceID),
                let name = string(source, kTISPropertyLocalizedName),
                !id.isEmpty,
                !name.isEmpty
            else { continue }
            // 理论上系统不会返回重复 id，但一旦重复，设置里的主键就不再唯一，UI 也会出现
            // 两个无法区分的选项 —— 这里主动去重，让「id 唯一」成为服务的保证而不是假设。
            guard seen.insert(id).inserted else { continue }
            layouts.append(KeyboardLayout(id: id, name: name))
        }
        let sorted = layouts.sorted { lhs, rhs in
            switch lhs.name.localizedStandardCompare(rhs.name) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return lhs.id < rhs.id
            }
        }
        log.debug("键盘布局列表：\(sorted.count, privacy: .public) 个可选择输入源")
        return sorted
    }

    /// 当前输入源的 id；无法读取时为 nil
    public func currentLayoutID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        guard let id = string(source, kTISPropertyInputSourceID), !id.isEmpty else {
            return nil
        }
        return id
    }

    // MARK: - 切换

    /// 切换到指定键盘布局
    ///
    /// 只在**可选择**的输入源里查找，避免用户保存的 id 指向一个存在但不可选的输入源。
    /// 返回是否找到并成功选中（`TISSelectInputSource` 返回 `noErr`）。
    /// 找不到（例如布局已被用户删除）或选中失败都返回 false，调用方无需特殊处理。
    @discardableResult
    public func select(layoutID: String) -> Bool {
        guard !layoutID.isEmpty,
            let source = selectableSources().first(where: {
                string($0, kTISPropertyInputSourceID) == layoutID
            })
        else {
            // 常见于用户在系统设置里删掉了之前保存的输入法：可恢复，不该打断面板流程。
            log.warning("切换键盘布局失败：找不到可选择的输入源 \(layoutID, privacy: .public)")
            return false
        }
        let name = string(source, kTISPropertyLocalizedName) ?? layoutID
        let status = TISSelectInputSource(source)
        guard status == noErr else {
            log.error(
                "切换键盘布局失败：\(name, privacy: .public)，OSStatus=\(status, privacy: .public)")
            return false
        }
        log.notice("已切换到键盘布局：\(name, privacy: .public)")
        return true
    }

    // MARK: - 输入源枚举

    /// 拉取当前系统中可选择的键盘输入源
    ///
    /// 过滤字典按类别和「可选择」限定，`includeAllInstalled` 传 false，只取当前启用的输入源。
    private func selectableSources() -> [TISInputSource] {
        // kTISPropertyInputSourceCategory 的合法取值是 kTISCategoryKeyboardInputSource，
        // 不是 kTISPropertyInputSourceCategoryKeyboard（后者在 SDK 里根本不存在）。
        // 键和值都转成 String 再交给 CFDictionary 桥接，避免把隐式解包的 CFString? 当作 Any。
        let properties =
            [
                kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
                kTISPropertyInputSourceIsSelectCapable as String: true
            ] as CFDictionary
        // TISCreateInputSourceList 是 Create 规则：返回的对象归调用方所有，必须 takeRetainedValue。
        guard let list = TISCreateInputSourceList(properties, false)?.takeRetainedValue() else {
            return []
        }
        // CFArray 与 NSArray 免费桥接，逐元素桥接成 TISInputSource 数组；类型不符时返回空而不是崩溃。
        guard let sources = list as? [TISInputSource] else {
            log.warning("键盘布局列表桥接失败：CFArray 内容不是 TISInputSource")
            return []
        }
        return sources
    }

    /// 读取输入源的字符串属性
    ///
    /// `TISGetInputSourceProperty` 是 Get 规则：返回的指针不归调用方所有，所以用
    /// `takeUnretainedValue` 桥接（不能 takeRetainedValue，否则会过释放）；
    /// 属性值本身是 CFString，与 Swift String 免费桥接。
    private func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    /// 读取输入源的布尔属性
    ///
    /// TIS 的布尔属性是 CFBoolean（与 NSNumber 免费桥接），用 `CFBooleanGetValue` 取值；
    /// 属性缺失时返回 false，让「缺失」与「显式为 false」都落到同一个安全分支。
    private func flag(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }
}
