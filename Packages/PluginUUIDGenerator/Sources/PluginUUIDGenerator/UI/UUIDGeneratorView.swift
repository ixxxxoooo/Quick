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
    @AppStorage(PluginSettingKey.UUIDGenerator.uppercase) private var uppercase = true
    @AppStorage(PluginSettingKey.UUIDGenerator.removeDashes) private var removeDashes = false
    @State private var version: UUIDGeneratorLogic.Version = .v4
    @State private var copiedIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack(spacing: DesignTokens.Spacing.md) {
                Stepper("数量: \(count)", value: $count, in: 1...100)
                    .frame(width: DesignTokens.Size.uuidOptionWidth)

                Picker("版本", selection: $version) {
                    ForEach(UUIDGeneratorLogic.Version.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: DesignTokens.Size.uuidVersionPickerWidth)
                .accessibilityLabel("UUID 版本")

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

            Divider().opacity(DesignTokens.Opacity.divider)

            // 结果列表
            ScrollView {
                LazyVStack(spacing: DesignTokens.Spacing.xs) {
                    ForEach(Array(uuids.enumerated()), id: \.offset) { index, uuid in
                        HStack(spacing: DesignTokens.Spacing.md) {
                            Text("\(index + 1)")
                                .font(DesignTokens.Typography.compactKeyCap)
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                                .frame(width: DesignTokens.Size.indexColumnWidth, alignment: .trailing)

                            Text(uuid)
                                .font(DesignTokens.Typography.code)
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
                                    .font(DesignTokens.Typography.inlineIcon)
                                    .foregroundStyle(
                                        copiedIndex == index
                                            ? DesignTokens.Colors.success
                                            : DesignTokens.Colors.textTertiary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(copiedIndex == index ? "已复制" : "复制 UUID")
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

            Divider().opacity(DesignTokens.Opacity.divider)

            // 状态栏
            HStack {
                Text("已生成 \(uuids.count) 个 UUID \(version.rawValue)")
                    .font(DesignTokens.Typography.keyCap).foregroundStyle(DesignTokens.Colors.textTertiary)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.xs)
        }
        .onAppear { generate() }
        .onChange(of: uppercase) { _, _ in generate() }
        .onChange(of: removeDashes) { _, _ in generate() }
        .onChange(of: version) { _, _ in generate() }
    }

    private func generate() {
        uuids = UUIDGeneratorLogic.generate(
            count: count,
            uppercase: uppercase,
            removeDashes: removeDashes,
            version: version
        )
    }

    private func copyAll() {
        let text = uuids.joined(separator: "\n")
        EventBus.shared.post(CopyToClipboardEvent(text: text))
    }
}
