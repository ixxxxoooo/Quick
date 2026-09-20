// TextDiffTool.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickUI
import SwiftUI

/// 文本对比工具
struct TextDiffTool: DevTool {
    let id = "diff"
    let name = "文本对比"
    let icon = "doc.on.doc.fill"
    let keywords = ["diff", "对比", "比较", "差异", "text diff"]
    let description = "对比两段文本的差异"

    func makeView() -> AnyView {
        AnyView(TextDiffView())
    }
}

struct TextDiffView: View {
    @State private var textA = ""
    @State private var textB = ""
    @State private var diffResult: [DiffLine] = []

    struct DiffLine: Identifiable {
        let id = UUID()
        let text: String
        let type: LineType

        enum LineType {
            case same, added, removed
        }
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            HStack {
                Text("文本对比")
                    .font(DesignTokens.Typography.panelTitle)
                Spacer()
                Button("对比") { computeDiff() }.buttonStyle(.borderedProminent)
            }

            HSplitView {
                VStack(alignment: .leading) {
                    Text("文本 A").font(DesignTokens.Typography.sectionHeader)
                    TextEditor(text: $textA)
                        .font(DesignTokens.Typography.code)
                        .scrollContentBackground(.hidden)
                }
                .frame(minWidth: 200)

                VStack(alignment: .leading) {
                    Text("文本 B").font(DesignTokens.Typography.sectionHeader)
                    TextEditor(text: $textB)
                        .font(DesignTokens.Typography.code)
                        .scrollContentBackground(.hidden)
                }
                .frame(minWidth: 200)
            }

            if !diffResult.isEmpty {
                Divider().opacity(0.3)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(diffResult) { line in
                            Text(line.text)
                                .font(DesignTokens.Typography.code)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, DesignTokens.Spacing.md)
                                .padding(.vertical, 2)
                                .background(lineBackground(line.type))
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .padding(DesignTokens.Spacing.xl)
    }

    private func lineBackground(_ type: DiffLine.LineType) -> Color {
        switch type {
        case .same: .clear
        case .added: Color.green.opacity(0.15)
        case .removed: Color.red.opacity(0.15)
        }
    }

    private func computeDiff() {
        let linesA = textA.components(separatedBy: "\n")
        let linesB = textB.components(separatedBy: "\n")
        var result: [DiffLine] = []

        let maxLines = max(linesA.count, linesB.count)
        for i in 0..<maxLines {
            let a = i < linesA.count ? linesA[i] : nil
            let b = i < linesB.count ? linesB[i] : nil

            if a == b {
                result.append(DiffLine(text: "  \(a ?? "")", type: .same))
            } else {
                if let a { result.append(DiffLine(text: "- \(a)", type: .removed)) }
                if let b { result.append(DiffLine(text: "+ \(b)", type: .added)) }
            }
        }
        diffResult = result
    }
}
