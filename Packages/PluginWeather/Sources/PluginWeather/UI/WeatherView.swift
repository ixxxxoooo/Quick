// WeatherView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickUI
import SwiftUI

/// 天气插件视图
struct WeatherView: View {

    let service: WeatherService

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xxl) {
            if service.isLoading {
                ProgressView("正在获取天气…")
            } else if let info = service.currentInfo {
                Image(systemName: info.icon)
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)

                Text(info.summary)
                    .font(DesignTokens.Typography.panelTitle)

                Text(info.detail)
                    .font(DesignTokens.Typography.rowTrailing)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            } else {
                Image(systemName: "cloud.sun")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)

                Text("搜索 \"天气\" 查看当前天气")
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
