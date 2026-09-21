// Pinyin.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Synchronization

/// 汉字到拼音的转写
///
/// 拼音匹配不需要码表：`kCFStringTransformMandarinLatin` 是系统自带的汉字转写，
/// 覆盖整个基本区，比手工维护的字表全，也不引入依赖。
///
/// 转写不便宜，而候选在一次搜索会话里是不变的，所以结果按原串缓存。
/// 缓存只装含汉字的字符串 —— 纯拉丁的候选压根不需要转写。
enum Pinyin {

    /// 一个字符串的拼音形态
    struct Forms: Equatable, Sendable {
        /// 全拼，音节之间不留分隔：`微信` → `weixin`
        let latin: String
        /// 每个音节的首字母：`微信` → `wx`
        let initials: String
    }

    private static let cache = Mutex<[String: Forms]>([:])

    /// 取字符串的拼音形态
    ///
    /// - Parameter text: 待转写的文本
    /// - Returns: 拼音形态；不含汉字时返回 `nil`
    static func forms(of text: String) -> Forms? {
        guard text.containsHan else { return nil }

        if let cached = cache.withLock({ $0[text] }) { return cached }

        let forms = transcribe(text)
        cache.withLock { $0[text] = forms }
        return forms
    }

    /// 调用系统转写
    ///
    /// 转写结果里每个汉字对应一个音节，音节之间由空格分开；本来就有的拉丁词原样保留。
    /// 所以「按非字母数字切分」正好得到音节列表，每段的首字母就是拼音首字母。
    private static func transcribe(_ text: String) -> Forms {
        let buffer = NSMutableString(string: text)
        CFStringTransform(buffer, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(buffer, nil, kCFStringTransformStripDiacritics, false)

        // 汉字在转写结果里带上了声调符号，上一步已经去掉；剩下转写不了的音节
        // （假名、谚文、生僻字）会原样留下，整段丢掉，免得混进首字母里。
        let syllables = (buffer as String)
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .filter { !String($0).containsCJK }

        return Forms(
            latin: syllables.joined(),
            initials: syllables.map { String($0.prefix(1)) }.joined()
        )
    }
}
