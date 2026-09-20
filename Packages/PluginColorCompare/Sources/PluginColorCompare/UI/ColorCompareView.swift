// ColorCompareView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

extension ParsedColor {
    /// 色块用的 SwiftUI 颜色
    ///
    /// 留在视图层而不是 Model：Model/ 目录禁止引 SwiftUI，数值本身在那边算好。
    var color: Color { Color(red: r / 255, green: g / 255, blue: b / 255) }
}

struct ColorCompareView: View {
    @State private var input = ""
    @State private var colors: [ParsedColor] = []
    @State private var copiedKey: String?

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack(spacing: DesignTokens.Spacing.sm) {
                if !colors.isEmpty {
                    Text("识别到 \(colors.count) 个颜色")
                        .font(.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                Spacer()
                Button {
                    copyAll()
                } label: {
                    Label("全部复制", systemImage: "doc.on.doc")
                }.buttonStyle(.bordered).controlSize(.small)
                    .disabled(colors.isEmpty)

                Button {
                    input = ""; colors = []
                } label: {
                    Label("清空", systemImage: "trash")
                }.buttonStyle(.bordered).controlSize(.small)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)

            // 输入区
            TextEditor(text: $input)
                .font(DesignTokens.Typography.code)
                .scrollContentBackground(.hidden)
                .frame(height: 60)
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .overlay(alignment: .topLeading) {
                    if input.isEmpty {
                        Text("输入颜色值（支持 #HEX、rgb()、多个颜色用空格/逗号分隔）…")
                            .font(DesignTokens.Typography.code)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .padding(.horizontal, DesignTokens.Spacing.lg + 5)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }

            Divider().opacity(0.3).padding(.horizontal, DesignTokens.Spacing.lg)

            if colors.isEmpty {
                VStack(spacing: DesignTokens.Spacing.md) {
                    Text("粘贴颜色值自动识别")
                        .font(.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
                    Text("支持 #FF5733、rgb(255,87,51) 等格式")
                        .font(.system(size: 10)).foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    // 颜色卡片网格
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 160), spacing: DesignTokens.Spacing.md)],
                        spacing: DesignTokens.Spacing.md
                    ) {
                        ForEach(colors) { color in
                            colorCard(color)
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                    .padding(.vertical, DesignTokens.Spacing.md)

                    // 亮度排序（≥2 个颜色）
                    if colors.count >= 2 {
                        luminanceSection
                    }
                }
            }
        }
        .onChange(of: input) { _, _ in parseColors() }
    }

    private func colorCard(_ color: ParsedColor) -> some View {
        VStack(spacing: 0) {
            // 色块预览
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .fill(color.color)
                .frame(height: 60)

            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    EventBus.shared.post(CopyToClipboardEvent(text: color.hex))
                    copiedKey = color.hex
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.5))
                        if copiedKey == color.hex { copiedKey = nil }
                    }
                } label: {
                    HStack {
                        Text(color.hex)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                        Spacer()
                        Image(systemName: copiedKey == color.hex ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(
                                copiedKey == color.hex ? .green : DesignTokens.Colors.textTertiary)
                    }
                }.buttonStyle(.plain)

                Text(color.rgbString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .padding(DesignTokens.Spacing.sm)
        }
        .background(DesignTokens.Colors.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
    }

    /// 亮度排序区域
    private var luminanceSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("亮度排序")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .padding(.horizontal, DesignTokens.Spacing.lg)

            VStack(spacing: DesignTokens.Spacing.xs) {
                ForEach(ColorCompareLogic.sortedByLuminance(colors)) { color in
                    HStack(spacing: DesignTokens.Spacing.md) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.color)
                            .frame(width: 16, height: 16)
                        Text(color.hex)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(DesignTokens.Colors.textPrimary)

                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color.color)
                                .frame(width: geo.size.width * color.luminance)
                        }.frame(height: 8)

                        Text(String(format: "%.1f%%", color.luminance * 100))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .frame(width: 50, alignment: .trailing)
                    }
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                }
            }
            .padding(.bottom, DesignTokens.Spacing.md)
        }
    }

    private func parseColors() {
        colors = ColorCompareLogic.parse(input)
    }

    private func copyAll() {
        EventBus.shared.post(CopyToClipboardEvent(text: ColorCompareLogic.copyText(colors)))
    }
}
