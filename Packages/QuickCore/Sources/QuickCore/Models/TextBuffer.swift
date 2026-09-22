// TextBuffer.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Observation

/// 插件面板里一段文本的工作状态
///
/// **它归插件所有，而不是视图里的 `@State`。** 视图的 `@State` 只活在那一棵视图树里：
/// 主面板里敲进去的内容，一旦「分离成独立窗口」就会随旧视图一起销毁，新窗口从空开始。
/// 把这块状态提到插件上、`makeView()` 每次都把同一个实例交给视图，主面板与分离窗口就读写
/// 同一份数据 —— 分离时自然把「当时里面的内容」带过去。
///
/// 只存纯文本：它不认识任何 AppKit / SwiftUI，也不关心自己属于哪个插件。
@MainActor
@Observable
public final class TextBuffer {

    /// 当前文本
    public var text: String

    public init(_ text: String = "") {
        self.text = text
    }
}
