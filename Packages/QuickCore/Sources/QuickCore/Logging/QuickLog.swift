// QuickLog.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import os

/// 统一日志入口
///
/// 本项目的硬性要求：所有代码、所有功能都要有完善的日志，出问题时能只靠日志定位。
/// 全仓**禁止裸 `print`** —— 它不进统一日志系统，没有级别、没有分类、生产环境抓不到。
///
/// 用法：
/// ```swift
/// private let log = QuickLog.module(ClipboardModule.id)
/// log.info("模块已激活，加载 \(entries.count, privacy: .public) 条历史")
/// log.error("写入失败: \(url.lastPathComponent, privacy: .public)")
/// ```
///
/// 分级与必须打日志的位置见 docs/logging.md。
public enum QuickLog {

    /// 日志子系统。
    ///
    /// 取 bundle id，所以 Debug 构建（`com.ygw.quick.dev`）的日志不会和已安装版本
    /// 混在一起 —— 这正是 `Scripts/logs.sh --dev` 能生效的原因。
    /// 在 SPM 测试里 `Bundle.main` 是测试宿主，bundle id 可能为 nil，此时回退到默认值。
    public static let subsystem: String =
        Bundle.main.bundleIdentifier ?? "com.ygw.quick"

    // MARK: - 固定区域

    /// 应用生命周期：启动、模块注册、退出的各阶段
    public static let app = Logger(subsystem: subsystem, category: Category.app)

    /// 面板：显隐、定位、模式切换、聚合搜索
    public static let palette = Logger(subsystem: subsystem, category: Category.palette)

    /// 全局快捷键：注册、注销、失败
    public static let hotKey = Logger(subsystem: subsystem, category: Category.hotKey)

    /// 事件总线
    public static let eventBus = Logger(subsystem: subsystem, category: Category.eventBus)

    /// 系统能力封装：权限、应用扫描、粘贴板、图标缓存
    public static let platform = Logger(subsystem: subsystem, category: Category.platform)

    /// 共享 UI 与设计系统
    public static let ui = Logger(subsystem: subsystem, category: Category.ui)

    /// 持久化读写
    public static let persistence = Logger(subsystem: subsystem, category: Category.persistence)

    // MARK: - 模块日志

    /// 取某个模块的日志通道
    ///
    /// 分类形如 `module.launcher`，可以用
    /// `log stream --predicate 'category BEGINSWITH "module."'` 一次性看所有模块。
    ///
    /// - Parameter id: 模块的 `QuickModule.id`，必须与注册时使用的 id 一致
    /// - Returns: 该模块专用的 `Logger`
    public static func module(_ id: String) -> Logger {
        Logger(subsystem: subsystem, category: "\(Category.modulePrefix)\(id)")
    }

    /// 取任意分类的日志通道（用于上面没列出的新区域）
    ///
    /// - Parameter category: 分类名，用点分小写英文，如 `backup.export`
    /// - Returns: 对应的 `Logger`
    public static func logger(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }

    // MARK: - 性能测量

    /// 取某区域的 signposter，用于在 Instruments 里看耗时区间
    ///
    /// 性能敏感路径（面板显隐、聚合搜索、应用扫描、文件索引、网络请求）
    /// 必须用 signpost 而不是手算耗时打 info —— 后者既慢又没法和 Instruments 对齐。
    ///
    /// ```swift
    /// let signpost = QuickLog.signposter(Category.palette)
    /// let id = signpost.begin("palette.show")
    /// defer { signpost.end("palette.show", id: id) }
    /// ```
    ///
    /// - Parameter category: 区域名，与日志分类保持一致最便于对照
    /// - Returns: 该区域的 `OSSignposter`
    public static func signposter(_ category: String) -> OSSignposter {
        OSSignposter(subsystem: subsystem, category: category)
    }

    // MARK: - 分类常量

    /// 分类名的集中定义
    ///
    /// 常量化的目的是让「有哪些分类」可以被 grep 到，避免同一区域出现两种拼写
    /// （`hotkey` 和 `hotKey` 会变成两个分类，日志就散了）。
    public enum Category {
        public static let app = "app"
        public static let palette = "palette"
        public static let hotKey = "hotkey"
        public static let eventBus = "eventbus"
        public static let platform = "platform"
        public static let ui = "ui"
        public static let persistence = "persistence"

        /// 模块分类的统一前缀，最终形如 `module.clipboard`
        public static let modulePrefix = "module."
    }
}
