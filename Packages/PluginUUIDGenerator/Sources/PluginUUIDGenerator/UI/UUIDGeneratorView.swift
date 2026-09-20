// UUIDGeneratorView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct UUIDGeneratorView: View {
    @State private var uuids: [String] = []
    @State private var count = 5
    /// 大小写与连字符持久化：设置页里的开关改的就是它们
    @AppStorage("uuidGenerator.uppercase") private var uppercase = true
    @AppStorage("uuidGenerator.removeDashes") private var removeDashes = false
    @State private var copiedIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack(spacing: DesignTokens.Spacing.md) {
                Stepper("数量: \(count)", value: $count, in: 1...100)
                    .frame(width: 130)

                Toggle("大写", isOn: $uppercase)
                Toggle("去连字符", isOn: $removeDashes)

                Spacer()

                Button {
                    generate()
                } label: {
                    Label("生成", systemImage: "arrow.clockwise")
                }.buttonStyle(.borderedProminent).controlSize(.small)

                Button {
                    copyAll()
                } label: {
                    Label("全部复制", systemImage: "doc.on.doc")
                }.buttonStyle(.bordered).controlSize(.small)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)

            Divider().opacity(0.3)

            // 结果列表
            ScrollView {
                LazyVStack(spacing: DesignTokens.Spacing.xs) {
                    ForEach(Array(uuids.enumerated()), id: \.offset) { index, uuid in
                        HStack(spacing: DesignTokens.Spacing.md) {
                            Text("\(index + 1)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                                .frame(width: 20, alignment: .trailing)

                            Text(uuid)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                                .textSelection(.enabled)

                            Spacer()

                            Button {
                                EventBus.shared.post(CopyToClipboardEvent(text: uuid))
                                copiedIndex = index
                                Task { @MainActor in
                                    try? await Task.sleep(for: .seconds(1.5))
                                    if copiedIndex == index { copiedIndex = nil }
                                }
                            } label: {
                                Image(systemName: copiedIndex == index ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundStyle(
                                        copiedIndex == index ? .green : DesignTokens.Colors.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        .padding(.vertical, DesignTokens.Spacing.sm)
                        .background(DesignTokens.Colors.cardFill)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.row))
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.vertical, DesignTokens.Spacing.sm)
            }

            Divider().opacity(0.3)

            // 状态栏
            HStack {
                Text("已生成 \(uuids.count) 个 UUID")
                    .font(.caption).foregroundStyle(DesignTokens.Colors.textTertiary)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.xs)
        }
        .onAppear { generate() }
        .onChange(of: uppercase) { _, _ in generate() }
        .onChange(of: removeDashes) { _, _ in generate() }
    }

    private func generate() {
        uuids = UUIDGeneratorLogic.generate(
            count: count,
            uppercase: uppercase,
            removeDashes: removeDashes
        )
    }

    private func copyAll() {
        let text = uuids.joined(separator: "\n")
        EventBus.shared.post(CopyToClipboardEvent(text: text))
    }
}
