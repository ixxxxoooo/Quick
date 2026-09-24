// FileSearchPreferences.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// 文件搜索的偏好
///
/// 纯数据：服务按它构造谓词、过滤与截断，至于值从哪个键读出来、用户什么时候改的，
/// 由 `FileSearchPreferences.current` 负责。
public struct FileSearchSettings: Sendable, Equatable {

    /// 单次搜索最多返回的文件数量
    public let maxResults: Int

    /// 是否丢掉隐藏文件
    public let ignoreHidden: Bool

    /// 是否连文件内的文本内容一起匹配
    public let includeContents: Bool
}

/// 文件搜索偏好的读取与映射
///
/// 读键的动作发生在**每次搜索时**，不是在服务 init 里读一次：
/// 设置页可以在应用运行期间随时改，捕获一次的话用户就会看到「改了没反应」。
public enum FileSearchPreferences {

    /// 设置页里可选的结果条数
    public static let resultChoices = [20, 50, 100, 200]

    /// 设置页在「从未设置过」时的默认条数
    public static let defaultMaxResults = 50

    /// 把存储值映射成合法的结果上限
    ///
    /// `UserDefaults.integer(forKey:)` 对没写过的键返回 0，手改过的值也可能是任意整数，
    /// 所以非法输入一律回落到设置页显示的默认档 —— 上限为 0 会让搜索结果永远是空的。
    public static func maxResults(storedValue: Int) -> Int {
        resultChoices.contains(storedValue) ? storedValue : defaultMaxResults
    }

    /// 当前的三项设置
    public static func current(defaults: UserDefaults = .standard) -> FileSearchSettings {
        FileSearchSettings(
            maxResults: maxResults(
                storedValue: defaults.integer(forKey: SettingsKey.fileSearchMaxResults)),
            // 没写过这两个键时要按设置页显示的档位处理：忽略隐藏文件是「开」，搜索内容是「关」
            ignoreHidden: boolValue(
                forKey: SettingsKey.fileSearchIgnoreHidden,
                fallback: true,
                defaults: defaults
            ),
            includeContents: boolValue(
                forKey: SettingsKey.fileSearchIncludeContents,
                fallback: false,
                defaults: defaults
            )
        )
    }

    /// 读布尔值，未设置过（`object` 为 nil）时返回 `fallback`
    private static func boolValue(
        forKey key: String,
        fallback: Bool,
        defaults: UserDefaults
    ) -> Bool {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.bool(forKey: key)
    }
}

/// 搜索结果的后处理：过滤隐藏文件、按上限截断
///
/// 与元素类型无关的纯逻辑，所以不用跑 Spotlight 就能把两个开关的效果钉死；
/// 服务只负责把 `NSMetadataItem` 读成结果，再交给这里。
public enum FileSearchFiltering {

    /// 路径里是否存在以 `.` 开头的一段
    ///
    /// 逐段判断而不是看首字符：`/Users/x/.config/quick.json` 本身不以点开头，
    /// 但它藏在隐藏目录里，设置页承诺的「不搜索以 . 开头的文件和目录」同样覆盖它。
    public static func isHidden(path: String) -> Bool {
        path.split(separator: "/").contains { $0.hasPrefix(".") }
    }

    /// 按设置过滤并截断
    /// - Parameters:
    ///   - ignoringHidden: 为 true 时丢掉隐藏项
    ///   - limit: 最多保留多少条
    ///   - items: 原始结果
    ///   - path: 从元素里取文件路径
    /// - Returns: 过滤并截断后的结果
    public static func applying<T>(
        ignoringHidden: Bool,
        limit: Int,
        to items: [T],
        path: (T) -> String
    ) -> [T] {
        let kept = ignoringHidden ? items.filter { !isHidden(path: path($0)) } : items
        return Array(kept.prefix(limit))
    }
}
