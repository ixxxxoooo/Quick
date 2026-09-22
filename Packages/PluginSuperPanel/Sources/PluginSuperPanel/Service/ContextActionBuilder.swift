// ContextActionBuilder.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Foundation
import QuickCore

/// 根据智能预览与原文构建上下文动作（对齐 Fasty useSuperPanelActions）
@MainActor
enum ContextActionBuilder {

    /// 从预览列表生成操作
    static func actions(previews: [SmartPreview], sourceText: String) -> [SuperPanelAction] {
        var result: [SuperPanelAction] = []
        let primary = previews.first { $0.isMeaningful }

        for preview in previews {
            result.append(contentsOf: actions(for: preview, primary: primary))
        }

        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            result.append(
                SuperPanelAction(
                    id: "sp.copy-text",
                    title: "复制文本",
                    subtitle: trimmed.count > 40 ? String(trimmed.prefix(40)) + "…" : trimmed,
                    icon: "doc.on.doc",
                    category: .context,
                    execute: {
                        EventBus.shared.post(CopyToClipboardEvent(text: trimmed))
                    }
                )
            )
            result.append(
                SuperPanelAction(
                    id: "sp.search-web",
                    title: "在 Google 搜索",
                    subtitle: trimmed,
                    icon: "magnifyingglass",
                    category: .context,
                    execute: {
                        let q =
                            trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
                        if let url = URL(string: "https://www.google.com/search?q=\(q)") {
                            NSWorkspace.shared.open(url)
                            EventBus.shared.post(HidePaletteEvent())
                        }
                    }
                )
            )
        }

