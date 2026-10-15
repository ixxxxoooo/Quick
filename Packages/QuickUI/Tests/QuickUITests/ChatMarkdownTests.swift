// ChatMarkdownTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Testing

@testable import QuickUI

@Suite("ChatMarkdown 块解析")
struct ChatMarkdownTests {

    @Test("空行分段，段内换行保留")
    func paragraphs() {
        let blocks = ChatMarkdown.parse("第一行\n第二行\n\n第二段")
        #expect(blocks == [.paragraph("第一行\n第二行"), .paragraph("第二段")])
    }

    @Test("标题要求 # 后有空格")
    func headings() {
        #expect(ChatMarkdown.parse("## 小标题") == [.heading(level: 2, text: "小标题")])
        #expect(ChatMarkdown.parse("#标签") == [.paragraph("#标签")])
        #expect(ChatMarkdown.parse("####### 七个") == [.paragraph("####### 七个")])
    }

    @Test("无序与有序列表，缩进折算层级")
    func lists() {
        let blocks = ChatMarkdown.parse("- 甲\n  - 乙\n1. 一\n2) 二")
        #expect(
            blocks == [
                .bullet(text: "甲", indent: 0), .bullet(text: "乙", indent: 1),
                .numbered(number: "1", text: "一", indent: 0),
                .numbered(number: "2", text: "二", indent: 0)
            ])
    }

    @Test("星号开头但没有空格不是列表（粗体）")
    func boldIsNotBullet() {
        #expect(ChatMarkdown.parse("**粗体** 文字") == [.paragraph("**粗体** 文字")])
    }

    @Test("引用块合并连续行")
    func quotes() {
        #expect(ChatMarkdown.parse("> 甲\n> 乙") == [.quote("甲\n乙")])
    }

    @Test("分隔线")
    func rules() {
        #expect(ChatMarkdown.parse("上\n\n---\n\n下") == [.paragraph("上"), .rule, .paragraph("下")])
    }

    @Test("代码块保留语言与原样缩进，块内的 # 与 - 不被解析")
    func codeBlock() {
        let text = "前\n```swift\n# 注释\n- 减号\n    缩进\n```\n后"
        #expect(
            ChatMarkdown.parse(text) == [
                .paragraph("前"),
                .code(language: "swift", code: "# 注释\n- 减号\n    缩进"),
                .paragraph("后")
            ])
    }

    @Test("流式中途围栏未闭合：已有内容照样当代码")
    func unclosedFence() {
        #expect(
            ChatMarkdown.parse("```python\nprint(1)")
                == [.code(language: "python", code: "print(1)")])
        #expect(ChatMarkdown.parse("```") == [.code(language: nil, code: "")])
    }

    @Test("空文本没有块")
    func empty() {
        #expect(ChatMarkdown.parse("").isEmpty)
        #expect(ChatMarkdown.parse("\n\n").isEmpty)
    }

    @Test("行内样式解析失败时回落纯文本，不崩")
    func inlineFallback() {
        let text = String(ChatMarkdown.inline("**未闭合 `代码").characters)
        #expect(text.contains("未闭合"))
    }
}
