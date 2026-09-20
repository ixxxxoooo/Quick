// SQLFormatterTool.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// SQL 格式化工具
///
/// 参考 Fasty sql-formatter 布局：
/// 工具栏（格式化/压缩/复制/清空 + 方言/缩进选择）→ 编辑区 → 状态栏
struct SQLFormatterTool: DevTool {
    let id = "sql"
    let name = "SQL 格式化"
    let icon = "cylinder"
    let keywords = ["sql", "格式化", "sql formatter", "sql格式化", "数据库"]
    let description = "格式化 SQL 查询语句"

    func makeView() -> AnyView {
        AnyView(SQLFormatterView())
    }
}

struct SQLFormatterView: View {
    @State private var input = ""
    @State private var output = ""
    @State private var indent = 2
    @State private var statementCount = 0

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack(spacing: DesignTokens.Spacing.sm) {
                Button {
                    formatSQL()
                } label: {
                    Label("格式化", systemImage: "text.alignleft")
                }.buttonStyle(.borderedProminent).controlSize(.small)

                Button {
                    compactSQL()
                } label: {
                    Label("压缩", systemImage: "arrow.down.right.and.arrow.up.left")
                }.buttonStyle(.bordered).controlSize(.small)

                Button {
                    EventBus.shared.post(CopyToClipboardEvent(text: output.isEmpty ? input : output))
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }.buttonStyle(.bordered).controlSize(.small)

                Button {
                    input = ""; output = ""; statementCount = 0
                } label: {
                    Label("清空", systemImage: "trash")
                }.buttonStyle(.bordered).controlSize(.small)

                Spacer()

                Picker("缩进", selection: $indent) {
                    Text("2 空格").tag(2)
                    Text("4 空格").tag(4)
                }.pickerStyle(.segmented).frame(width: 140)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)

            Divider().opacity(0.3)

            // 编辑区（双栏）
            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("输入 SQL")
                        .font(.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, DesignTokens.Spacing.xs)
                    TextEditor(text: $input)
                        .font(DesignTokens.Typography.code)
                        .scrollContentBackground(.hidden)
                }
                .frame(minWidth: 200)

                VStack(alignment: .leading, spacing: 0) {
                    Text("输出")
                        .font(.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, DesignTokens.Spacing.xs)
                    TextEditor(text: .constant(output))
                        .font(DesignTokens.Typography.code)
                        .scrollContentBackground(.hidden)
                }
                .frame(minWidth: 200)
            }

            Divider().opacity(0.3)

            // 状态栏
            HStack(spacing: DesignTokens.Spacing.lg) {
                if statementCount > 0 {
                    Text("\(statementCount) 条语句")
                        .font(.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                if !input.isEmpty {
                    Text(byteSize(input))
                        .font(.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                if !output.isEmpty {
                    Text("已格式化")
                        .font(.caption).foregroundStyle(.green)
                }
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.xs)
        }
        .onChange(of: input) { _, _ in autoFormat() }
    }

    private func autoFormat() {
        guard !input.isEmpty else { output = ""; statementCount = 0; return }
        formatSQL()
    }

    private func formatSQL() {
        let indentStr = String(repeating: " ", count: indent)
        let keywords = [
            "SELECT", "FROM", "WHERE", "AND", "OR", "JOIN", "LEFT JOIN",
            "RIGHT JOIN", "INNER JOIN", "OUTER JOIN", "CROSS JOIN", "ON",
            "GROUP BY", "ORDER BY", "HAVING", "INSERT INTO", "VALUES",
            "UPDATE", "SET", "DELETE FROM", "CREATE TABLE", "ALTER TABLE",
            "DROP TABLE", "LIMIT", "OFFSET", "UNION", "UNION ALL",
            "CASE", "WHEN", "THEN", "ELSE", "END", "AS"
        ]

        var result = input
        // 在关键词前加换行和缩进
        for keyword in keywords {
            result = result.replacingOccurrences(
                of: "\\b\(keyword)\\b",
                with: "\n\(indentStr)\(keyword)",
                options: [.caseInsensitive, .regularExpression]
            )
        }

        // 清理多余空行和前导空格
        result = result.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .init(charactersIn: " ")) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        output = result
        statementCount =
            input.components(separatedBy: ";").filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.count
    }

    private func compactSQL() {
        let compact = input.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        output = compact
    }

    private func byteSize(_ text: String) -> String {
        let bytes = text.utf8.count
        if bytes < 1024 { return "\(bytes) B" }
        return String(format: "%.1f KB", Double(bytes) / 1024)
    }
}
