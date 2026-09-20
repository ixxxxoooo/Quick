// URLCodecTool.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// URL 编解码工具
struct URLCodecTool: DevTool {
    let id = "url"
    let name = "URL 编解码"
    let icon = "link"
    let keywords = ["url", "编码", "解码", "urlencode", "urldecode", "链接"]
    let description = "URL 百分号编码和解码"

    func makeView() -> AnyView {
        AnyView(URLCodecView())
    }
}

struct URLCodecView: View {
    @State private var input = ""
    @State private var output = ""

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            HStack {
                Text("URL 编解码")
                    .font(DesignTokens.Typography.panelTitle)
                Spacer()
                Button("编码") {
                    output = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
                }.buttonStyle(.borderedProminent)
                Button("解码") {
                    output = input.removingPercentEncoding ?? input
                }.buttonStyle(.bordered)
                Button("复制") {
                    EventBus.shared.post(CopyToClipboardEvent(text: output))
                }.buttonStyle(.bordered)
            }

            HSplitView {
                TextEditor(text: $input).font(DesignTokens.Typography.code).scrollContentBackground(.hidden).frame(minWidth: 200)
                TextEditor(text: .constant(output)).font(DesignTokens.Typography.code).scrollContentBackground(.hidden).frame(minWidth: 200)
            }
        }
        .padding(DesignTokens.Spacing.xl)
    }
}
