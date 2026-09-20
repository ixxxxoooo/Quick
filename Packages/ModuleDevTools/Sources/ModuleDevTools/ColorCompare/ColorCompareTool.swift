// ColorCompareTool.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 颜色对比工具
struct ColorCompareTool: DevTool {
    let id = "color"
    let name = "颜色工具"
    let icon = "paintpalette"
    let keywords = ["颜色", "color", "hex", "rgb", "色值", "取色"]
    let description = "HEX/RGB 颜色转换和对比"

    func makeView() -> AnyView {
        AnyView(ColorCompareView())
    }
}

struct ColorCompareView: View {
    @State private var hexInput = "#007AFF"
    @State private var parsedColor: Color = .blue
    @State private var r: Double = 0
    @State private var g: Double = 122
    @State private var b: Double = 255

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            Text("颜色工具")
                .font(DesignTokens.Typography.panelTitle)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: DesignTokens.Spacing.xxl) {
                // 颜色预览
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                    .fill(parsedColor)
                    .frame(width: 100, height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                            .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
                    )

                // HEX 输入
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    HStack {
                        Text("HEX:")
                            .font(DesignTokens.Typography.sectionHeader)
                        TextField("#RRGGBB", text: $hexInput)
                            .textFieldStyle(.plain)
                            .font(DesignTokens.Typography.code)
                            .onChange(of: hexInput) { _, newValue in
                                parseHex(newValue)
                            }
                        Button {
                            EventBus.shared.post(CopyToClipboardEvent(text: hexInput))
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                    }

                    HStack {
                        Text("RGB:")
                            .font(DesignTokens.Typography.sectionHeader)
                        Text("rgb(\(Int(r)), \(Int(g)), \(Int(b)))")
                            .font(DesignTokens.Typography.code)
                            .textSelection(.enabled)
                    }
                }
            }

            // RGB 滑块
            VStack(spacing: DesignTokens.Spacing.md) {
                colorSlider("R", value: $r, color: .red)
                colorSlider("G", value: $g, color: .green)
                colorSlider("B", value: $b, color: .blue)
            }
            .onChange(of: r) { _, _ in updateFromRGB() }
            .onChange(of: g) { _, _ in updateFromRGB() }
            .onChange(of: b) { _, _ in updateFromRGB() }

            Spacer()
        }
        .padding(DesignTokens.Spacing.xl)
        .onAppear { parseHex(hexInput) }
    }

    private func colorSlider(_ label: String, value: Binding<Double>, color: Color) -> some View {
        HStack {
            Text(label).font(DesignTokens.Typography.code).frame(width: 20)
            Slider(value: value, in: 0...255)
                .tint(color)
            Text("\(Int(value.wrappedValue))")
                .font(DesignTokens.Typography.code)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func parseHex(_ hex: String) {
        let clean = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        guard clean.count == 6, let value = UInt64(clean, radix: 16) else { return }
        r = Double((value >> 16) & 0xFF)
        g = Double((value >> 8) & 0xFF)
        b = Double(value & 0xFF)
        parsedColor = Color(red: r / 255, green: g / 255, blue: b / 255)
    }

    private func updateFromRGB() {
        parsedColor = Color(red: r / 255, green: g / 255, blue: b / 255)
        hexInput = String(format: "#%02X%02X%02X", Int(r), Int(g), Int(b))
    }
}
