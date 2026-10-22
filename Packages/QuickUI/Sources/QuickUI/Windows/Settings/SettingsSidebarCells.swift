// SettingsSidebarCells.swift
// Quick — 原生 macOS 效率启动器
// @author ixxxxoooo

import AppKit
import SwiftUI

/// 选中态：中性浅灰圆角底，不用系统强调蓝
final class SettingsSidebarRowView: NSTableRowView {

    override var isEmphasized: Bool {
        get { false }
        set {}
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        let rect = bounds.insetBy(dx: DesignTokens.Spacing.sm, dy: DesignTokens.Spacing.xxs / 2)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor(DesignTokens.Colors.settingsSidebarSelection).setFill()
            NSBezierPath(
                roundedRect: rect, xRadius: DesignTokens.Radius.menu, yRadius: DesignTokens.Radius.menu
            ).fill()
        }
    }
}

/// 彩色色块图标（AppKit 绘制，对应 `SettingsTileIcon`）
final class SettingsSidebarTileView: NSView {

    var symbolName = "" { didSet { needsDisplay = true } }
    var tint: SettingsTileIcon.Tint = .blue { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize {
        NSSize(width: DesignTokens.Size.settingsIconTile, height: DesignTokens.Size.settingsIconTile)
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(
            roundedRect: bounds, xRadius: DesignTokens.Radius.settingsIconTile,
            yRadius: DesignTokens.Radius.settingsIconTile)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let base = NSColor(tint.color)
            NSGradient(starting: base.withAlphaComponent(0.96), ending: base)?  // ui-literal-ok: 渐变色标
                .draw(in: shape, angle: -90)
        }
        let config = NSImage.SymbolConfiguration(
            pointSize: DesignTokens.Size.settingsIconGlyph, weight: .medium
        ).applying(.init(paletteColors: [.white]))
        guard let glyph = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        else { return }
        let size = glyph.size
        glyph.draw(in: NSRect(
            x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
            width: size.width, height: size.height))
    }
}

/// 页面行：色块 + 标题（+ 副标题）
final class SettingsSidebarPageCell: NSTableCellView {

    private let tile = SettingsSidebarTileView()
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        title.font = .systemFont(ofSize: 13)
        subtitle.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        subtitle.textColor = .secondaryLabelColor
        for label in [title, subtitle] {
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
        }
        let text = NSStackView(views: [title, subtitle])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 0
        let row = NSStackView(views: [tile, text])
        row.spacing = DesignTokens.Size.settingsSidebarIconGap
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: DesignTokens.Size.settingsSidebarRowHorizontal + DesignTokens.Spacing.sm),
            row.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor, constant: -DesignTokens.Spacing.md),
            row.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 填充内容
    func configure(tab: SettingsTab, title: String, subtitle: String?) {
        tile.symbolName = tab.systemImage
        tile.tint = .named(tab.iconTintName)
        self.title.stringValue = title
        self.subtitle.stringValue = subtitle ?? ""
        self.subtitle.isHidden = subtitle == nil
    }
}

/// 分区标题行
final class SettingsSidebarHeaderCell: NSTableCellView {

    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: DesignTokens.Size.settingsSidebarRowHorizontal + DesignTokens.Spacing.sm),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DesignTokens.Spacing.xs)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ text: String) { label.stringValue = text }
}
