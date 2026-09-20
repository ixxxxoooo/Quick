// ColorCompareTool.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 颜色对比工具
///
/// 参考 Fasty color-compare 布局：
/// 输入区 → 颜色卡片网格（HEX/RGB/HSL）→ 亮度排序和对比度矩阵
struct ColorCompareTool: DevTool {
    let id = "color"
    let name = "颜色工具"
    let icon = "paintpalette"
    let keywords = ["颜色", "color", "hex", "rgb", "色值", "取色"]
    let description = "HEX/RGB 颜色识别、转换和亮度对比"

    func makeView() -> AnyView {
        AnyView(ColorCompareView())
    }
}

/// 解析的颜色条目
private struct ParsedColor: Identifiable {
    let id = UUID()
    let hex: String
    let r: Double
    let g: Double
    let b: Double

    var color: Color { Color(red: r / 255, green: g / 255, blue: b / 255) }
    var rgbString: String { "rgb(\(Int(r)), \(Int(g)), \(Int(b)))" }
    /// 相对亮度（WCAG）
    var luminance: Double {
        func sRGB(_ v: Double) -> Double {
            let s = v / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * sRGB(r) + 0.7152 * sRGB(g) + 0.0722 * sRGB(b)
    }
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
                ForEach(colors.sorted(by: { $0.luminance > $1.luminance })) { color in
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
        let text = input
        var parsed: [ParsedColor] = []

        // 匹配 #HEX
        let hexPattern = "#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{3})"
        if let regex = try? NSRegularExpression(pattern: hexPattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let range = Range(match.range, in: text) {
                    let hex = String(text[range])
                    if let color = parseHex(hex) { parsed.append(color) }
                }
            }
        }

        // 匹配 rgb(r, g, b)
        let rgbPattern = "rgb\\s*\\(\\s*(\\d+)\\s*,\\s*(\\d+)\\s*,\\s*(\\d+)\\s*\\)"
        if let regex = try? NSRegularExpression(pattern: rgbPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let rRange = Range(match.range(at: 1), in: text),
                    let gRange = Range(match.range(at: 2), in: text),
                    let bRange = Range(match.range(at: 3), in: text),
                    let r = Double(text[rRange]),
                    let g = Double(text[gRange]),
                    let b = Double(text[bRange])
                {
                    let hex = String(format: "#%02X%02X%02X", Int(r), Int(g), Int(b))
                    parsed.append(ParsedColor(hex: hex, r: r, g: g, b: b))
                }
            }
        }

        colors = parsed
    }

    private func parseHex(_ hex: String) -> ParsedColor? {
        var clean = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        if clean.count == 3 {
            clean = clean.map { "\($0)\($0)" }.joined()
        }
        guard clean.count == 6, let value = UInt64(clean, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF)
        let g = Double((value >> 8) & 0xFF)
        let b = Double(value & 0xFF)
        return ParsedColor(hex: "#\(clean.uppercased())", r: r, g: g, b: b)
    }

    private func copyAll() {
        let text = colors.map { "\($0.hex) | \($0.rgbString)" }.joined(separator: "\n")
        EventBus.shared.post(CopyToClipboardEvent(text: text))
    }
}
