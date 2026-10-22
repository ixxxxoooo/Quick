// SettingsSidebarController.swift
// Quick — 原生 macOS 效率启动器
// @author ixxxxoooo

import AppKit
import Observation

/// 设置侧栏（纯 AppKit）
///
/// 用 `NSTableView` 代替 SwiftUI `List`：点击只重绘受影响的两行，
/// 不再重算整份列表；选中底由自定义 `NSTableRowView` 绘制。
@MainActor
final class SettingsSidebarController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    private let dataSource: any PluginSettingsDataSource
    private let navigationState: SettingsNavigationState
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private var items: [SettingsSidebarItem] = []
    private var isSearching = false
    private var isSyncing = false

    init(dataSource: any PluginSettingsDataSource, navigationState: SettingsNavigationState) {
        self.dataSource = dataSource
        self.navigationState = navigationState
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let root = NSView()
        searchField.placeholderString = "搜索设置"
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: .init("main"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = .zero
        tableView.dataSource = self
        tableView.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(searchField)
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: DesignTokens.Spacing.md),
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: DesignTokens.Spacing.lg),
            searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -DesignTokens.Spacing.lg),
            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: DesignTokens.Spacing.md),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        view = root
        reloadBrowse()
        observeSelection()
    }

    /// ⌘F：聚焦搜索框
    func focusSearch() {
        view.window?.makeFirstResponder(searchField)
    }

    // MARK: - 数据

    private func reloadBrowse() {
        isSearching = false
        items = SettingsSidebarItem.browse(plugins: dataSource.pluginEntries)
        tableView.reloadData()
        syncSelection()
    }

    @objc private func searchChanged() {
        let query = searchField.stringValue
        guard !query.isEmpty else { return reloadBrowse() }
        isSearching = true
        items = SettingsSidebarItem.results(
            SettingsSearchCatalog.results(for: query, plugins: dataSource.pluginEntries))
        tableView.reloadData()
    }

    /// 让选中行跟随导航状态（工具栏前进 / 后退、`show(tab:)`）
    private func observeSelection() {
        withObservationTracking {
            _ = navigationState.tab
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.syncSelection()
                self?.observeSelection()
            }
        }
    }

    private func syncSelection() {
        guard !isSearching else { return }
        guard let row = items.firstIndex(where: { $0.tab == navigationState.tab }) else { return }
        isSyncing = true
        tableView.selectRowIndexes([row], byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        isSyncing = false
    }

    // MARK: - NSTableView

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .header = items[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        items[row].tab != nil
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch items[row] {
        case .header(let text): text.isEmpty ? DesignTokens.Spacing.md : 28
        case .page(_, _, _, let subtitle):
            (subtitle == nil ? 18 : 32) + DesignTokens.Size.settingsSidebarRowVertical * 2
        }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SettingsSidebarRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch items[row] {
        case .header(let text):
            let cell = (tableView.makeView(withIdentifier: .init("header"), owner: nil)
                as? SettingsSidebarHeaderCell) ?? SettingsSidebarHeaderCell()
            cell.identifier = .init("header")
            cell.configure(text)
            return cell
        case .page(_, let tab, let title, let subtitle):
            let cell = (tableView.makeView(withIdentifier: .init("page"), owner: nil)
                as? SettingsSidebarPageCell) ?? SettingsSidebarPageCell()
            cell.identifier = .init("page")
            cell.configure(tab: tab, title: title, subtitle: subtitle)
            return cell
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isSyncing, tableView.selectedRow >= 0, let tab = items[tableView.selectedRow].tab else { return }
        navigationState.tab = tab
    }
}
