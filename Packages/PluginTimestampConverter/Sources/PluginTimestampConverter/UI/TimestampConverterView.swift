// TimestampConverterView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct TimestampConverterView: View {
    /// 输入文本归插件所有：主面板与分离窗口共享同一份，分离时内容自然带过去
    @Bindable var buffer: TextBuffer

    private var input: String {
        get { buffer.text }
        nonmutating set { buffer.text = newValue }
    }
    @State private var results: [TimestampConverterLogic.Row] = []
    @State private var inputType: TimestampConverterLogic.InputType = .empty
    @State private var now = Date()
    @State private var copiedKey: String?

    @AppStorage(PluginSettingKey.TimestampConverter.defaultUnit)
    private var unitSetting = TimestampConverterDefaults.unit.rawValue
    @AppStorage(PluginSettingKey.TimestampConverter.timeZone)
    private var zoneSetting = TimestampConverterDefaults.zone.rawValue

    private var zonePreference: TimestampZonePreference { TimestampZonePreference(setting: zoneSetting) }

    /// 底部「当前时间」的格式器：时区跟随设置（每次现建，设置变了立刻生效；一秒才一次，开销可忽略）
    private var clockText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = zonePreference.timeZone(local: .current)
        let text = formatter.string(from: now)
        return zonePreference == .utc ? "\(text) UTC" : text
    }

    var body: some View {
        VStack(spacing: 0) {
            // 输入区
            HStack(spacing: DesignTokens.Spacing.md) {
                TextField("输入时间戳或日期…", text: $buffer.text)
                    .textFieldStyle(.plain)
                    .font(DesignTokens.Typography.code)
                    .padding(DesignTokens.Spacing.md)
                    .background(DesignTokens.Colors.cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))

                if inputType != .empty {
                    Text(inputType == .timestamp ? "时间戳" : "日期")
                        .font(DesignTokens.Typography.keyCap)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(Color.accentColor.opacity(DesignTokens.Opacity.tint))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.keyCap))
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.md)

            Divider().opacity(DesignTokens.Opacity.divider).padding(.horizontal, DesignTokens.Spacing.lg)

            // 结果卡片
            if !results.isEmpty {
                ScrollView {
                    VStack(spacing: DesignTokens.Spacing.xs) {
                        ForEach(results, id: \.key) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                                    Text(item.label)
                                        .font(DesignTokens.Typography.keyCap)
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
                                    .font(DesignTokens.Typography.inlineIcon)
                                    .foregroundStyle(
                                        copiedKey == item.key
                                            ? DesignTokens.Colors.success : DesignTokens.Colors.textTertiary)
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
                    .font(DesignTokens.Typography.keyCap).foregroundStyle(DesignTokens.Colors.destructive)
                    .padding(DesignTokens.Spacing.lg)
            } else {
                VStack(spacing: DesignTokens.Spacing.md) {
                    Text("输入时间戳或日期后自动转换")
                        .font(DesignTokens.Typography.keyCap)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer(minLength: 0)

            Divider().opacity(DesignTokens.Opacity.divider)

            // 底部当前时间
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "clock")
                    .font(DesignTokens.Typography.compactIcon)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text("当前时间")
                    .font(DesignTokens.Typography.keyCap)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text(clockText)
                    .font(DesignTokens.Typography.code)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Spacer()
                Button {
                    input = TimestampConverterLogic.currentTimestamp(
                        now: Date(), unit: TimestampUnit(setting: unitSetting))
                } label: {
                    Label("填入当前", systemImage: "arrow.down.to.line")
                }.buttonStyle(.bordered).controlSize(.mini)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)
        }
        .onAppear {
            // 打开时输入为空就预填当前时间戳（单位跟随设置），打开即可看到转换结果
            if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                input = TimestampConverterLogic.currentTimestamp(
                    now: Date(), unit: TimestampUnit(setting: unitSetting))
            }
            convert(input)
        }
        .onChange(of: input) { _, newVal in convert(newVal) }
        .onChange(of: zoneSetting) { _, _ in convert(input) }
        .task {
            // 底部「当前时间」每秒走一格。用 `Task` 而不是 `Timer.publish`：视图消失时
            // 自动取消，不必再挂一个 onDisappear 去炸掉订阅
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: Self.clockInterval)
            }
        }
    }

    /// 「当前时间」的走针间隔
    private static let clockInterval = Duration.seconds(1)

    /// 转换逻辑整体在模型层，视图只把结果搬进 `@State`
    private func convert(_ text: String) {
        let preference = zonePreference
        let conversion = TimestampConverterLogic.convert(
            text, timeZone: preference.timeZone(local: .current), now: Date(),
            zoneLabel: preference.rowLabel)
        results = conversion.rows
        inputType = conversion.inputType
    }
}
