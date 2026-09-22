// NetworkToolsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 网络工具视图
struct NetworkToolsView: View {

    let service: NetworkService

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            HStack {
                Text("网络工具")
                    .font(DesignTokens.Typography.panelTitle)
                Spacer()
                Button("刷新") {
                    Task { await service.refresh() }
                }
                .buttonStyle(.bordered)
            }

            if service.isLoading {
                ProgressView("正在查询…")
                    .frame(maxHeight: .infinity)
            } else if let info = service.networkInfo {
                VStack(spacing: DesignTokens.Spacing.md) {
                    infoRow("本机 IP", value: info.localIP)
                    // 公网 IP 那一行跟着设置走：关掉时连请求都没发出去，
                    // 自然也没有什么可显示的 —— 留着「无法获取」只会误导用户以为查询失败
                    if service.showsExternalIP {
                        infoRow("公网 IP", value: info.publicIP ?? "无法获取")
                    }
                    infoRow("DNS 服务器", value: info.dns.joined(separator: ", "))
                }

                Spacer()
            } else {
                VStack(spacing: DesignTokens.Spacing.md) {
                    Image(systemName: "network")
                        .font(DesignTokens.Typography.emptyStateIcon)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    Text("点击刷新按钮获取网络信息")
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(DesignTokens.Spacing.xxl)
        .task { await service.refresh() }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(DesignTokens.Typography.code)
                .textSelection(.enabled)
            Button {
                EventBus.shared.post(CopyToClipboardEvent(text: value))
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.row))
    }
}
