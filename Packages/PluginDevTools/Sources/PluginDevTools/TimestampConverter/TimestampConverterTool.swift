// TimestampConverterTool.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 时间戳转换器
///
/// 参考 Fasty timestamp-converter 布局：
/// 输入区 + 自动检测 → 结果卡片列表 → 底部当前时间
struct TimestampConverterTool: DevTool {
    let id = "timestamp"
    let name = "时间戳转换"
    let icon = "clock"
    let keywords = ["时间戳", "timestamp", "unix", "时间转换", "日期"]
    let description = "Unix 时间戳与日期互转"

    func makeView() -> AnyView {
        AnyView(TimestampConverterView())
    }
}

struct TimestampConverterView: View {
    @State private var input = ""
    @State private var results: [(key: String, label: String, value: String)] = []
    @State private var inputType: String = "empty"
    @State private var now = Date()
    @State private var copiedKey: String?

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = .current
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // 输入区
            HStack(spacing: DesignTokens.Spacing.md) {
                TextField("输入时间戳或日期…", text: $input)
                    .textFieldStyle(.plain)
                    .font(DesignTokens.Typography.code)
                    .padding(DesignTokens.Spacing.md)
                    .background(DesignTokens.Colors.cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))

                if inputType != "empty" {
                    Text(inputType == "timestamp" ? "时间戳" : "日期")
                        .font(.caption)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.md)

            Divider().opacity(0.3).padding(.horizontal, DesignTokens.Spacing.lg)

            // 结果卡片
            if !results.isEmpty {
                ScrollView {
                    VStack(spacing: DesignTokens.Spacing.xs) {
                        ForEach(results, id: \.key) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.label)
                                        .font(.caption)
                                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                                    Text(item.value)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                                        .textSelection(.enabled)
                                }
                                Spacer()
                                Button {
                                    EventBus.shared.post(CopyToClipboardEvent(text: item.value))
                                    copiedKey = item.key
                                    Task { @MainActor in
                                        try? await Task.sleep(for: .seconds(1.5))
                                        if copiedKey == item.key { copiedKey = nil }
                                    }
                                } label: {
                                    Image(
                                        systemName: copiedKey == item.key ? "checkmark" : "doc.on.doc"
                                    )
                                    .font(.system(size: 12))
                                    .foregroundStyle(
                                        copiedKey == item.key ? .green : DesignTokens.Colors.textTertiary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(DesignTokens.Spacing.md)
                            .background(DesignTokens.Colors.cardFill)
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                }
            } else if !input.isEmpty {
                Text("无法识别的时间格式")
                    .font(.caption).foregroundStyle(DesignTokens.Colors.destructive)
                    .padding(DesignTokens.Spacing.lg)
            } else {
                VStack(spacing: DesignTokens.Spacing.md) {
                    Text("输入时间戳或日期后自动转换")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer(minLength: 0)

            Divider().opacity(0.3)

            // 底部当前时间
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text("当前时间")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text(dateFormatter.string(from: now))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Spacer()
                Button {
                    input = "\(Int(Date().timeIntervalSince1970))"
                } label: {
                    Label("填入当前", systemImage: "arrow.down.to.line")
                }.buttonStyle(.bordered).controlSize(.mini)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)
        }
        .onChange(of: input) { _, newVal in convert(newVal) }
        .onReceive(timer) { now = $0 }
    }

    private func convert(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []; inputType = "empty"; return
        }

        // 尝试解析为时间戳
        if let ts = Double(trimmed) {
            inputType = "timestamp"
            let interval: TimeInterval = ts > 1e12 ? ts / 1000 : ts
            let date = Date(timeIntervalSince1970: interval)
            let iso = ISO8601DateFormatter().string(from: date)
            results = [
                (key: "local", label: "本地时间", value: dateFormatter.string(from: date)),
                (key: "iso", label: "ISO 8601", value: iso),
                (key: "unix", label: "Unix 时间戳（秒）", value: "\(Int(date.timeIntervalSince1970))"),
                (key: "unixms", label: "Unix 时间戳（毫秒）", value: "\(Int(date.timeIntervalSince1970 * 1000))")
            ]
            return
        }

        // 尝试解析为日期
        let formats = [
            "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "yyyy/MM/dd HH:mm:ss",
            "yyyy/MM/dd", "MM/dd/yyyy"
        ]
        for fmt in formats {
            let df = DateFormatter()
            df.dateFormat = fmt
            if let date = df.date(from: trimmed) {
                inputType = "date"
                results = [
                    (key: "unix", label: "Unix 时间戳（秒）", value: "\(Int(date.timeIntervalSince1970))"),
                    (
                        key: "unixms", label: "Unix 时间戳（毫秒）",
                        value: "\(Int(date.timeIntervalSince1970 * 1000))"
                    ),
                    (key: "local", label: "本地时间", value: dateFormatter.string(from: date)),
                    (key: "iso", label: "ISO 8601", value: ISO8601DateFormatter().string(from: date))
                ]
                return
            }
        }

        inputType = "empty"
        results = []
    }
}
