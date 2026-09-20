// TextDiffTool.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 文本对比工具
///
/// 参考 Fasty text-diff 布局：
/// 工具栏（互换/复制/清空 + 差异统计）→ 左右双栏编辑区 → 差异结果
struct TextDiffTool: DevTool {
    let id = "diff"
    let name = "文本对比"
    let icon = "doc.on.doc"
    let keywords = ["diff", "对比", "比较", "差异", "text diff"]
    let description = "左右双栏对比文本差异"

    func makeView() -> AnyView {
        AnyView(TextDiffView())
    }
}

struct TextDiffView: View {
    @State private var textA = ""
    @State private var textB = ""
    @State private var diffResult: [DiffLine] = []
    @State private var addedCount = 0
    @State private var removedCount = 0

    struct DiffLine: Identifiable {
        let id = UUID()
        let text: String
        let type: LineType

        enum LineType {
            case same, added, removed
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack(spacing: DesignTokens.Spacing.sm) {
                Button {
                    swapTexts()
                } label: {
                    Label("互换", systemImage: "arrow.left.arrow.right")
                }.buttonStyle(.bordered).controlSize(.small)

                Button {
                    copyDiff()
                } label: {
                    Label("复制差异", systemImage: "doc.on.doc")
                }.buttonStyle(.bordered).controlSize(.small)
                    .disabled(diffResult.isEmpty)

                Button {
                    textA = ""; textB = ""; diffResult = []; addedCount = 0; removedCount = 0
                } label: {
                    Label("清空", systemImage: "trash")
                }.buttonStyle(.bordered).controlSize(.small)

                Spacer()

                // 差异统计标签
                if textA.isEmpty && textB.isEmpty {
                    EmptyView()
                } else if addedCount == 0 && removedCount == 0 && !textA.isEmpty {
                    Text("完全相同")
                        .font(.caption)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    if removedCount > 0 {
                        Text("-\(removedCount)")
                            .font(.caption)
                            .padding(.horizontal, DesignTokens.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.15))
                            .foregroundStyle(.red)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    if addedCount > 0 {
                        Text("+\(addedCount)")
                            .font(.caption)
                            .padding(.horizontal, DesignTokens.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)

            Divider().opacity(0.3)

            // 双栏编辑区
            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("原文")
                        .font(.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, DesignTokens.Spacing.xs)
                    TextEditor(text: $textA)
                        .font(DesignTokens.Typography.code)
                        .scrollContentBackground(.hidden)
                }
                .frame(minWidth: 200)

                VStack(alignment: .leading, spacing: 0) {
                    Text("修改后")
                        .font(.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, DesignTokens.Spacing.xs)
                    TextEditor(text: $textB)
                        .font(DesignTokens.Typography.code)
                        .scrollContentBackground(.hidden)
                }
                .frame(minWidth: 200)
            }

            // 差异结果
            if !diffResult.isEmpty {
                Divider().opacity(0.3)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(diffResult) { line in
                            HStack(spacing: 0) {
                                Text(linePrefix(line.type))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(lineColor(line.type))
                                    .frame(width: 16)
                                Text(line.text)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DesignTokens.Spacing.md)
                            .padding(.vertical, 1)
                            .background(lineBackground(line.type))
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .onChange(of: textA) { _, _ in computeDiff() }
        .onChange(of: textB) { _, _ in computeDiff() }
    }

    private func linePrefix(_ type: DiffLine.LineType) -> String {
        switch type {
        case .same: " "
        case .added: "+"
        case .removed: "-"
        }
    }

    private func lineColor(_ type: DiffLine.LineType) -> Color {
        switch type {
        case .same: DesignTokens.Colors.textTertiary
        case .added: .green
        case .removed: .red
        }
    }

    private func lineBackground(_ type: DiffLine.LineType) -> Color {
        switch type {
        case .same: .clear
        case .added: Color.green.opacity(0.08)
        case .removed: Color.red.opacity(0.08)
        }
    }

    private func swapTexts() {
        let temp = textA
        textA = textB
        textB = temp
    }

    private func copyDiff() {
        let text = diffResult.map { "\(linePrefix($0.type))\($0.text)" }.joined(separator: "\n")
        EventBus.shared.post(CopyToClipboardEvent(text: text))
    }

    private func computeDiff() {
        let linesA = textA.components(separatedBy: "\n")
        let linesB = textB.components(separatedBy: "\n")
        var result: [DiffLine] = []
        var added = 0
        var removed = 0

        let maxLines = max(linesA.count, linesB.count)
        for i in 0..<maxLines {
            let a = i < linesA.count ? linesA[i] : nil
            let b = i < linesB.count ? linesB[i] : nil

            if a == b {
                result.append(DiffLine(text: a ?? "", type: .same))
            } else {
                if let a { result.append(DiffLine(text: a, type: .removed)); removed += 1 }
                if let b { result.append(DiffLine(text: b, type: .added)); added += 1 }
            }
        }
        diffResult = result
        addedCount = added
        removedCount = removed
    }
}
