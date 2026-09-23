// SuperPanelContextBuilder.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Foundation

/// 超级面板执行动作时需要的外部能力
///
/// 面板自己不持有窗口之外的任何东西：怎么复制、怎么隐藏、怎么跳插件都由宿主注入，
/// 这样构建动作这一层不依赖 AppCore，也不会把窗口逻辑缠进动作定义里。
@MainActor
public struct SuperPanelActionContext {

    /// 复制文本：写剪贴板、弹一个 toast、收起面板
    public let copy: (String) -> Void
    /// 用文本替换原应用的选区（收起面板、交还焦点、合成粘贴）
    public let replaceOriginal: (String) -> Void
    /// 跳转到某个插件（收起面板后由宿主打开主面板）
    public let navigate: (String) -> Void
    /// 打开链接（收起面板后交给系统）
    public let openURL: (URL) -> Void
    /// 只收起面板（动作自己完成了副作用，例如在 Finder 中显示）
    public let dismiss: () -> Void

    public init(
        copy: @escaping (String) -> Void,
        replaceOriginal: @escaping (String) -> Void,
        navigate: @escaping (String) -> Void,
        openURL: @escaping (URL) -> Void,
        dismiss: @escaping () -> Void
    ) {
        self.copy = copy
        self.replaceOriginal = replaceOriginal
        self.navigate = navigate
        self.openURL = openURL
        self.dismiss = dismiss
    }
}

/// 根据智能预览与原文构建上下文动作（对齐 Fasty useSuperPanelActions）
@MainActor
public enum SuperPanelContextBuilder {

    /// 从预览列表生成操作
    public static func actions(
        previews: [SmartPreview],
        sourceText: String,
        context: SuperPanelActionContext
    ) -> [SuperPanelAction] {
        var result: [SuperPanelAction] = []

        for preview in previews where preview.isMeaningful {
            result.append(contentsOf: actions(for: preview, context: context))
        }

        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return result }

        let snippet = trimmed.count > 40 ? String(trimmed.prefix(40)) + "…" : trimmed

        result.append(
            SuperPanelAction(
                id: "sp.copy-text",
                title: "复制文本",
                subtitle: snippet,
                icon: "doc.on.doc",
                execute: { context.copy(trimmed) }
            )
        )
        result.append(
            SuperPanelAction(
                id: "sp.search-web",
                title: "在 Google 搜索",
                subtitle: snippet,
                icon: "magnifyingglass",
                execute: {
                    let q = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
                    if let url = URL(string: "https://www.google.com/search?q=\(q)") {
                        context.openURL(url)
                    }
                }
            )
        )

