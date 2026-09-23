// AIProvider.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// AI 官网 Provider 定义
///
/// 每个 Provider 对应一个 AI 官网，在独立 WebView 窗口中保持登录态。
/// 参考 Fasty ai-portal 的 Provider 注册表设计。
struct AIProvider: Identifiable, Sendable {
    /// 唯一标识
    let id: String
    /// 显示名称
    let name: String
    /// 官网 URL
    let url: String
    /// SF Symbol 图标
    let icon: String
    /// 品牌主色（十六进制）
    let accent: String
    /// 搜索触发关键词
    let keywords: [String]
    /// 描述文字
    let description: String
}

/// 内置 AI Provider 注册表
///
/// 顺序即设置页和卡片展示顺序。
enum AIProviderRegistry {
    /// 全部内置 Provider
    static let all: [AIProvider] = [
        AIProvider(
            id: "deepseek",
            name: "DeepSeek",
            url: "https://chat.deepseek.com",
            icon: "brain.head.profile",
            accent: "#4D6BFE",
            keywords: ["deepseek", "ds", "深度求索"],
            description: "DeepSeek 官方对话"
        ),
        AIProvider(
            id: "chatgpt",
            name: "ChatGPT",
            url: "https://chatgpt.com",
            icon: "bubble.left.and.text.bubble.right",
            accent: "#10A37F",
            keywords: ["chatgpt", "gpt", "openai"],
            description: "OpenAI ChatGPT"
        ),
        AIProvider(
            id: "gemini",
            name: "Gemini",
            url: "https://gemini.google.com",
            icon: "sparkle",
            accent: "#8E75B2",
            keywords: ["gemini", "谷歌", "bard", "google"],
            description: "Google Gemini"
        ),
        AIProvider(
            id: "claude",
            name: "Claude",
            url: "https://claude.ai",
            icon: "text.bubble",
            accent: "#D97706",
            keywords: ["claude", "anthropic"],
            description: "Anthropic Claude"
        ),
        AIProvider(
            id: "doubao",
            name: "豆包",
            url: "https://www.doubao.com/chat/",
            icon: "leaf",
            accent: "#3B82F6",
            keywords: ["豆包", "doubao", "字节"],
            description: "字节跳动豆包"
        ),
        AIProvider(
            id: "kimi",
            name: "Kimi",
            url: "https://kimi.moonshot.cn",
            icon: "moon",
            accent: "#6366F1",
            keywords: ["kimi", "月之暗面", "moonshot"],
            description: "月之暗面 Kimi"
        ),
        AIProvider(
            id: "glm",
            name: "智谱清言",
            url: "https://chatglm.cn",
            icon: "wand.and.stars",
            accent: "#0F62FE",
            keywords: ["glm", "chatglm", "智谱", "zhipu", "清言"],
            description: "智谱 ChatGLM"
        ),
        AIProvider(
            id: "tongyi",
            name: "通义千问",
            url: "https://tongyi.aliyun.com",
            icon: "cloud",
            accent: "#FF6A00",
            keywords: ["通义", "千问", "tongyi", "qwen", "阿里"],
            description: "阿里云通义千问"
        )
    ]

    /// 按 ID 查找 Provider
    static func provider(for id: String) -> AIProvider? {
        all.first { $0.id == id }
    }

    /// 全部关键词并集（用于搜索闸门匹配）
    static var allKeywords: [String] {
        all.flatMap(\.keywords) + ["ai", "AI", "聊天", "对话", "chat", "ai portal", "ai聚合"]
    }

    /// 解析用户为某个 Provider 配置的自定义触发词
    ///
    /// 设置页存的是一整段原文（逗号 / 顿号 / 分号 / 空白分隔），这里统一切开、
    /// 小写、去空、去重，与内置关键词的存储约定一致（全小写、无空串，
    /// 见 `AIProviderRegistryTests.keywordsAreWellFormed`）。放在注册表而不是插件层：
    /// 解析规则就是关键词规范本身，改要跟着内置关键词的约定一起改。
    static func parseCustomKeywords(_ raw: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",，、;； \t\n\r")
        var seen = Set<String>()
        var keywords: [String] = []
        for token in raw.components(separatedBy: separators) {
            let keyword = token.trimmingCharacters(in: .whitespaces).lowercased()
            guard !keyword.isEmpty, seen.insert(keyword).inserted else { continue }
            keywords.append(keyword)
        }
        return keywords
    }
}
