// UUIDGeneratorTool.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// UUID 生成器
struct UUIDGeneratorTool: DevTool {
    let id = "uuid"
    let name = "UUID 生成器"
    let icon = "number"
    let keywords = ["uuid", "guid", "生成", "随机", "唯一标识"]
    let description = "生成 UUID / GUID"

    func makeView() -> AnyView {
        AnyView(UUIDGeneratorView())
    }
}

struct UUIDGeneratorView: View {
    @State private var uuids: [String] = []
    @State private var count = 5
    @State private var uppercase = true

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            HStack {
                Text("UUID 生成器")
                    .font(DesignTokens.Typography.panelTitle)
                Spacer()
                Stepper("数量: \(count)", value: $count, in: 1...50)
                Toggle("大写", isOn: $uppercase)
                Button("生成") { generate() }.buttonStyle(.borderedProminent)
            }

            ScrollView {
                LazyVStack(spacing: DesignTokens.Spacing.xs) {
                    ForEach(uuids, id: \.self) { uuid in
                        HStack {
                            Text(uuid)
                                .font(DesignTokens.Typography.code)
                                .textSelection(.enabled)
                            Spacer()
                            Button {
                                EventBus.shared.post(CopyToClipboardEvent(text: uuid))
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        .padding(.vertical, DesignTokens.Spacing.sm)
                        .background(DesignTokens.Colors.cardFill)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.row))
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.xl)
        .onAppear { generate() }
    }

    private func generate() {
        uuids = (0..<count).map { _ in
            let uuid = UUID().uuidString
            return uppercase ? uuid : uuid.lowercased()
        }
    }
}
