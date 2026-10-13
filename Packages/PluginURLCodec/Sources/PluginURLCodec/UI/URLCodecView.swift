// URLCodecView.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import QuickCore
import QuickUI
import SwiftUI

struct URLCodecView: View {
    /// 输入文本归插件所有：主面板与分离窗口共享同一份，分离时内容自然带过去
    @Bindable var buffer: TextBuffer

    private var input: String {
        get { buffer.text }
        nonmutating set { buffer.text = newValue }
    }
    @State private var output = ""
    @State private var mode: Mode = .encode

    /// 解码失败的原因（nil 表示上一次转换成功）
    ///
    /// 单独存一份而不是从 output 反推：失败时 output 是空的，
    /// 空结果和「输入为空」在界面上无法区分。
    @State private var error: String?
    /// 大输入走防抖 + 后台计算，小输入同步算（见 `Debouncer`）
    @State private var debouncer = Debouncer()

    /// 编码选项与设置页共用同一个键：那边改了这边立即生效
    @AppStorage(PluginSettingKey.URLCodec.encodeSpacesAsPluses) private var spacesAsPluses = false
    @AppStorage(PluginSettingKey.URLCodec.encodeFullUrl) private var encodeFullUrl = false

    private var options: URLCodecLogic.Options {
        .init(encodesSpacesAsPluses: spacesAsPluses, encodesFullURL: encodeFullUrl)
    }

    enum Mode: String, CaseIterable {
        case encode = "编码"
        case decode = "解码"
    }

    var body: some View {
        CodecWorkbench(
            isEncode: Binding(get: { mode == .encode }, set: { mode = $0 ? .encode : .decode }),
            input: $buffer.text,
            output: $output,
            error: $error,
            encodedTitle: "已编码",
            onTransform: transform
        )
        .onChange(of: input) { _, _ in transform() }
        .onChange(of: spacesAsPluses) { _, _ in transform() }
        .onChange(of: encodeFullUrl) { _, _ in transform() }
        .onChange(of: mode) { _, _ in transform() }
        .onDisappear { debouncer.cancel() }
    }

    private func transform() {
        guard !input.isEmpty else {
            debouncer.cancel()
            output = ""
            error = nil
            return
        }
        // 把要用的值拷成局部常量：计算在后台线程跑，闭包不能碰视图状态
        let text = input
        let isEncode = mode == .encode
        let currentOptions = options
        debouncer.schedule(
            weight: text.utf8.count,
            work: {
                Result {
                    isEncode
                        ? URLCodecLogic.encode(text, options: currentOptions)
                        : try URLCodecLogic.decode(text, options: currentOptions)
                }
            },
            apply: { result in
                switch result {
                case .success(let value):
                    output = value
                    error = nil
                case .failure:
                    output = ""
                    error = "解码失败：存在非法的百分号序列"
                }
            })
    }
}
