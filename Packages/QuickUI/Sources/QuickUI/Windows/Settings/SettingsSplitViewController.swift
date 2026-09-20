// SettingsSplitViewController.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import SwiftUI

/// 原生 AppKit 分栏控制器
///
/// 参考 Tinycast 实现：
/// 使用真正的 `NSSplitViewController`，使得窗口工具栏可以使用 `.sidebarTrackingSeparator`，
/// 从而将交通灯控制按钮与侧边栏对齐，并将窗口标题置于详情栏正上方，与 macOS 系统偏好设置完全一致。
@MainActor
final class SettingsSplitViewController: NSSplitViewController {

    init(sidebar: some View, detail: some View) {
        super.init(nibName: nil, bundle: nil)

        let sidebarHosting = NSHostingController(rootView: sidebar)
        sidebarHosting.sizingOptions = []
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHosting)
        sidebarItem.minimumThickness = DesignTokens.Size.settingsSidebar
        sidebarItem.maximumThickness = DesignTokens.Size.settingsSidebar
        sidebarItem.canCollapse = false

        let detailHosting = NSHostingController(rootView: detail)
        detailHosting.sizingOptions = []
        let detailItem = NSSplitViewItem(viewController: detailHosting)
        detailItem.minimumThickness = DesignTokens.Size.settingsDetailMinimum

        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
