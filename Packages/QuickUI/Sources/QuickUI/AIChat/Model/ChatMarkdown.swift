// ChatMarkdown.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 对话消息里的一个 Markdown 块
public enum ChatMarkdownBlock: Equatable, Sendable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case bullet(text: String, indent: Int)
    case numbered(number: String, text: String, indent: Int)
    case quote(String)
    case code(language: String?, code: String)
    case rule
}

/// 把模型回复拆成块
///
/// 只做对话里真正会出现的那一小撮：标题、列表、引用、代码块、分隔线、段落。
/// 行内样式（粗体、斜体、行内代码、链接）交给系统的 `AttributedString(markdown:)`。
/// 不引入第三方 Markdown 库，也不去追完整的 CommonMark。
///
/// **必须容忍不完整的输入**：流式生成时文本随时在任意位置被截断，
/// 最典型的是代码块只有开头的 ``` 还没闭合 —— 此时把已有内容当代码显示，
/// 而不是等闭合后整块突然从正文变成代码。
public enum ChatMarkdown {

    public static func parse(_ text: String) -> [ChatMarkdownBlock] {
        var blocks: [ChatMarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var code: [String]?
        var codeLanguage: String?

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }
        func flushQuote() {
            guard !quote.isEmpty else { return }
            blocks.append(.quote(quote.joined(separator: "\n")))
            quote.removeAll()
        }
        func flushText() {
            flushParagraph()
            flushQuote()
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 代码块内：原样收集，直到闭合围栏
            if code != nil {
                if trimmed.hasPrefix("```") {
                    blocks.append(.code(language: codeLanguage, code: code!.joined(separator: "\n")))
                    code = nil
                    codeLanguage = nil
                } else {
                    code!.append(line)
                }
                continue
            }

            if trimmed.hasPrefix("```") {
                flushText()
                let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                codeLanguage = language.isEmpty ? nil : language
                code = []
                continue
            }

            if trimmed.isEmpty {
                flushText()
                continue
            }

            if isRule(trimmed) {
                flushText()
                blocks.append(.rule)
                continue
            }

            if let (level, content) = heading(trimmed) {
                flushText()
                blocks.append(.heading(level: level, text: content))
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }

            if let item = listItem(line) {
                flushText()
                blocks.append(item)
                continue
            }

            flushQuote()
            paragraph.append(line)
        }

        flushText()
        // 流式中途：围栏还没闭合，已有内容照样当代码块显示
        if let code {
            blocks.append(.code(language: codeLanguage, code: code.joined(separator: "\n")))
        }
        return blocks
    }

    /// 行内 Markdown（粗体 / 斜体 / 行内代码 / 链接）；解析失败回落成纯文本
    public static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    // MARK: - 行级识别

    private static func isRule(_ line: String) -> Bool {
        guard line.count >= 3, let first = line.first, "-*_".contains(first) else { return false }
        return line.allSatisfy { $0 == first }
    }

    private static func heading(_ line: String) -> (Int, String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        // `#` 后必须跟空格：`#标签` 不是标题
        guard rest.first == " " else { return nil }
        let content = rest.trimmingCharacters(in: .whitespaces)
        return content.isEmpty ? nil : (hashes, content)
    }

    private static func listItem(_ line: String) -> ChatMarkdownBlock? {
        let leading = line.prefix { $0 == " " || $0 == "\t" }
        let indent = leading.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2
        let body = line.dropFirst(leading.count)

        if let marker = body.first, "-*+".contains(marker),
            body.dropFirst().first == " "
        {
            let content = body.dropFirst(2).trimmingCharacters(in: .whitespaces)
            return content.isEmpty ? nil : .bullet(text: content, indent: indent)
        }

        let digits = body.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let afterDigits = body.dropFirst(digits.count)
        guard let punctuation = afterDigits.first, ".)".contains(punctuation),
            afterDigits.dropFirst().first == " "
        else { return nil }
        let content = afterDigits.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return content.isEmpty ? nil : .numbered(number: String(digits), text: content, indent: indent)
    }
}
