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

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            header
            detail
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .fill(DesignTokens.Colors.cardFill)
        )
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.top, DesignTokens.Spacing.md)
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
                        .fill(DesignTokens.Colors.progress.opacity(0.12))
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

            Text(preview.title)
                .font(DesignTokens.Typography.compactKeyCap)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xxs)
                .background(Capsule().fill(DesignTokens.Colors.progress.opacity(0.12)))
                .foregroundStyle(DesignTokens.Colors.progress)
        }
    }

    /// 主标题：直接给「答案」
    private var primaryText: String {
        switch preview {
        case .url(_, let domain): return domain
        case .filePath(let path, _, _): return (path as NSString).lastPathComponent
        case .color(let hex, _): return hex
        case .timestamp(_, let formatted, _): return formatted
        case .math(_, let result): return result
        case .email(let email): return email
        case .ip(let address): return address
        case .phone(let formatted): return formatted
        case .base64: return "Base64"
        case .urlEncoded: return "URL 编码"
        case .json(let summary, let lines): return "\(summary) · \(lines) 行"
        case .sql(let statement, let lines): return "\(statement) · \(lines) 行"
        case .translation: return "文本"
        case .plainText: return "文本"
        }
    }

    /// 副标题：补充说明
    private var secondaryText: String? {
        switch preview {
        case .url(let url, _): return url
        case .filePath(let path, _, _): return path
        case .color(_, let rgb): return rgb
        case .timestamp(let original, _, let relative): return "\(relative) · \(original)"
        case .math(let expr, _): return expr
        case .base64, .urlEncoded, .json, .sql, .email, .ip, .phone, .translation, .plainText:
            return nil
        }
    }

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
        case .timestamp, .url, .math, .email, .ip, .phone, .translation, .plainText:
            if let snippet = snippet {
                Text(snippet)
                    .font(DesignTokens.Typography.rowTrailing)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .lineLimit(2)
            }
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

    private func colorDetail(hex: String, rgb: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                .fill(Self.color(from: hex) ?? .clear)
                .frame(
                    width: DesignTokens.Size.rowIcon + DesignTokens.Spacing.xl,
                    height: DesignTokens.Size.rowIcon + DesignTokens.Spacing.xl
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.barControl, style: .continuous)
                        .strokeBorder(DesignTokens.Colors.cardStroke, lineWidth: 0.5)
                )
            Text(rgb)
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
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
                .lineLimit(5)
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
                .lineLimit(8)
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