        return result
    }

    // MARK: - 单类型

    private static func actions(for preview: SmartPreview, primary: SmartPreview?) -> [SuperPanelAction] {
        switch preview {
        case .url(let url, let domain):
            return [
                SuperPanelAction(
                    id: "sp.open-url",
                    title: "打开网址",
                    subtitle: domain,
                    icon: "arrow.up.right.square",
                    category: .context,
                    execute: {
                        if let u = URL(string: url) {
                            NSWorkspace.shared.open(u)
                            EventBus.shared.post(HidePaletteEvent())
                        }
                    }
                )
            ]

        case .filePath(let path, let exists, let isDirectory):
            var items: [SuperPanelAction] = [
                SuperPanelAction(
                    id: "sp.reveal-path",
                    title: "在 Finder 中显示",
                    subtitle: path,
                    icon: "folder",
                    category: .context,
                    execute: {
                        if exists {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        } else {
                            NSWorkspace.shared.selectFile(
                                nil, inFileViewerRootedAtPath: (path as NSString).deletingLastPathComponent)
                        }
                        EventBus.shared.post(HidePaletteEvent())
                    }
                ),
                SuperPanelAction(
                    id: "sp.copy-path-context",
                    title: "复制路径",
                    subtitle: path,
                    icon: "doc.on.doc",
                    category: .context,
                    execute: {
                        EventBus.shared.post(CopyToClipboardEvent(text: path))
                    }
                )
            ]
            if exists {
                let terminalPath = isDirectory ? path : (path as NSString).deletingLastPathComponent
                items.insert(
                    SuperPanelAction(
                        id: "sp.terminal-path",
                        title: "在终端中打开",
                        subtitle: terminalPath,
                        icon: "terminal",
                        category: .context,
                        execute: {
                            ActionProvider.openInTerminal(path: terminalPath)
                        }
                    ),
                    at: 1
                )
            }
            return items

        case .color(let hex, _):
            return [
                SuperPanelAction(
                    id: "sp.copy-hex",
                    title: "复制色值",
                    subtitle: hex,
                    icon: "paintpalette",
                    category: .context,
                    execute: {
                        EventBus.shared.post(CopyToClipboardEvent(text: hex))
                    }
                ),
                SuperPanelAction(
                    id: "sp.open-color",
                    title: "打开颜色工具",
                    subtitle: hex,
                    icon: "eyedropper",
                    category: .context,
                    execute: {
                        EventBus.shared.post(NavigateEvent(pluginID: "color-compare"))
                    }
                )
            ]

        case .timestamp(_, let formatted, _):
            return [
                SuperPanelAction(
                    id: "sp.copy-timestamp",
                    title: "复制格式化时间",
                    subtitle: formatted,
                    icon: "clock",
                    category: .context,
                    execute: {
                        EventBus.shared.post(CopyToClipboardEvent(text: formatted))
                    }
                ),
                SuperPanelAction(
                    id: "sp.open-timestamp",
                    title: "打开时间戳转换",
                    subtitle: formatted,
                    icon: "calendar",
                    category: .context,
                    execute: {
                        EventBus.shared.post(NavigateEvent(pluginID: "timestamp-converter"))
                    }
                )
            ]

        case .base64(let decoded):
            return [
                SuperPanelAction(
                    id: "sp.copy-base64-decoded",
                    title: "复制解码结果",
                    subtitle: decoded,
                    icon: "lock.rectangle",
                    category: .context,
                    execute: {
                        EventBus.shared.post(CopyToClipboardEvent(text: decoded))
                    }
                ),
                SuperPanelAction(
                    id: "sp.open-base64",
                    title: "打开 Base64 工具",
                    subtitle: "继续编解码",
                    icon: "wrench.and.screwdriver",
                    category: .context,
                    execute: {
                        EventBus.shared.post(NavigateEvent(pluginID: "base64-codec"))
                    }
                )
            ]

        case .urlEncoded(let decoded):
            return [
                SuperPanelAction(
                    id: "sp.copy-url-decoded",
                    title: "复制解码结果",
                    subtitle: decoded,
                    icon: "percent",
                    category: .context,
                    execute: {
                        EventBus.shared.post(CopyToClipboardEvent(text: decoded))
                    }
                ),
                SuperPanelAction(
                    id: "sp.open-urlcodec",
                    title: "打开 URL 编解码",
                    subtitle: "继续编解码",
                    icon: "link",
                    category: .context,
                    execute: {
                        EventBus.shared.post(NavigateEvent(pluginID: "url-codec"))
                    }
                )
            ]

        case .math(_, let result):
            return [
                SuperPanelAction(
                    id: "sp.copy-math",
                    title: "复制计算结果",
                    subtitle: result,
                    icon: "plus.forwardslash.minus",
                    category: .context,
                    execute: {
                        EventBus.shared.post(CopyToClipboardEvent(text: result))
                    }
                )
            ]

        case .email(let email):
            return [
                SuperPanelAction(
                    id: "sp.mailto",
                    title: "发送邮件",
                    subtitle: email,
                    icon: "envelope",
                    category: .context,
                    execute: {
                        if let url = URL(string: "mailto:\(email)") {
                            NSWorkspace.shared.open(url)
                            EventBus.shared.post(HidePaletteEvent())
                        }
                    }
                )
            ]

        case .ip(let address):
            return [
                SuperPanelAction(
                    id: "sp.copy-ip",
                    title: "复制 IP",
                    subtitle: address,
                    icon: "network",
                    category: .context,
                    execute: {
                        EventBus.shared.post(CopyToClipboardEvent(text: address))
                    }
                ),
                SuperPanelAction(
                    id: "sp.open-network",
                    title: "打开网络工具",
                    subtitle: address,
                    icon: "antenna.radiowaves.left.and.right",
                    category: .context,
                    execute: {
                        EventBus.shared.post(NavigateEvent(pluginID: "networktools"))
                    }
                )
            ]

        case .json:
            return [
                SuperPanelAction(
                    id: "sp.open-json",
                    title: "用 JSON 格式化打开",
                    subtitle: "格式化 / 压缩",
                    icon: "curlybraces",
                    category: .context,
                    execute: {
                        EventBus.shared.post(NavigateEvent(pluginID: "json-formatter"))
                    }
                )
            ]

        case .phone(let formatted):
            return [
                SuperPanelAction(
                    id: "sp.copy-phone",
                    title: "复制号码",
                    subtitle: formatted,
                    icon: "phone",
                    category: .context,
                    execute: {
                        EventBus.shared.post(CopyToClipboardEvent(text: formatted))
                    }
                )
            ]

        case .translation(let source, let lang):
            // 与主预览重复时仍提供翻译入口
            _ = primary
            let target = lang == "en" ? "中文" : "英文"
            return [
                SuperPanelAction(
                    id: "sp.open-translator",
                    title: "翻译成\(target)",
                    subtitle: source,
                    icon: "character.book.closed",
                    category: .context,
                    execute: {
                        EventBus.shared.post(NavigateEvent(pluginID: "translator"))
                    }
                )
            ]

        case .plainText:
            return []
        }
    }
}

/// 工作台快捷工具（对齐 Fasty DEFAULT_CONFIGURED_TOOL_IDS）
enum SuperPanelQuickTools {

    struct Tool: Identifiable, Sendable {
        let id: String
        let title: String
        let icon: String
        let pluginID: String
    }

    /// 默认常用工具
    static let defaults: [Tool] = [
        Tool(id: "screenshot", title: "截图", icon: "camera", pluginID: "screenshot"),
        Tool(id: "clipboard", title: "剪贴板", icon: "doc.on.clipboard", pluginID: "clipboard"),
        Tool(id: "translator", title: "翻译", icon: "character.book.closed", pluginID: "translator"),
        Tool(id: "ai", title: "AI", icon: "sparkles", pluginID: "ai"),
        Tool(id: "notes", title: "备忘", icon: "text.page", pluginID: "notes"),
        Tool(id: "calculator", title: "计算", icon: "plus.forwardslash.minus", pluginID: "calculator"),
        Tool(id: "sysmonitor", title: "监控", icon: "cpu", pluginID: "sysmonitor"),
        Tool(id: "json", title: "JSON", icon: "curlybraces", pluginID: "json-formatter")
    ]

    /// 打开工具：导航到对应插件
    @MainActor
    static func open(_ tool: Tool) {
        EventBus.shared.post(NavigateEvent(pluginID: tool.pluginID))
    }
}
