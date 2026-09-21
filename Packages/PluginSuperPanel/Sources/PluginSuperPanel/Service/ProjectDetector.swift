// ProjectDetector.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Foundation
import QuickCore

/// 项目上下文检测器
///
/// 通过前台应用检测当前项目路径和类型。
/// 性能策略：
/// - 前台应用变化时才重新检测（不轮询）
/// - Git 分支名用 `git rev-parse` 异步获取，有缓存
/// - 项目类型通过标记文件判断（纯文件系统操作，微秒级）
@MainActor
final class ProjectDetector {

    private let log = QuickLog.plugin("superPanel")

    /// 上次检测到的上下文（缓存）
    private(set) var currentContext: ProjectContext?

    /// 上次检测的前台应用 Bundle ID
    private var lastFrontAppBundleID: String?

    /// 能检测项目的应用 Bundle ID 列表
    ///
    /// 这些应用通常有打开的项目/工作区。
    private static let knownIDEBundleIDs: Set<String> = [
        "com.apple.dt.Xcode",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "dev.zed.Zed",
        "com.sublimehq.3",
        "com.jetbrains.intellij",
        "com.jetbrains.WebStorm",
        "com.jetbrains.goland",
        "com.jetbrains.pycharm",
        "com.jetbrains.CLion",
        "com.jetbrains.AppCode",
        "com.googlecode.iterm2",
        "com.apple.Terminal"
    ]

    /// 检测当前项目上下文
    ///
    /// 只在前台应用变化时真正检测；同一应用重复调用返回缓存。
    func detect() async -> ProjectContext? {
        let frontApp = NSWorkspace.shared.frontmostApplication
        let bundleID = frontApp?.bundleIdentifier

        // 前台应用没变就返回缓存
        if bundleID == lastFrontAppBundleID, let cached = currentContext {
            return cached
        }
        lastFrontAppBundleID = bundleID

        guard let bundleID else {
            currentContext = nil
            return nil
        }

        // 获取项目路径
        guard let projectPath = await detectProjectPath(bundleID: bundleID, app: frontApp) else {
            currentContext = nil
            return nil
        }

        let context = buildContext(rootPath: projectPath, sourceBundleID: bundleID)
        currentContext = context
        log.notice("检测到项目：\(context.name, privacy: .public)（\(context.type.displayName, privacy: .public)）")
        return context
    }

    /// 强制刷新（清除缓存后重新检测）
    func refresh() async -> ProjectContext? {
        lastFrontAppBundleID = nil
        return await detect()
    }

    /// 获取前台应用的项目路径
    private func detectProjectPath(bundleID: String, app: NSRunningApplication?) async -> String? {
        // Xcode：通过 Apple Script 获取当前 workspace
        if bundleID == "com.apple.dt.Xcode" {
            return await xcodeFrontWorkspace()
        }

        // VS Code / Cursor / 终端 类应用：通过窗口标题推断
        if let app, Self.knownIDEBundleIDs.contains(bundleID) {
            return windowTitleProjectPath(app: app)
        }

        return nil
    }

