// AppIdentity.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 当前构建的渠道身份（Debug = 独立开发频道）。
///
/// Debug 使用 `com.ixxxxoooo.quick.dev` 与展示名「Quick Dev」，正式版使用
/// `com.ixxxxoooo.quick` / 「Quick」。独立 bundle id = 独立 TCC 授权、偏好与日志子系统。
public enum AppIdentity {

    /// 系统设置与菜单里显示的名字（Debug 为「Quick Dev」）
    public static var displayName: String {
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
            !name.isEmpty
        {
            return name
        }
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
            !name.isEmpty
        {
            return name
        }
        return "Quick"
    }

    /// 是否为开发渠道（bundle id 以 `.dev` 结尾）
    public static var isDevChannel: Bool {
        Bundle.main.bundleIdentifier?.hasSuffix(".dev") ?? false
    }

    /// bundle id，便于排查 TCC 授权对象
    public static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.ixxxxoooo.quick"
    }
}