        return result
    }

    // MARK: - 单类型

    private static func actions(
        for preview: SmartPreview,
        context: SuperPanelActionContext
    ) -> [SuperPanelAction] {
        switch preview {
        case .url(let url, let domain):
            return [
                SuperPanelAction(
                    id: "sp.open-url",
                    title: "打开网址",
                    subtitle: domain,
                    icon: "arrow.up.right.square",
                    execute: {
                        if let u = URL(string: url) { context.openURL(u) }
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
                    execute: {
                        if exists {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        } else {
                            NSWorkspace.shared.selectFile(
                                nil, inFileViewerRootedAtPath: (path as NSString).deletingLastPathComponent)
                        }
                        context.dismiss()
                    }
                ),
                SuperPanelAction(
                    id: "sp.copy-path-context",
                    title: "复制路径",
                    subtitle: path,
                    icon: "doc.on.doc",
                    execute: { context.copy(path) }
                )
            ]
            if exists {
                // 打开：默认应用打开文件 / 在 Finder 里打开文件夹
                items.insert(
                    SuperPanelAction(
                        id: "sp.open-path",
                        title: isDirectory ? "打开文件夹" : "打开文件",
                        subtitle: path,
                        icon: "arrow.up.forward.app",
                        execute: {
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                            context.dismiss()
                        }
                    ),
                    at: 0
                )
                let terminalPath = isDirectory ? path : (path as NSString).deletingLastPathComponent
                items.insert(
                    SuperPanelAction(
                        id: "sp.terminal-path",
                        title: "在终端中打开",
                        subtitle: terminalPath,
                        icon: "terminal",
                        execute: {
                            openInTerminal(path: terminalPath)
                            context.dismiss()
                        }
                    ),
                    at: 2
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
                    execute: { context.copy(hex) }
                ),
                SuperPanelAction(
                    id: "sp.open-color",
                    title: "打开颜色工具",
                    subtitle: hex,
                    icon: "eyedropper",
                    execute: { context.navigate("color-compare") }
                )
            ]

        case .timestamp(_, let formatted, _):
            return [
                SuperPanelAction(
                    id: "sp.copy-timestamp",
                    title: "复制格式化时间",
                    subtitle: formatted,
                    icon: "clock",
                    execute: { context.copy(formatted) }
                ),
                SuperPanelAction(
                    id: "sp.open-timestamp",
                    title: "打开时间戳转换",
                    subtitle: formatted,
                    icon: "calendar",
                    execute: { context.navigate("timestamp-converter") }
                )
            ]

        case .base64(let decoded):
            return [
                SuperPanelAction(
                    id: "sp.copy-base64-decoded",
                    title: "复制解码结果",
                    subtitle: decoded,
                    icon: "lock.rectangle",
                    execute: { context.copy(decoded) }
                ),
                SuperPanelAction(
                    id: "sp.open-base64",
                    title: "打开 Base64 工具",
                    subtitle: "继续编解码",
                    icon: "wrench.and.screwdriver",
                    execute: { context.navigate("base64-codec") }
                )
            ]

        case .urlEncoded(let decoded):
            return [
                SuperPanelAction(
                    id: "sp.copy-url-decoded",
                    title: "复制解码结果",
                    subtitle: decoded,
                    icon: "percent",
                    execute: { context.copy(decoded) }
                ),
                SuperPanelAction(
                    id: "sp.open-urlcodec",
                    title: "打开 URL 编解码",
                    subtitle: "继续编解码",
                    icon: "link",
                    execute: { context.navigate("url-codec") }
                )
            ]

        case .math(_, let result):
            return [
                SuperPanelAction(
                    id: "sp.copy-math",
                    title: "复制计算结果",
                    subtitle: result,
                    icon: "plus.forwardslash.minus",
                    execute: { context.copy(result) }
                )
            ]

        case .email(let email):
            return [
                SuperPanelAction(
                    id: "sp.mailto",
                    title: "发送邮件",
                    subtitle: email,
                    icon: "envelope",
                    execute: {
                        if let url = URL(string: "mailto:\(email)") { context.openURL(url) }
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
                    execute: { context.copy(address) }
                ),
                SuperPanelAction(
                    id: "sp.open-network",
                    title: "打开网络工具",
                    subtitle: address,
                    icon: "antenna.radiowaves.left.and.right",
                    execute: { context.navigate("networktools") }
                )
            ]

        case .json:
            return [
                SuperPanelAction(
                    id: "sp.open-json",
                    title: "用 JSON 格式化打开",
                    subtitle: "格式化 / 压缩",
                    icon: "curlybraces",
                    execute: { context.navigate("json-formatter") }
                )
            ]

        case .sql:
            return [
                SuperPanelAction(
                    id: "sp.open-sql",
                    title: "用 SQL 格式化打开",
                    subtitle: "格式化 / 压缩",
                    icon: "cylinder",
                    execute: { context.navigate("sql-formatter") }
                )
            ]

        case .phone(let formatted):
            return [
                SuperPanelAction(
                    id: "sp.copy-phone",
                    title: "复制号码",
                    subtitle: formatted,
                    icon: "phone",
                    execute: { context.copy(formatted) }
                )
            ]

        case .translation(let source, let lang):
            let target = lang == "en" ? "中文" : "英文"
            return [
                SuperPanelAction(
                    id: "sp.open-translator",
                    title: "翻译成\(target)",
                    subtitle: source,
                    icon: "character.book.closed",
                    execute: { context.navigate("translator") }
                )
            ]

        case .plainText:
            return []
        }
    }

    /// 在终端中打开目录（Fasty 用系统 Terminal）
    static func openInTerminal(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
