// KeyboardLayoutServiceTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import QuickPlatform

/// 键盘布局服务测试
///
/// 这些测试**刻意不假设本机装了哪些输入源** —— 不同开发机的键盘布局/输入法组合
/// 差别很大（有人只有 ABC，有人装了中文、日文、越南文输入法）。因此所有断言都写成
/// 「对列表本身成立」或「对负面输入成立」，而不是写死任何具体 id / 名字。
///
/// 唯一会真正调用 `select` 的正例是「切到当前布局」：它不改变任何系统状态，
/// 因此可以安全地在测试里执行。切换其它布局会真的改掉用户输入法，测试里一律不做。
@MainActor
@Suite("键盘布局服务")
struct KeyboardLayoutServiceTests {

    /// 列表中的每一项都必须是合法的（id / 名字非空），且 id 唯一
    ///
    /// 空列表天然满足这两个断言，所以在没有可选择布局的机器上也会通过。
    @Test("列表条目 id、名称非空且 id 唯一")
    func layoutEntriesAreWellFormed() {
        let layouts = KeyboardLayoutService().availableLayouts()

        for layout in layouts {
            #expect(!layout.id.isEmpty)
            #expect(!layout.name.isEmpty)
        }
        // id 是持久化主键：一旦重复，设置里就分不清选的是哪一个。
        #expect(Set(layouts.map(\.id)).count == layouts.count)
    }

    /// 排序必须稳定：同一台机器上连续两次调用得到完全相同的顺序
    @Test("列表按显示名稳定排序")
    func layoutOrderingIsStable() {
        let service = KeyboardLayoutService()
        let layouts = service.availableLayouts()

        let names = layouts.map(\.name)
        for (previous, next) in zip(names, names.dropFirst()) {
            // 允许相等（同名时按 id 兜底），但不允许逆序。
            #expect(previous.localizedStandardCompare(next) != .orderedDescending)
        }
        #expect(service.availableLayouts().map(\.id) == layouts.map(\.id))
    }

    /// 不存在的 id 必须被拒绝，且不能动到当前布局
    ///
    /// 这是「用户删掉了之前保存的布局」这一真实场景：服务要返回 false 并保持系统原样。
    @Test("未知布局 id 被拒绝且不改变当前布局")
    func unknownLayoutIDIsRejectedAndLeavesCurrentUntouched() {
        let service = KeyboardLayoutService()
        let before = service.currentLayoutID()

        #expect(!service.select(layoutID: "definitely-not-a-real-layout-id"))
        #expect(service.currentLayoutID() == before)

        // 空 id 同样必须被拒绝。
        #expect(!service.select(layoutID: ""))
        #expect(service.currentLayoutID() == before)
    }

    /// currentLayoutID() 要么为 nil，要么是列表里的一个 id
    @Test("当前布局是列表成员")
    func currentLayoutIsAmongAvailableLayouts() {
        let service = KeyboardLayoutService()
        let ids = Set(service.availableLayouts().map(\.id))

        guard let current = service.currentLayoutID() else {
            // nil 是合法结果（例如输入源属性暂时读不到），没有可断言的成员关系。
            return
        }
        #expect(ids.contains(current))
    }

    /// 切到当前布局是幂等空操作：返回 true，且不改变任何状态，所以可以安全执行
    ///
    /// 这里也是「`availableLayouts()` 返回的 id 能被 `select(layoutID:)` 接受」的
    /// 正面证明：当前布局必然在列表里，选中它既验证了查找路径又不产生副作用。
    /// 其余列表成员的接受性无法在不真正切换输入法的前提下验证，故不测。
    @Test("切换到当前布局是幂等空操作")
    func selectingCurrentLayoutIsANoOp() {
        let service = KeyboardLayoutService()
        let ids = Set(service.availableLayouts().map(\.id))

        guard let current = service.currentLayoutID(), ids.contains(current) else {
            // 没有可读、可选的当前布局时跳过：无可测状态，测试应当通过而非失败。
            return
        }

        #expect(service.select(layoutID: current))
        #expect(service.currentLayoutID() == current)
    }

    /// 没有可选择布局时，查询与切换都必须安全返回，而不是抛错或崩溃
    ///
    /// 用一个几乎不可能存在的 id 探测「找不到」分支；有布局的机器上等价于普通的
    /// 负面用例，没有布局的机器上则确保空列表不会让任何调用崩掉。
    @Test("无可选择布局时查询与切换仍然安全")
    func queriesStaySafeWithoutSelectableLayouts() {
        let service = KeyboardLayoutService()
        let layouts = service.availableLayouts()

        #expect(layouts.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty })
        // 「找不到」无论是因机器没有布局，还是因 id 本身无效，都只返回 false。
        #expect(!service.select(layoutID: "com.apple.keylayout.Quick-does-not-exist"))
    }
}
