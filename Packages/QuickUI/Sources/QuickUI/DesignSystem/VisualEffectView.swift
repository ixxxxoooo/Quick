// VisualEffectView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import SwiftUI

/// 原生 vibrancy 背景
///
/// 用 `NSVisualEffectView` 而不是 SwiftUI 的 `.ultraThinMaterial`：
/// 材质、混合模式与「强调」状态都需要显式指定才能和系统其他面板一致，
/// 而 SwiftUI 的材质修饰器不暴露这些。
///
/// 与 Tinycast 的 `VisualEffectView` 一致，默认 `.hudWindow` + `.behindWindow`：
/// 前者是系统给浮动面板用的材质，后者让它真正对窗口背后的内容做模糊，
/// 而不是模糊窗口自己的背景（那会得到一层灰）。
public struct VisualEffectView: NSViewRepresentable {

    public var material: NSVisualEffectView.Material
    public var blending: NSVisualEffectView.BlendingMode

    /// 初始化
    /// - Parameters:
    ///   - material: 材质，默认 `.hudWindow`
    ///   - blending: 混合模式，默认 `.behindWindow`
    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blending: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blending = blending
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.isEmphasized = false
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
    }
}
