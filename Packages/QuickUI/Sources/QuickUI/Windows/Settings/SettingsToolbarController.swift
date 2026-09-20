// SettingsToolbarController.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Foundation

/// 设置窗口工具栏控制器
///
/// 参考 Tinycast 设计：
/// 通过 AppKit 的 `NSToolbar` 配合 `.sidebarTrackingSeparator` 与前进后退按钮，
/// 呈现与 macOS 系统设置及 Tinycast 完全一致的导航与标题布局。
@MainActor
final class SettingsToolbarController: NSObject, NSToolbarDelegate {

    private static let back = NSToolbarItem.Identifier("SettingsBack")
    private static let forward = NSToolbarItem.Identifier("SettingsForward")

    private weak var window: NSWindow?
    private let navigationState: SettingsNavigationState
    private let backButton: NSButton
    private let forwardButton: NSButton

    init(navigationState: SettingsNavigationState) {
        self.navigationState = navigationState
        self.backButton = Self.makeButton("chevron.backward", "Back")
        self.forwardButton = Self.makeButton("chevron.forward", "Forward")
        super.init()
        backButton.target = self
        backButton.action = #selector(goBack)
        forwardButton.target = self
        forwardButton.action = #selector(goForward)
    }

    func install(in window: NSWindow) {
        self.window = window
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = false

        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.allowsDisplayModeCustomization = false
        window.toolbar = toolbar

        observe()
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator, Self.back, Self.forward]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        switch identifier {
        case Self.back:
            item.view = backButton
            item.label = "Back"
        case Self.forward:
            item.view = forwardButton
            item.label = "Forward"
        default:
            return nil
        }
        item.isNavigational = true
        item.visibilityPriority = .high
        item.autovalidates = false
        return item
    }

    // MARK: - 动作

    @objc private func goBack() {
        navigationState.goBack()
    }

    @objc private func goForward() {
        navigationState.goForward()
    }

    // MARK: - 私有方法

    private func observe() {
        withObservationTracking {
            sync()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observe()
            }
        }
    }

    private func sync() {
        window?.title = navigationState.tab.title
        backButton.isEnabled = navigationState.canGoBack
        forwardButton.isEnabled = navigationState.canGoForward
    }

    private static func makeButton(_ symbol: String, _ label: String) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        let button = NSButton(image: image ?? NSImage(), target: nil, action: nil)
        button.bezelStyle = .toolbar
        button.setAccessibilityLabel(label)
        button.toolTip = label
        return button
    }
}
