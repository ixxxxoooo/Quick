// PaletteAutoBehavior.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// 面板打开时的自动行为：自动粘贴剪贴板、自动清空旧查询
///
/// 判定逻辑抽成纯函数：它只比较几个时间点，不碰剪贴板、不碰窗口，所以能直接测 ——
/// 而这几个「时间窗」的边界正是最容易写错的地方（`<` 还是 `<=`、没有记录时算不算）。
public enum PaletteAutoBehavior {

    /// 自动粘贴的时间窗选项
    public enum AutoPasteWindow: Int, CaseIterable, Identifiable, Sendable {
        case off = 0
        case fiveSeconds = 5
        case tenSeconds = 10
        case thirtySeconds = 30

        public var id: Self { self }

        public var title: String {
            switch self {
            case .off: "关闭"
            case .fiveSeconds: "5 秒内"
            case .tenSeconds: "10 秒内"
            case .thirtySeconds: "30 秒内"
            }
        }
    }

    /// 自动清空的空闲时间选项
    public enum AutoClearIdle: Int, CaseIterable, Identifiable, Sendable {
        case off = 0
        case oneMinute = 1
        case threeMinutes = 3
        case tenMinutes = 10

        public var id: Self { self }

        public var title: String {
            switch self {
            case .off: "关闭"
            case .oneMinute: "1 分钟"
            case .threeMinutes: "3 分钟"
            case .tenMinutes: "10 分钟"
            }
        }
    }

    // MARK: - 出厂默认

    /// 出厂默认的自动粘贴时间窗
    ///
    /// 设置页的 `@AppStorage` 与这里的读取方**必须是同一份常量**。两边各写各的就会出现
    /// 「设置页写着 5 秒内、实际行为是关闭」：`@AppStorage` 的默认值只在键不存在时生效，
    /// 而 `integer(forKey:)` 在键不存在时读到 `0`（见 docs/ui.md §11）。
    public static let defaultPasteWindow: AutoPasteWindow = .fiveSeconds

    /// 出厂默认的自动清空空闲时间
    public static let defaultClearIdle: AutoClearIdle = .threeMinutes

    // MARK: - 读取设置

    /// 当前设置下的自动粘贴时间窗
    ///
    /// - Parameter defaults: 偏好域（测试传自己的 suite）
    /// - Returns: 用户选过的取值；没设置过、或存的取值认不出来时，返回默认值
    public static func pasteWindow(from defaults: UserDefaults = .standard) -> AutoPasteWindow {
        option(key: SettingsKey.paletteAutoPasteSeconds, fallback: defaultPasteWindow, from: defaults)
    }

    /// 当前设置下的自动清空空闲时间
    ///
    /// - Parameter defaults: 偏好域（测试传自己的 suite）
    /// - Returns: 用户选过的取值；没设置过、或存的取值认不出来时，返回默认值
    public static func clearIdle(from defaults: UserDefaults = .standard) -> AutoClearIdle {
        option(key: SettingsKey.paletteAutoClearMinutes, fallback: defaultClearIdle, from: defaults)
    }

    /// 读一个以整数为 `rawValue` 的选项
    ///
    /// 「没设置过」和「显式关掉」必须分开：前者用默认值，后者就是用户选的关闭 ——
    /// 所以先判 `object(forKey:) != nil`，不能直接用 `integer(forKey:)`（它把两者都读成 0）。
    private static func option<T: RawRepresentable>(
        key: String,
        fallback: T,
        from defaults: UserDefaults
    ) -> T where T.RawValue == Int {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return T(rawValue: defaults.integer(forKey: key)) ?? fallback
    }

    /// 打开面板时是否该把剪贴板内容填进搜索框
    ///
    /// - Parameters:
    ///   - lastClipboardChange: 剪贴板最后一次变化的时刻；从未变化过为 nil
    ///   - now: 当前时刻
    ///   - window: 时间窗（秒）；0 表示关闭
    ///   - clipboardText: 当前剪贴板文本；空则没什么可填的
    ///   - currentQuery: 搜索框里已有的文本；非空说明用户有未完成的输入，不要覆盖
    /// - Returns: 是否填入
    public static func shouldPrefillFromClipboard(
        lastClipboardChange: Date?,
        now: Date,
        window: TimeInterval,
        clipboardText: String,
        currentQuery: String
    ) -> Bool {
        guard window > 0 else { return false }
        guard !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        // 用户已经打了一半的字不能被剪贴板内容顶掉
        guard currentQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard let lastClipboardChange else { return false }
        return now.timeIntervalSince(lastClipboardChange) <= window
    }

    /// 打开面板时是否该清空搜索框里的旧内容
    ///
    /// - Parameters:
    ///   - lastEditedAt: 搜索框最后一次改动的时刻；从没改过为 nil
    ///   - now: 当前时刻
    ///   - idleMinutes: 空闲多久算旧（分钟）；0 表示关闭
    ///   - currentQuery: 搜索框里的文本
    /// - Returns: 是否清空
    public static func shouldClearStaleQuery(
        lastEditedAt: Date?,
        now: Date,
        idleMinutes: Int,
        currentQuery: String
    ) -> Bool {
        guard idleMinutes > 0 else { return false }
        guard !currentQuery.isEmpty else { return false }
        // 没有时间戳（例如查询是启动参数预填的）不当作旧内容：宁可留着也不要莫名清掉
        guard let lastEditedAt else { return false }
        return now.timeIntervalSince(lastEditedAt) >= TimeInterval(idleMinutes) * 60
    }
}
