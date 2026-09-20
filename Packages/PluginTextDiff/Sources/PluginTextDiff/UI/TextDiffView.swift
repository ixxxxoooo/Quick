// TextDiffView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct TextDiffView: View {
    @State private var textA = ""
    @State private var textB = ""
    @State private var diffResult: [TextDiffLogic.DiffLine] = []
    @State private var addedCount = 0
    @State private var removedCount = 0

    /// 差异行类型来自模型层，视图只负责画
    private typealias DiffLine = TextDiffLogic.DiffLine

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
        TextDiffLogic.linePrefix(type)
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
        EventBus.shared.post(CopyToClipboardEvent(text: TextDiffLogic.render(diffResult)))
    }

    /// 对比算法整体在模型层，视图只把结果搬进 `@State`
    private func computeDiff() {
        let result = TextDiffLogic.diff(textA, against: textB)
        diffResult = result.lines
        addedCount = result.addedCount
        removedCount = result.removedCount
    }
}
