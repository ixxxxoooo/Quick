// PermissionsPane.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import SwiftUI

/// 权限
///
/// 每一行都要说清「这个权限用来干什么」—— 权限页最忌讳只要求授权不说用途，
/// 用户唯一能做的判断就是看那行灰字。
struct PermissionsPane: View {

    let dataSource: any HostSettingsDataSource

    /// 状态是每次进入这一页时现查的：权限可能在系统设置里被改过，
    /// 而应用收不到通知。缓存会让这一页显示过期状态。
    @State private var states: [SettingsPermission: SettingsPermissionState] = [:]

    var body: some View {
        Form {
            Section {
                ForEach(SettingsPermission.allCases, id: \.self) { permission in
                    row(for: permission)
                }
            } header: {
                Text("系统权限")
            } footer: {
                Text("macOS 只允许已授权的应用访问这些能力。授权后需要重启 Quick 才会生效。")
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
    }

    @ViewBuilder
    private func row(for permission: SettingsPermission) -> some View {
        let state = states[permission]

        SettingsRow(
            title: permission.title,
            subtitle: permission.purpose,
            icon: {
                SettingsRowIcon(
                    systemImage: permission.systemImage,
                    isEnabled: state?.isGranted ?? false
                )
            }
        ) {
            trailing(for: permission, state: state)
        }
    }

    @ViewBuilder
    private func trailing(for permission: SettingsPermission, state: SettingsPermissionState?) -> some View {
        switch state {
        case .none:
            ProgressView().controlSize(.small)

        case .some(let state) where state.isGranted:
            Label("已授权", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .font(DesignTokens.Typography.rowTrailing)
                .foregroundStyle(DesignTokens.Colors.success)

        default:
            HStack(spacing: DesignTokens.Spacing.sm) {
                Button("重新检测") { refresh() }
                if let target = dragTarget(for: permission) {
                    Button("拖拽授权") {
                        PermissionDragController.shared.present(target)
                    }
                } else if state?.canRequest == true {
                    Button("申请") {
                        dataSource.requestPermission(permission)
                        Task {
                            try? await Task.sleep(for: .seconds(1))
                            refresh()
                        }
                    }
                } else {
                    Button("打开系统设置") {
                        dataSource.openPermissionSettings(permission)
                    }
                }
            }
        }
    }

    /// 辅助功能和屏幕录制走拖拽授权。定位仍由系统对话框申请
    private func dragTarget(for permission: SettingsPermission) -> PermissionDragTarget? {
        switch permission {
        case .accessibility: .accessibility
        case .screenCapture: .screenCapture
        case .location: nil
        }
    }

    private func refresh() {
        states = Dictionary(
            uniqueKeysWithValues: SettingsPermission.allCases.map {
                ($0, dataSource.permissionState($0))
            }
        )
    }
}
