// TimestampConverterTool.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 时间戳转换器
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
    @State private var timestampInput = ""
    @State private var dateOutput = ""
    @State private var currentTimestamp = ""

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = .current
        return f
    }()

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            HStack {
                Text("时间戳转换")
                    .font(DesignTokens.Typography.panelTitle)
                Spacer()
            }

            // 当前时间戳
            HStack {
                Text("当前时间戳:")
                    .font(DesignTokens.Typography.sectionHeader)
                Text(currentTimestamp)
                    .font(DesignTokens.Typography.code)
                    .textSelection(.enabled)
                Button {
                    EventBus.shared.post(CopyToClipboardEvent(text: currentTimestamp))
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .onAppear { updateCurrent() }

            Divider().opacity(0.3)

            // 时间戳 → 日期
            HStack(spacing: DesignTokens.Spacing.md) {
                TextField("输入时间戳…", text: $timestampInput)
                    .textFieldStyle(.plain)
                    .font(DesignTokens.Typography.code)
                    .padding(DesignTokens.Spacing.md)
                    .background(DesignTokens.Colors.cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))

                Image(systemName: "arrow.right")
                    .foregroundStyle(DesignTokens.Colors.textTertiary)

                Text(dateOutput.isEmpty ? "日期结果" : dateOutput)
                    .font(DesignTokens.Typography.code)
                    .foregroundStyle(
                        dateOutput.isEmpty
                            ? DesignTokens.Colors.textTertiary : DesignTokens.Colors.textPrimary
                    )
                    .textSelection(.enabled)
                    .padding(DesignTokens.Spacing.md)
                    .background(DesignTokens.Colors.cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
                    .frame(minWidth: 200)
            }
            .onChange(of: timestampInput) { _, newValue in
                convert(newValue)
            }

            Spacer()
        }
        .padding(DesignTokens.Spacing.xl)
    }

    private func updateCurrent() {
        currentTimestamp = "\(Int(Date().timeIntervalSince1970))"
    }

    private func convert(_ input: String) {
        guard let ts = Double(input) else {
            dateOutput = ""
            return
        }
        // 自动检测秒/毫秒
        let interval: TimeInterval = ts > 1e12 ? ts / 1000 : ts
        let date = Date(timeIntervalSince1970: interval)
        dateOutput = formatter.string(from: date)
    }
}
