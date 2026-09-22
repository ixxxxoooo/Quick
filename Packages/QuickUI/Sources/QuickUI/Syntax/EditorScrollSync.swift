// EditorScrollSync.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit

/// 两个编辑器的垂直滚动同步
///
/// `NSTextView` 没有内建的同步滚动，而左右对比必须一起滚 —— 否则行号对齐立刻失效。
/// 这里盯住两个 `NSClipView` 的 `boundsDidChange`，把纵向偏移镜像过去。
/// `isSyncing` 是必须的：不做闸门时 A 的滚动通知会触发 B 的 `scroll(to:)`，
/// B 再回头发一条通知给 A，形成回环。
///
/// **用 selector 而不是 block 观察者**：block 版本是 `@Sendable`，把 `NSClipView` / 通知
/// 这类主线程对象捕进去在 Swift 6 下过不了数据竞争检查；selector 版本天然落在主线程。
@MainActor
public final class EditorScrollSync: NSObject {

    /// 编辑器在分栏里的角色
    public enum Role {
        case leading
        case trailing
    }

    private weak var leading: NSScrollView?
    private weak var trailing: NSScrollView?
    private var registered: [NSClipView] = []
    private var isSyncing = false

    public override init() {
        super.init()
    }

    /// 登记一个编辑器；两个都到齐后才接上监听
    public func attach(_ scrollView: NSScrollView, role: Role) {
        switch role {
        case .leading: leading = scrollView
        case .trailing: trailing = scrollView
        }
        wireIfReady()
    }

    public func detach() {
        for clipView in registered {
            NotificationCenter.default.removeObserver(
                self, name: NSView.boundsDidChangeNotification, object: clipView)
        }
        registered.removeAll()
        leading = nil
        trailing = nil
    }

    private func wireIfReady() {
        guard registered.isEmpty, let leading, let trailing else { return }
        for scrollView in [leading, trailing] {
            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(clipBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )
            registered.append(clipView)
        }
    }

    @objc private func clipBoundsDidChange(_ notification: Notification) {
        guard !isSyncing, let source = notification.object as? NSClipView else { return }
        mirror(from: source)
    }

    private func mirror(from source: NSClipView) {
        guard let leading, let trailing else { return }
        let target = source === leading.contentView ? trailing : leading
        guard target.contentView.bounds.origin.y != source.bounds.origin.y else { return }

        isSyncing = true
        var origin = target.contentView.bounds.origin
        origin.y = source.bounds.origin.y
        target.contentView.scroll(to: origin)
        target.reflectScrolledClipView(target.contentView)
        isSyncing = false
    }
}