    /// Xcode 当前工作区路径
    ///
    /// 通过 NSWorkspace.shared.runningApplications 获取打开的文档 URL。
    /// AppleScript 太慢（500ms+），改用 Accessibility API 读窗口标题。
    private func xcodeFrontWorkspace() async -> String? {
        let app = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == "com.apple.dt.Xcode"
        }
        guard let app else { return nil }
        return windowTitleProjectPath(app: app)
    }

    /// 从窗口标题推断项目路径
    ///
    /// IDE 窗口标题通常包含项目名或路径：
    /// - Xcode: "MyProject — Editing ViewController.swift"
    /// - VS Code: "main.py — MyProject"
    /// - Cursor: "main.py — MyProject"
    /// - Terminal: "~/Projects/MyProject — zsh"
    private func windowTitleProjectPath(app: NSRunningApplication) -> String? {
        // 使用 CGWindowListCopyWindowInfo 获取窗口信息
        guard
            let windowList = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return nil }

        let pid = app.processIdentifier

        // 找到该应用最上层的窗口
        for info in windowList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
                ownerPID == pid,
                let name = info[kCGWindowName as String] as? String,
                !name.isEmpty
            else { continue }

            // 从窗口标题提取路径
            if let path = extractProjectPath(from: name) {
                return path
            }
        }
        return nil
    }

    /// 从窗口标题提取项目路径
    ///
    /// 支持多种格式：
    /// - 完整路径 "/Users/xxx/Projects/MyProject"
    /// - 波浪号路径 "~/Projects/MyProject"
    /// - 只含项目名 "MyProject"（尝试在常见位置查找）
    private func extractProjectPath(from title: String) -> String? {
        // 标题中的分隔符（— 或 -）分割各段，每段都检测
        let separators = CharacterSet(charactersIn: "—–-")
        let segments = title.components(separatedBy: separators).map {
            $0.trimmingCharacters(in: .whitespaces)
        }

        for segment in segments {
            // 完整绝对路径
            if segment.hasPrefix("/"), FileManager.default.fileExists(atPath: segment) {
                return findProjectRoot(from: segment)
            }
            // 波浪号路径
            if segment.hasPrefix("~") {
                let expanded = NSString(string: segment).expandingTildeInPath
                if FileManager.default.fileExists(atPath: expanded) {
                    return findProjectRoot(from: expanded)
                }
            }
        }

        // 拿标题第一段当项目名，在常见路径搜索
        if let first = segments.first, !first.isEmpty {
            let home = NSHomeDirectory()
            let candidates = [
                "\(home)/Projects/\(first)",
                "\(home)/Developer/\(first)",
                "\(home)/Code/\(first)",
                "\(home)/Desktop/\(first)",
                "\(home)/Documents/\(first)"
            ]
            for path in candidates where FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        return nil
    }

    /// 从文件路径向上查找项目根目录
    ///
    /// 性能：最多向上遍历 10 层，每层只做 `fileExists` 判断。
    private func findProjectRoot(from path: String) -> String? {
        var current = path
        let fm = FileManager.default
        var isDir: ObjCBool = false

        // 如果是文件，先取目录
        if fm.fileExists(atPath: current, isDirectory: &isDir), !isDir.boolValue {
            current = (current as NSString).deletingLastPathComponent
        }

        // 向上遍历查找项目标志文件
        let markers: [String] = [
            ".git", "Package.swift", "*.xcodeproj", "*.xcworkspace",
            "package.json", "Cargo.toml", "go.mod", "pom.xml",
            "build.gradle", "requirements.txt", "pyproject.toml"
        ]

        for _ in 0..<10 {
            guard current != "/" else { break }
            for marker in markers {
                if marker.contains("*") {
                    let pattern = (current as NSString).appendingPathComponent(marker)
                    let globResult = glob(pattern: pattern)
                    if !globResult.isEmpty { return current }
                } else {
                    let markerPath = (current as NSString).appendingPathComponent(marker)
                    if fm.fileExists(atPath: markerPath) { return current }
                }
            }
            current = (current as NSString).deletingLastPathComponent
        }

        return nil
    }

    /// 简易 glob
    private func glob(pattern: String) -> [String] {
        let dir = (pattern as NSString).deletingLastPathComponent
        let name = (pattern as NSString).lastPathComponent
        let suffix = String(name.dropFirst())  // 去掉 *

        guard
            let contents = try? FileManager.default.contentsOfDirectory(atPath: dir)
        else { return [] }

        return contents.filter { $0.hasSuffix(suffix) }.map {
            (dir as NSString).appendingPathComponent($0)
        }
    }

    /// 构建项目上下文
    private func buildContext(rootPath: String, sourceBundleID: String?) -> ProjectContext {
        let name = (rootPath as NSString).lastPathComponent
        let type = detectProjectType(at: rootPath)
        let isGit = FileManager.default.fileExists(
            atPath: (rootPath as NSString).appendingPathComponent(".git"))
        let branch = isGit ? readGitBranch(at: rootPath) : nil

        return ProjectContext(
            rootPath: rootPath,
            name: name,
            type: type,
            isGitRepo: isGit,
            gitBranch: branch,
            sourceBundleID: sourceBundleID
        )
    }

    /// 检测项目类型（纯文件系统操作，微秒级）
    private func detectProjectType(at path: String) -> ProjectContext.ProjectType {
        let fm = FileManager.default
        let exists: (String) -> Bool = { marker in
            if marker.contains("*") {
                return !self.glob(pattern: (path as NSString).appendingPathComponent(marker)).isEmpty
            }
            return fm.fileExists(atPath: (path as NSString).appendingPathComponent(marker))
        }

        if exists("Package.swift") || exists("*.xcodeproj") || exists("*.xcworkspace") {
            return .xcode
        }
        if exists("package.json") { return .node }
        if exists("Cargo.toml") { return .rust }
        if exists("go.mod") { return .golang }
        if exists("pom.xml") || exists("build.gradle") { return .java }
        if exists("requirements.txt") || exists("pyproject.toml") || exists("setup.py") {
            return .python
        }
        return .generic
    }

    /// 读取 Git 分支名（同步、微秒级）
    ///
    /// 直接读 `.git/HEAD` 文件而不是跑 `git rev-parse`：
    /// 进程创建的开销是 5~20ms，读文件是微秒，差两个数量级。
    private func readGitBranch(at path: String) -> String? {
        let headPath = (path as NSString).appendingPathComponent(".git/HEAD")
        guard let content = try? String(contentsOfFile: headPath, encoding: .utf8) else {
            return nil
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "ref: refs/heads/"
        if trimmed.hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count))
        }
        // detached HEAD：取 hash 前 7 位
        return String(trimmed.prefix(7))
    }
}
