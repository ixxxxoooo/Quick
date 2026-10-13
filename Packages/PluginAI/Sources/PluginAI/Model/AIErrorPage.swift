// AIErrorPage.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// WebView 加载失败时展示的本地错误页
///
/// 纯文本生成、不依赖 AppKit，可单测。重试链接用自定义 scheme，由导航代理拦截后重新加载。
enum AIErrorPage {

    /// 重试链接的 scheme（导航代理据此识别「点了重试」）
    static let retryScheme = "quick-retry"

    /// 是否应该为这个错误展示错误页
    ///
    /// 用户主动取消（`NSURLErrorCancelled`）或被新导航顶掉的加载不算失败。
    static func shouldShow(for error: any Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return true }
        return nsError.code != NSURLErrorCancelled
    }

    /// 生成错误页 HTML
    static func html(providerName: String, message: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="color-scheme" content="light dark">
        <style>
        body{font:-apple-system-body;font-family:-apple-system,sans-serif;display:flex;
        flex-direction:column;align-items:center;justify-content:center;height:100vh;margin:0;
        text-align:center;color:CanvasText;background:Canvas}
        h2{font-weight:600;margin:0 0 8px}p{opacity:.65;margin:0 0 20px;max-width:420px}
        a{padding:8px 18px;border-radius:8px;background:AccentColor;color:white;text-decoration:none}
        </style></head><body>
        <h2>\(escape(providerName)) 加载失败</h2>
        <p>\(escape(message))</p>
        <a href="\(retryScheme)://reload">重试</a>
        </body></html>
        """
    }

    /// HTML 转义，避免错误信息里的特殊字符破坏页面
    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
