// SQLFormatterTool.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// SQL 格式化工具
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

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            HStack {
                Text("SQL 格式化")
                    .font(DesignTokens.Typography.panelTitle)
                Spacer()
                Button("格式化") { formatSQL() }
                    .buttonStyle(.borderedProminent)
                Button("复制") {
                    EventBus.shared.post(CopyToClipboardEvent(text: output))
                }
                .buttonStyle(.bordered)
            }

            HSplitView {
                TextEditor(text: $input)
                    .font(DesignTokens.Typography.code)
                    .scrollContentBackground(.hidden)
                    .frame(minWidth: 200)

                TextEditor(text: .constant(output))
                    .font(DesignTokens.Typography.code)
                    .scrollContentBackground(.hidden)
                    .frame(minWidth: 200)
            }
        }
        .padding(DesignTokens.Spacing.xl)
    }

    private func formatSQL() {
        let keywords = ["SELECT", "FROM", "WHERE", "AND", "OR", "JOIN", "LEFT JOIN",
                       "RIGHT JOIN", "INNER JOIN", "ON", "GROUP BY", "ORDER BY",
                       "HAVING", "INSERT INTO", "VALUES", "UPDATE", "SET", "DELETE FROM",
                       "CREATE TABLE", "ALTER TABLE", "DROP TABLE", "LIMIT", "OFFSET", "UNION"]

        var result = input
        for keyword in keywords {
            result = result.replacingOccurrences(
                of: keyword,
                with: "\n\(keyword)",
                options: .caseInsensitive
            )
        }

        // 清理多余空行
        result = result.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        output = result
    }
}
