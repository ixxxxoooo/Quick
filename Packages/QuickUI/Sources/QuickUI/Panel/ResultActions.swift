// ResultActions.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import QuickCore

/// ⌘K 操作菜单里的一项
struct ResultAction: Identifiable {
    let id: String
    let title: String
    let icon: String
    let perform: @MainActor () -> Void
}

/// 一条结果能做哪些事
///
/// 分两层：`Kind` 是**纯数据**（由结果的形状决定，可单测），`makeActions` 才把它接上
/// 访达 / 剪贴板这些副作用。这样「哪种结果给哪几个操作」的规则不用启动 AppKit 就能验证。
enum ResultActionCatalog {

    enum Kind: Equatable {
        /// 执行（等同回车）
        case run
        /// 在访达中显示（应用 / 文件）
        case reveal(path: String)
        /// 复制路径
        case copyPath(path: String)
        /// 复制标题
        case copyTitle
    }

    /// 由结果的形状推出可用操作（第一项永远是「执行」）
    static func kinds(for item: SearchableItem) -> [Kind] {
        var kinds: [Kind] = [.run]
        if case .appIcon(let path) = item.iconType, !path.isEmpty {
            kinds.append(.reveal(path: path))
            kinds.append(.copyPath(path: path))
        }
        kinds.append(.copyTitle)
        return kinds
    }

    /// 接上副作用
    ///
    /// - Parameters:
    ///   - item: 目标结果
    ///   - run: 「执行」走协调器已有的激活路径（会记最近使用），不在这里直接调 `item.action`
    @MainActor
    static func makeActions(for item: SearchableItem, run: @escaping @MainActor () -> Void)
        -> [ResultAction]
    {
        kinds(for: item).map { kind in
            switch kind {
            case .run:
                return ResultAction(id: "run", title: "执行", icon: "return", perform: run)
            case .reveal(let path):
                return ResultAction(id: "reveal", title: "在访达中显示", icon: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    EventBus.shared.post(HidePaletteEvent(restoreFocus: false))
                }
            case .copyPath(let path):
                return ResultAction(id: "copyPath", title: "复制路径", icon: "doc.on.doc") {
                    Self.copy(path, hud: "已复制路径")
                }
            case .copyTitle:
                return ResultAction(id: "copyTitle", title: "复制名称", icon: "textformat") {
                    Self.copy(item.title, hud: "已复制名称")
                }
            }
        }
    }

    @MainActor
    private static func copy(_ text: String, hud: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        EventBus.shared.post(ShowHUDEvent(message: hud, tone: .success))
    }
}

/// ⌘K 操作菜单的状态
///
/// 和 `PaletteSelection` 一样是**独立的观察对象**，不持有窗口，所以被面板视图观察是安全的
/// （见 `PaletteCoordinator` 顶部关于 AttributeGraph 死循环的说明）。
@MainActor
@Observable
final class ActionMenuState {

    private(set) var isOpen = false
    private(set) var actions: [ResultAction] = []
    private(set) var index = 0

    /// 打开菜单；没有可做的操作时保持关闭
    func open(actions: [ResultAction]) {
        guard !actions.isEmpty else { return }
        self.actions = actions
        index = 0
        isOpen = true
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        actions = []
        index = 0
    }

    /// 上下移动，夹在边界内
    func move(_ delta: Int) {
        guard isOpen, !actions.isEmpty else { return }
        index = min(max(index + delta, 0), actions.count - 1)
    }

    /// 选中某一项（鼠标悬停）
    func select(_ newIndex: Int) {
        guard actions.indices.contains(newIndex) else { return }
        index = newIndex
    }

    /// 执行选中项并关闭菜单
    /// - Returns: 是否真的执行了
    @discardableResult
    func runSelected() -> Bool {
        guard isOpen, actions.indices.contains(index) else { return false }
        let action = actions[index]
        close()
        action.perform()
        return true
    }
}
