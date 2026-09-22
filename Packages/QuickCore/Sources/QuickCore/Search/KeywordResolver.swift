// KeywordResolver.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 用关键字找到唯一一条命令
///
/// 和 uTools、Fasty 一样：关键字就是功能本身。用户输入「锁定屏幕」或插件声明的
/// 唤醒词，命中的是那一条功能，不是一份下拉菜单。多个功能可以各有自己的关键字，
/// 同一个字同时对上两条时拒绝猜测，让用户写得更具体。
public enum KeywordResolver {

    /// 解析关键字
    ///
    /// - Parameters:
    ///   - query: 用户输入
    ///   - commands: 候选命令
    /// - Returns: 唯一命中；空输入、没有命中、或命中多条时返回 nil
    public static func match(query: String, commands: [CommandDescriptor]) -> CommandDescriptor? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let hits = commands.filter { command in
            command.title.compare(trimmed, options: .caseInsensitive) == .orderedSame
                || command.keywords.contains {
                    $0.compare(trimmed, options: .caseInsensitive) == .orderedSame
                }
        }
        guard hits.count == 1 else { return nil }
        return hits[0]
    }
}
