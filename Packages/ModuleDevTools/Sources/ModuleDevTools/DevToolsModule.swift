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

/// DevTools 根视图（工具列表 + 内容区）
///
/// 视图创建时从模块的 `selectedToolID` 读取初始选中工具，
/// 确保从搜索结果点击某个子工具后能直接打开对应内容。
struct DevToolsRootView: View {
    let module: DevToolsModule
    let tools: [any DevTool]

    @State private var selectedID: String?

    var body: some View {
        HStack(spacing: 0) {
            // 左侧工具列表
            ScrollView {
                LazyVStack(spacing: DesignTokens.Spacing.xxs) {
                    ForEach(module.toolEntries) { entry in
                        HStack(spacing: DesignTokens.Spacing.md) {
                            Image(systemName: entry.icon)
                                .font(.system(size: 14))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                                .frame(width: 20)
                            Text(entry.name)
                                .font(DesignTokens.Typography.rowTitle)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        .padding(.vertical, DesignTokens.Spacing.md)
                        .background {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.row)
                                .fill(selectedID == entry.id ? DesignTokens.Colors.selection : .clear)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedID = entry.id }
                    }
                }
                .padding(DesignTokens.Spacing.md)
            }
            .frame(width: 180)

            Divider().opacity(0.3)

            // 右侧工具内容
            if let id = selectedID, let tool = module.tool(for: id) {
                tool.makeView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: DesignTokens.Spacing.md) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    Text("选择一个开发工具")
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if selectedID == nil, let toolID = module.selectedToolID {
                selectedID = toolID
            }
        }
    }
}
