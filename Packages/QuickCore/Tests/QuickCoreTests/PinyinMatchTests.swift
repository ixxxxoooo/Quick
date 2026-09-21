// PinyinMatchTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Testing

@testable import QuickCore

@Suite("拼音匹配")
struct PinyinMatchTests {

    /// 全拼应当命中汉字
    @Test("全拼命中汉字")
    func fullPinyinFindsHan() {
        #expect("微信".fuzzyMatch("weixin"))
        #expect("支付宝".fuzzyMatch("zhifubao"))
        #expect("腾讯会议".fuzzyMatch("tengxunhuiyi"))
    }

    /// 拼音首字母应当命中汉字
    @Test("首字母命中汉字")
    func initialsFindHan() {
        #expect("微信".fuzzyMatch("wx"))
        #expect("支付宝".fuzzyMatch("zfb"))
        #expect("腾讯会议".fuzzyMatch("txhy"))
    }

    /// 拼音打错不该命中 —— 否则首字母匹配会变成「打了字母就有结果」
    @Test("拼音打错时不命中")
    func wrongPinyinDoesNotMatch() {
        #expect(!"微信".fuzzyMatch("wz"))
        #expect("微信".fuzzyScore("weixinweixin") == 0)
    }

    /// 转写形态：全拼不留分隔，首字母取每段第一字
    @Test("转写形态")
    func formsShape() {
        #expect(MatchText("微信").pinyin?.latin == "weixin")
        #expect(MatchText("微信").pinyin?.initials == "wx")
        // 中英混排：拉丁词原样保留，跟着一起进首字母
        #expect(MatchText("微信 Dev").pinyin?.latin == "weixindev")
        #expect(MatchText("微信 Dev").pinyin?.initials == "wxd")
    }

    /// 纯拉丁候选不需要转写
    @Test("纯拉丁候选不做拼音转写")
    func latinCandidatesHaveNoPinyin() {
        #expect(MatchText("Safari").pinyin == nil)
        #expect(MatchText("Visual Studio Code").pinyin == nil)
    }

    /// 查询词里带汉字时走字面匹配
    @Test("中文查询按字面匹配")
    func chineseQueryMatchesLiterally() {
        #expect("微信".fuzzyScore("微") > 0)
        #expect("微信 Dev".fuzzyScore("dev") > 0)
        #expect(!"微信".fuzzyMatch("信微"))
    }

    /// 字面命中必须排在拼音命中之前：用户打 `wx` 时，名字真叫 WX 的那个更可能是目标
    @Test("字面命中排在拼音命中之前")
    func literalOutranksPinyin() {
        #expect("WX".fuzzyScore("wx") > "微信".fuzzyScore("wx"))
        #expect("Weixin".fuzzyScore("wei") > "微信".fuzzyScore("wei"))
        #expect("ZFB".fuzzyScore("zfb") > "支付宝".fuzzyScore("zfb"))
    }

    /// 全拼比首字母更明确
    @Test("全拼排在首字母之前")
    func fullPinyinOutranksInitials() {
        #expect("微信".fuzzyScore("weixin") > "微信".fuzzyScore("wx"))
    }

    /// 拼音终究是转写，不能压过任何一级字面命中
    @Test("拼音命中低于字面命中")
    func pinyinStaysBelowLiteralTiers() {
        #expect("微信".fuzzyScore("weixin") < "Weixin".fuzzyScore("wei"))
    }

    /// 全角输入（中文输入法没切英文键盘）也要能命中
    @Test("全角输入命中")
    func fullWidthInputMatches() {
        #expect("Visual Studio Code".fuzzyScore("ｖｓｃ") > 0)
    }
}
