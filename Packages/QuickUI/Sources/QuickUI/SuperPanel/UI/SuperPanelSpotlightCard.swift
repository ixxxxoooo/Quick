// SuperPanelSpotlightCard.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Foundation
import QuickCore
import SwiftUI

/// 识别结果预览卡
///
/// 不只是「这是网址」这类标签，而是**直接把答案摆出来**：文件给名字/大小/修改时间，
/// 颜色给色块，算式给结果，JSON 给格式化预览，时间戳给可读时间……
/// 需要更细的操作时，下方的动作列表里仍有「在某某工具中打开」。
struct SuperPanelSpotlightCard: View {

    let preview: SmartPreview
    let sourceText: String
    let onCopy: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            header
            detail
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .fill(DesignTokens.Colors.cardFill)
        )
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.top, DesignTokens.Spacing.xs)
        .padding(.bottom, DesignTokens.Spacing.xs)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: preview.icon)
                .font(DesignTokens.Typography.iconGlyph)
                .foregroundStyle(DesignTokens.Colors.progress)
                .frame(
                    width: DesignTokens.Size.rowIcon + DesignTokens.Spacing.lg,
                    height: DesignTokens.Size.rowIcon + DesignTokens.Spacing.lg
                )
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                        .fill(DesignTokens.Colors.progress.opacity(DesignTokens.Opacity.tint))
                )

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(primaryText)
                    .font(DesignTokens.Typography.panelTitle)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                if let secondary = secondaryText {
                    Text(secondary)
                        .font(DesignTokens.Typography.rowTrailing)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DesignTokens.Spacing.sm)

            HStack(spacing: DesignTokens.Spacing.xs) {
                Button {
                    onCopy(textToCopy)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(DesignTokens.Typography.compactIcon)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .frame(
                            width: DesignTokens.Size.windowControlButton,
                            height: DesignTokens.Size.windowControlButton
                        )
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.keyCap, style: .continuous)
                                .fill(DesignTokens.Colors.controlSurface)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("复制")
                .focusable(false)
                .help("复制")

                Text(preview.title)
                    .font(DesignTokens.Typography.compactKeyCap)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .background(Capsule().fill(DesignTokens.Colors.progress.opacity(DesignTokens.Opacity.tint)))
                    .foregroundStyle(DesignTokens.Colors.progress)
            }
        }
    }

    private var textToCopy: String { preview.copyText(sourceText: sourceText) }

    /// 主标题：直接给「答案」
    private var primaryText: String { preview.headline }

    /// 副标题：补充说明
    private var secondaryText: String? { preview.subheadline }

    // MARK: - 类型化详情

    @ViewBuilder
    private var detail: some View {
        switch preview {
        case .filePath(let path, let exists, let isDirectory):
            fileDetail(path: path, exists: exists, isDirectory: isDirectory)
        case .color(let hex, let rgb):
            colorDetail(hex: hex, rgb: rgb)
        case .base64(let decoded):
            decodedDetail(label: "解码结果", text: decoded)
        case .urlEncoded(let decoded):
            decodedDetail(label: "解码结果", text: decoded)
        case .json:
            jsonDetail
        case .sql:
            decodedDetail(label: "SQL 预览", text: sourceText)
        case .timestamp(
            let original,
            let formatted,
            let relative,
            let unixSeconds,
            let unixMilliseconds,
            let localTime,
            let isFromDateString
        ):
            timestampDetail(
                original: original,
                formatted: formatted,
                relative: relative,
                unixSeconds: unixSeconds,
                unixMilliseconds: unixMilliseconds,
                localTime: localTime,
                isFromDateString: isFromDateString
            )
        case .translation(let source, _, let translated, _, let senses):
            translationDetail(source: source, translated: translated, senses: senses)
        case .url, .math, .email, .ip, .phone, .plainText:
            if let snippet = snippet {
                Text(snippet)
                    .font(DesignTokens.Typography.rowTrailing)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .lineLimit(2)
            }
        }
    }

    private func timestampDetail(
        original: String,
        formatted: String,
        relative: String,
        unixSeconds: String?,
        unixMilliseconds: String?,
        localTime: String?,
        isFromDateString: Bool
    ) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            // 标题已经给出格式化时间、副标题已经给出相对时间与原文，
            // 这里只放「标题里没有」的信息：日期文本给本地时间，数字时间戳给秒值，
            // 再补一个毫秒值 —— 重复同一串数字三遍只会挤出换行。
            if isFromDateString, let local = localTime {
                infoChip(local)
            } else if let sec = unixSeconds, sec != original {
                infoChip("秒 \(sec)")
            }
            if let ms = unixMilliseconds, ms != original {
                infoChip("毫秒 \(ms)")
            }
        }
    }

    @ViewBuilder
    private func translationDetail(
        source: String,
        translated: String?,
        senses: [String]?
    ) -> some View {
        if let senses, !senses.isEmpty {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                ForEach(senses.prefix(2), id: \.self) { sense in
                    Text(sense)
                        .font(DesignTokens.Typography.rowTrailing)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
        } else if let translated, translated != source {
            Text(source)
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .lineLimit(2)
        } else if let snippet = snippet {
            Text(snippet)
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .lineLimit(2)
        }
    }

    private func fileDetail(path: String, exists: Bool, isDirectory: Bool) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            if exists {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    infoChip(isDirectory ? "文件夹" : "文件")
                    if !isDirectory, let size = Self.fileSize(path) {
                        infoChip(size)
                    }
                    if let modified = Self.fileModified(path) {
                        infoChip("修改于 \(modified)")
                    }
                }
            } else {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(DesignTokens.Typography.compactIcon)
                    Text("路径不存在")
                        .font(DesignTokens.Typography.rowTrailing)
                }
                .foregroundStyle(DesignTokens.Colors.warning)
            }
        }
    }

    /// 色块：RGB 已经在卡片副标题里，这里只放一条横向色带，不再把同一串数字写第二遍
    private func colorDetail(hex: String, rgb: String) -> some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
            .fill(Self.color(from: hex) ?? .clear)
            .frame(maxWidth: .infinity)
            .frame(height: DesignTokens.Size.rowIcon)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                    .strokeBorder(DesignTokens.Colors.cardStroke, lineWidth: DesignTokens.Size.hairlineThin)
            )
            .accessibilityLabel("颜色 \(rgb)")
    }

    private func decodedDetail(label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            Text(label)
                .font(DesignTokens.Typography.compactKeyCap)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text(text)
                .font(DesignTokens.Typography.code)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .textSelection(.enabled)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var jsonDetail: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            Text("格式化预览")
                .font(DesignTokens.Typography.compactKeyCap)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text(Self.prettyJSON(sourceText) ?? sourceText)
                .font(DesignTokens.Typography.code)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .textSelection(.enabled)
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func infoChip(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.Typography.compactKeyCap)
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.keyCap, style: .continuous)
                    .fill(DesignTokens.Colors.controlSurface)
            )
    }

    private var snippet: String? {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count > 60 ? String(trimmed.prefix(60)) + "…" : trimmed
    }

    // MARK: - 辅助

    private static func fileSize(_ path: String) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
            let bytes = attrs[.size] as? Int64
        else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func fileModified(_ path: String) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
            let date = attrs[.modificationDate] as? Date
        else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private static func prettyJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let string = String(data: pretty, encoding: .utf8)
        else { return nil }
        return string
    }

    private static func color(from hex: String) -> Color? {
        var value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if value.count == 3 { value = value.map { "\($0)\($0)" }.joined() }
        guard value.count >= 6, let number = UInt64(value.prefix(6), radix: 16) else { return nil }
        return Color(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }
}
