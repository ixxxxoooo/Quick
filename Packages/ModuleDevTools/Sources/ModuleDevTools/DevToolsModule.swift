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

    /// 所有已注册的子工具
    private let tools: [any DevTool]

    /// 当前选中的子工具 ID
    var selectedToolID: String?

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
            ColorCompareTool(),
        ]
    }

    // MARK: - QuickModule 协议

    public func searchItems(query: String) async -> [SearchableItem] {
        var results: [SearchableItem] = []

        for tool in tools {
            let matchScore = tool.keywords.compactMap { keyword -> Double? in
                let score = keyword.fuzzyScore(query)
                return score > 0 ? score : nil
            }.max() ?? 0

            if matchScore > 0 {
                results.append(SearchableItem(
                    id: "devtools.\(tool.id)",
                    moduleID: Self.id,
                    title: tool.name,
                    subtitle: tool.description,
                    icon: tool.icon,
                    relevance: matchScore * 0.75,
                    action: { [weak self] in
                        self?.selectedToolID = tool.id
                        EventBus.shared.post(NavigateEvent(
                            moduleID: "devtools",
                            context: ["tool": tool.id]
                        ))
                    }
                ))
            }
        }
        return results
    }

    public func makeView() -> AnyView {
        AnyView(DevToolsRootView(module: self, tools: tools))
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
    }
}
