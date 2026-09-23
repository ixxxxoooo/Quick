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

    /// 编码选项
    ///
    /// 视图从 `@AppStorage`（`urlCodec.encodeSpacesAsPluses` / `urlCodec.encodeFullUrl`，
    /// 与设置页同一个键）读出来后传进来，逻辑层不碰 `UserDefaults`。
    struct Options: Equatable, Sendable {
        /// 空格编成 `+`（application/x-www-form-urlencoded 约定）而不是 `%20`
        var encodesSpacesAsPluses = false
        /// 完整 URL 模式：保留 `://` 等结构分隔符，只编非保留字符
        var encodesFullURL = false

        /// 默认行为：查询串组件编码
        static let `default` = Options()
    }

    /// 查询组件模式：从 `.urlQueryAllowed` 去掉结构分隔符，仍保留 `&` `=` 方便粘贴进查询串
    ///
    /// Foundation 的 `.urlQueryAllowed` 仍放行冒号与斜杠，拿来当「组件编码」会让
    /// `https://…` 原样通过，和「完整 URL 模式」分不出差别。
    private static let queryComponentAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: ":/?#[]@")
        return set
    }()

    /// 完整 URL 模式的放行字符集：在查询组件基础上补回结构分隔符
    private static let fullURLAllowed: CharacterSet = {
        var set = queryComponentAllowed
        set.insert(charactersIn: ":/?#[]@")
        return set
    }()

    /// 百分号编码
    ///
    /// 默认编码 `:` `/` 等结构字符，但 `&` `=` 保持原样以便粘贴进查询串。
    /// 打开 `encodesFullURL` 后保留 URL 结构，只编非保留字符。
    static func encode(_ input: String, options: Options = .default) -> String {
        let allowed = options.encodesFullURL ? fullURLAllowed : queryComponentAllowed
        let encoded = input.addingPercentEncoding(withAllowedCharacters: allowed) ?? input
        guard options.encodesSpacesAsPluses else { return encoded }
        return encoded.replacingOccurrences(of: "%20", with: "+")
    }

    /// 百分号解码
    ///
    /// 非法序列返回错误而不是回退原文：回退会让界面显示「解码完成」却原样输出，
    /// 用户无从发现输入本身有问题，也会把非法输入当成解码结果复制走。
    static func decode(_ input: String, options: Options = .default) throws -> String {
        // 编码侧把空格写成了 +，解码侧就得认回来，否则往返不一致
        let normalized =
            options.encodesSpacesAsPluses
            ? input.replacingOccurrences(of: "+", with: " ") : input
        guard let decoded = normalized.removingPercentEncoding else {
            throw DecodeError.malformedPercentSequence
        }
        return decoded
    }
}
