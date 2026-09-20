// DevToolsModule.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 开发者工具集模块
///
/// 集合 12 个轻量开发工具为一个 Module，
/// 内部按子功能文件夹隔离，对外呈现为统一入口。
@MainActor
public final class DevToolsModule: QuickModule {

    public static let id = "devtools"
    public static let name = "开发工具"
    public static let icon = "wrench.and.screwdriver"
    public static let triggerWords = [
        "json", "格式化", "format", "base64", "编码", "encode", "decode", "解码",
        "url", "hash", "md5", "sha", "时间戳", "timestamp", "uuid", "正则", "regex",
        "颜色", "color", "sql", "开发", "devtools"
    ]

    public var isEnabled = true

    private let log = QuickLog.module(DevToolsModule.id)

    /// 所有已注册的子工具
    private let tools: [any DevTool]

    /// 当前选中的子工具 ID
    var selectedToolID: String?

    /// 全部子工具关键词的并集
    ///
    /// 闸门与逐个工具的打分必须同源，否则会出现「过了闸门却没有一行」。
    private var allKeywords: [String] { tools.flatMap(\.keywords) }

    /// 只打了触发词、没有剩余查询词时的基础相关度
    private static let defaultRelevance = 0.5

    public init() {
        tools = [
            JSONFormatterTool(),
            SQLFormatterTool(),
            Base64Tool(),
            URLCodecTool(),
            UUIDGeneratorTool(),
            HashCalculatorTool(),
            TimestampConverterTool(),
            WordCounterTool(),
            TextDiffTool(),
            MarkdownPreviewTool(),
            ColorCompareTool()
        ]
    }

    // MARK: - QuickModule 协议

    public func searchItems(query: String) async -> [SearchableItem] {
        guard query.matchesAnyTrigger(allKeywords) else { return [] }

        // 用剥离触发词后的词打分：整段查询（如 `json 格式化`）永远匹配不上任何单个关键词
        let keyword = query.removingTrigger(allKeywords)

        var results: [SearchableItem] = []

        for tool in tools {
            let matchScore =
                tool.keywords.compactMap { word -> Double? in
                    let score = word.fuzzyScore(keyword)
                    return score > 0 ? score : nil
                }.max() ?? 0

            // 只剩触发词时列出全部工具，给基础分而不是 0
            let relevance = keyword.isEmpty ? Self.defaultRelevance : matchScore * 0.75
            guard keyword.isEmpty || matchScore > 0 else { continue }

            results.append(
                SearchableItem(
                    id: "devtools.\(tool.id)",
                    moduleID: Self.id,
                    title: tool.name,
                    subtitle: tool.description,
                    icon: tool.icon,
                    relevance: relevance,
                    action: { [weak self] in
                        self?.selectedToolID = tool.id
                        EventBus.shared.post(
                            NavigateEvent(
                                moduleID: "devtools",
                                context: ["tool": tool.id]
                            ))
                    }
                ))
        }
        return results
    }

    public func makeView() -> AnyView {
        AnyView(DevToolsRootView(module: self, tools: tools))
    }

    public func activate() {
        log.notice("模块已激活，已注册 \(self.tools.count, privacy: .public) 个子工具")
    }

    public func deactivate() {
        log.notice("模块已停用")
    }

    /// 获取指定 ID 的子工具
    func tool(for id: String) -> (any DevTool)? {
        tools.first { $0.id == id }
    }

    /// 所有工具条目信息
    var toolEntries: [ToolEntryInfo] {
        tools.map { ToolEntryInfo(id: $0.id, name: $0.name, icon: $0.icon, description: $0.description) }
    }
}

/// DevTools 根视图
///
/// 两种显示模式：
/// 1. 直接打开指定子工具（从搜索结果进入，selectedToolID 不为空）
/// 2. 工具选择界面（从"开发工具"入口进入，没有指定具体工具）
///
/// 每个子工具独立占据完整面板，不再使用左右分栏。
struct DevToolsRootView: View {
    let module: DevToolsModule
    let tools: [any DevTool]

    @State private var selectedID: String?

    var body: some View {
        Group {
            if let id = selectedID, let tool = module.tool(for: id) {
                // 直接显示子工具的完整面板
                VStack(spacing: 0) {
                    // 子工具标题栏（有返回按钮可回到工具列表）
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Button {
                            selectedID = nil
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                        .buttonStyle(.plain)

                        Image(systemName: tool.icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DesignTokens.Colors.textSecondary)

                        Text(tool.name)
                            .font(DesignTokens.Typography.sectionHeader)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)

                        Spacer()
                    }
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                    .frame(height: DesignTokens.Size.detachedTitleBarHeight)

                    Divider().opacity(0.3)

                    tool.makeView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                // 工具选择网格
                toolGrid
            }
        }
        .onAppear {
            if selectedID == nil, let toolID = module.selectedToolID {
                selectedID = toolID
            }
        }
    }

    /// 工具选择网格
    private var toolGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: DesignTokens.Spacing.md),
                    GridItem(.flexible(), spacing: DesignTokens.Spacing.md),
                    GridItem(.flexible(), spacing: DesignTokens.Spacing.md)
                ],
                spacing: DesignTokens.Spacing.md
            ) {
                ForEach(module.toolEntries) { entry in
                    Button {
                        selectedID = entry.id
                    } label: {
                        VStack(spacing: DesignTokens.Spacing.sm) {
                            Image(systemName: entry.icon)
                                .font(.system(size: 24))
                                .foregroundStyle(Color.accentColor)
                                .frame(height: 32)

                            Text(entry.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                                .lineLimit(1)

                            Text(entry.description)
                                .font(.system(size: 10))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .padding(DesignTokens.Spacing.md)
                        .frame(maxWidth: .infinity, minHeight: 100)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                                .fill(DesignTokens.Colors.cardFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                                .strokeBorder(DesignTokens.Colors.cardStroke, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
    }
}
