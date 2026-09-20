// URLCodecLogic.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// URL 编解码的纯逻辑
///
/// 界面只负责持有 `@State` 与呈现，编码/解码规则集中在这里 ——
/// `Model/` 里禁止出现任何 UI 框架，这条红线由编译期保证，
/// 好处是这块逻辑能被测试单独编译、单独验证。
enum URLCodecLogic {

    /// 解码失败的原因
    enum DecodeError: Error, Equatable {
        /// 输入里存在非法的百分号序列（`%ZZ`、结尾孤立的 `%`、`%2` 等）
        case malformedPercentSequence
    }

    /// 百分号编码
    ///
    /// 沿用 `.urlQueryAllowed`：空格编成 `%20` 而不是 `+`，
    /// 且 `&` `=` 等分隔符保持原样，粘贴进查询串不会被二次转义。
    static func encode(_ input: String) -> String {
        input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
    }

    /// 百分号解码
    ///
    /// 非法序列返回错误而不是回退原文：回退会让界面显示「解码完成」却原样输出，
    /// 用户无从发现输入本身有问题，也会把非法输入当成解码结果复制走。
    static func decode(_ input: String) throws -> String {
        guard let decoded = input.removingPercentEncoding else {
            throw DecodeError.malformedPercentSequence
        }
        return decoded
    }
}
