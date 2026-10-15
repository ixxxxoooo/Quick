// NetworkToolsView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

/// 网络工具视图
struct NetworkToolsView: View {

    let service: NetworkService

    @State private var pingHost = "apple.com"
    @State private var showsRawPing = false

    var body: some View {
        ScrollView {
            content
        }
        .task { await service.refresh() }
        .onDisappear { service.cancelPing() }
    }

    private var content: some View {
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
            } else {
                VStack(spacing: DesignTokens.Spacing.md) {
                    Image(systemName: "network")
                        .font(DesignTokens.Typography.emptyStateIcon)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    Text("点击刷新按钮获取网络信息")
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.emptyStateMinHeight)
            }

            pingCard
        }
        .padding(DesignTokens.Spacing.xxl)
    }

    // MARK: - Ping

    private var isPinging: Bool {
        if case .running = service.pingState { return true }
        return false
    }

    private var pingCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.md) {
                Text("Ping")
                    .font(DesignTokens.Typography.sectionHeader)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                TextField("主机名或 IP", text: $pingHost)
                    .textFieldStyle(.roundedBorder)
                    .font(DesignTokens.Typography.code)
                    .onSubmit { service.startPing(host: pingHost) }
                if isPinging {
                    Button("停止") { service.cancelPing() }
                        .buttonStyle(.bordered)
                } else {
                    Button("开始") { service.startPing(host: pingHost) }
                        .buttonStyle(.borderedProminent)
                        .disabled(PingTarget.validated(pingHost) == nil)
                }
            }

            switch service.pingState {
            case .idle:
                EmptyView()
            case .running(let host):
                HStack(spacing: DesignTokens.Spacing.sm) {
                    ProgressView().controlSize(.small)
                    Text("正在 ping \(host)…")
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            case .finished(_, let summary, let raw):
                Label(
                    summary.headline,
                    systemImage: summary.received == 0 ? "xmark.circle.fill" : "checkmark.circle.fill"
                )
                .foregroundStyle(summary.received == 0 ? DesignTokens.Colors.destructive : DesignTokens.Colors.success)
                DisclosureGroup("详细输出", isExpanded: $showsRawPing) {
                    Text(raw)
                        .font(DesignTokens.Typography.code)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .failed(_, let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(DesignTokens.Colors.destructive)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.row))
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
            .accessibilityLabel("复制")
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.row))
    }
}
