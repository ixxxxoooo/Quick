// OCRResultView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// OCR 结果视图
struct OCRResultView: View {

    let engine: OCREngine

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xxl) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            Text("文字识别 (OCR)")
                .font(DesignTokens.Typography.panelTitle)

            if engine.isProcessing {
                ProgressView("正在识别…")
            } else if !engine.lastResult.isEmpty {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    HStack {
                        Text("识别结果")
                            .font(DesignTokens.Typography.sectionHeader)
                        Spacer()
                        Button {
                            EventBus.shared.post(CopyToClipboardEvent(text: engine.lastResult))
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                    }

                    ScrollView {
                        Text(engine.lastResult)
                            .font(DesignTokens.Typography.code)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(DesignTokens.Spacing.md)
                    .background(DesignTokens.Colors.cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
                }
            } else {
                Text("在搜索框中输入 \"ocr\" 或 \"文字识别\" 开始截图识别")
                    .font(DesignTokens.Typography.rowTrailing)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        }
        .padding(DesignTokens.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
