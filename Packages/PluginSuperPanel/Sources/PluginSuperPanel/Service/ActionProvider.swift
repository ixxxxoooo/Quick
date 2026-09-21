// ActionProvider.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import AppKit
import Foundation
import QuickCore

/// 超级面板操作提供器
///
/// 根据项目上下文生成可用的快速操作列表。
/// 性能策略：
/// - 操作列表随上下文缓存，上下文不变不重新计算
/// - 所有文件系统操作（`fileExists`）在生成时一次性完成
/// - `searchItems` 只做内存过滤
@MainActor
final class ActionProvider {

    private let log = QuickLog.plugin("superPanel")

    /// 上次缓存对应的项目路径
    private var cachedPath: String?

    /// 缓存的操作列表
    private var cachedActions: [SuperPanelAction] = []

    /// 根据项目上下文生成操作列表
    ///
    /// 相同项目路径返回缓存，避免重复的文件系统检测。
    func actions(for context: ProjectContext) -> [SuperPanelAction] {
        if context.rootPath == cachedPath {
            return cachedActions
        }

        var result: [SuperPanelAction] = []

        // 通用操作（所有项目都有）
        result.append(contentsOf: commonActions(for: context))

        // Git 操作
        if context.isGitRepo {
            result.append(contentsOf: gitActions(for: context))
        }

        // 项目类型特定操作
        result.append(contentsOf: typeSpecificActions(for: context))

        // 快速导航
        result.append(contentsOf: quickNavigationActions(for: context))

        cachedPath = context.rootPath
        cachedActions = result
        log.debug("为 \(context.name, privacy: .public) 生成 \(result.count) 个操作")
        return result
    }

    /// 清除缓存（上下文变化时调用）
    func invalidateCache() {
        cachedPath = nil
        cachedActions = []
    }

    // MARK: - 通用操作

    private func commonActions(for context: ProjectContext) -> [SuperPanelAction] {
        let root = context.rootPath
        return [
            SuperPanelAction(
                id: "sp.open-terminal",
                title: "在终端中打开",
                subtitle: root,
                icon: "terminal",
                category: .terminal,
                execute: {
                    Self.openInTerminal(path: root)
                }
            ),
            SuperPanelAction(
                id: "sp.open-finder",
                title: "在 Finder 中显示",
                subtitle: root,
                icon: "folder",
                category: .file,
                execute: {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: root)
                    EventBus.shared.post(HidePaletteEvent())
                }
            ),
            SuperPanelAction(
                id: "sp.copy-path",
                title: "复制项目路径",
                subtitle: root,
                icon: "doc.on.doc",
                category: .quick,
                execute: {
                    EventBus.shared.post(CopyToClipboardEvent(text: root))
                    EventBus.shared.post(ShowHUDEvent(message: "已复制路径", tone: .success))
                }
            ),
            SuperPanelAction(
                id: "sp.open-vscode",
                title: "在 VS Code 中打开",
                subtitle: root,
                icon: "chevron.left.forwardslash.chevron.right",
                category: .quick,
                execute: {
                    Self.openInApp(path: root, appName: "Visual Studio Code")
                }
            ),
            SuperPanelAction(
                id: "sp.open-cursor",
                title: "在 Cursor 中打开",
                subtitle: root,
                icon: "cursorarrow.rays",
                category: .quick,
                execute: {
                    Self.openInApp(path: root, appName: "Cursor")
                }
            )
        ]
    }

    // MARK: - Git 操作

    private func gitActions(for context: ProjectContext) -> [SuperPanelAction] {
        let root = context.rootPath
        var actions: [SuperPanelAction] = []

        if let branch = context.gitBranch {
            actions.append(
                SuperPanelAction(
                    id: "sp.git-branch",
                    title: "当前分支：\(branch)",
                    subtitle: "点击复制分支名",
                    icon: "arrow.triangle.branch",
                    category: .git,
                    execute: {
                        EventBus.shared.post(CopyToClipboardEvent(text: branch))
                        EventBus.shared.post(ShowHUDEvent(message: "已复制分支名", tone: .success))
                    }
                ))
        }

        actions.append(contentsOf: [
            SuperPanelAction(
                id: "sp.git-status",
                title: "查看 Git 状态",
                subtitle: "git status",
                icon: "list.bullet.clipboard",
                category: .git,
                execute: {
                    Self.runInTerminal(command: "cd '\(root)' && git status", title: "Git Status")
                }
            ),
            SuperPanelAction(
                id: "sp.git-log",
                title: "查看提交历史",
                subtitle: "git log --oneline -20",
                icon: "clock.arrow.circlepath",
                category: .git,
                execute: {
                    Self.runInTerminal(
                        command: "cd '\(root)' && git log --oneline --graph --decorate -20",
                        title: "Git Log")
                }
            ),
            SuperPanelAction(
                id: "sp.git-diff",
                title: "查看未暂存变更",
                subtitle: "git diff",
                icon: "arrow.left.arrow.right",
                category: .git,
                execute: {
                    Self.runInTerminal(command: "cd '\(root)' && git diff", title: "Git Diff")
                }
            ),
            SuperPanelAction(
                id: "sp.git-pull",
                title: "拉取最新代码",
                subtitle: "git pull",
                icon: "arrow.down.circle",
                category: .git,
                execute: {
                    Self.runInTerminal(command: "cd '\(root)' && git pull", title: "Git Pull")
                }
            ),
            SuperPanelAction(
                id: "sp.git-push",
                title: "推送代码",
                subtitle: "git push",
                icon: "arrow.up.circle",
                category: .git,
                execute: {
                    Self.runInTerminal(command: "cd '\(root)' && git push", title: "Git Push")
                }
            )
        ])

        return actions
    }

    // MARK: - 项目类型特定操作

    private func typeSpecificActions(for context: ProjectContext) -> [SuperPanelAction] {
        let root = context.rootPath

        switch context.type {
        case .xcode:
            return xcodeActions(root: root)
        case .node:
            return nodeActions(root: root)
        case .python:
            return pythonActions(root: root)
        case .rust:
            return rustActions(root: root)
        case .golang:
            return goActions(root: root)
        case .java:
            return javaActions(root: root)
        case .generic:
            return []
        }
    }

    private func xcodeActions(root: String) -> [SuperPanelAction] {
        var actions: [SuperPanelAction] = []

        // 检测构建系统
        let hasPackageSwift = FileManager.default.fileExists(
            atPath: (root as NSString).appendingPathComponent("Package.swift"))
        let hasXcodeproj = !glob(
            pattern: (root as NSString).appendingPathComponent("*.xcodeproj")
        ).isEmpty

        if hasPackageSwift {
            actions.append(contentsOf: [
                SuperPanelAction(
                    id: "sp.swift-build",
                    title: "Swift Build",
                    subtitle: "swift build",
                    icon: "hammer",
                    category: .build,
                    execute: {
                        Self.runInTerminal(command: "cd '\(root)' && swift build", title: "Swift Build")
                    }
                ),
                SuperPanelAction(
                    id: "sp.swift-test",
                    title: "Swift Test",
                    subtitle: "swift test",
                    icon: "testtube.2",
                    category: .build,
                    execute: {
                        Self.runInTerminal(command: "cd '\(root)' && swift test", title: "Swift Test")
                    }
                )
            ])
        }

        if hasXcodeproj {
            actions.append(
                SuperPanelAction(
                    id: "sp.xcode-open",
                    title: "在 Xcode 中打开",
                    subtitle: root,
                    icon: "hammer.circle",
                    category: .quick,
                    execute: {
                        Self.openInApp(path: root, appName: "Xcode")
                    }
                ))
        }

        // 检查 Scripts 目录
        let scriptsDir = (root as NSString).appendingPathComponent("Scripts")
        if FileManager.default.fileExists(atPath: scriptsDir) {
            if let scripts = try? FileManager.default.contentsOfDirectory(atPath: scriptsDir) {
                for script in scripts.prefix(8) where script.hasSuffix(".sh") {
                    let scriptName = (script as NSString).deletingPathExtension
                    actions.append(
                        SuperPanelAction(
                            id: "sp.script-\(scriptName)",
                            title: "运行 \(scriptName)",
                            subtitle: "Scripts/\(script)",
                            icon: "applescript",
                            category: .build,
                            execute: {
                                Self.runInTerminal(
                                    command: "cd '\(root)' && ./Scripts/\(script)",
                                    title: scriptName)
                            }
                        ))
                }
            }
        }

        return actions
    }

    private func nodeActions(root: String) -> [SuperPanelAction] {
        var actions: [SuperPanelAction] = []

        // 读取 package.json 的 scripts
        let packageJsonPath = (root as NSString).appendingPathComponent("package.json")
        if let data = FileManager.default.contents(atPath: packageJsonPath),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let scripts = json["scripts"] as? [String: String]
        {
            let commonScripts = ["dev", "start", "build", "test", "lint", "format", "serve"]
            for name in commonScripts where scripts[name] != nil {
                let manager =
                    fileExists(at: root, name: "pnpm-lock.yaml")
                    ? "pnpm"
                    : fileExists(at: root, name: "yarn.lock") ? "yarn" : "npm"
                actions.append(
                    SuperPanelAction(
                        id: "sp.npm-\(name)",
                        title: "\(manager) run \(name)",
                        subtitle: scripts[name] ?? "",
                        icon: "play.circle",
                        category: .build,
                        execute: {
                            Self.runInTerminal(
                                command: "cd '\(root)' && \(manager) run \(name)",
                                title: "\(manager) \(name)")
                        }
                    ))
            }

            // 添加其他自定义 scripts（不在常见列表中的）
            for (name, cmd) in scripts.sorted(by: { $0.key < $1.key })
            where !commonScripts.contains(name) {
                let manager =
                    fileExists(at: root, name: "pnpm-lock.yaml")
                    ? "pnpm"
                    : fileExists(at: root, name: "yarn.lock") ? "yarn" : "npm"
                actions.append(
                    SuperPanelAction(
                        id: "sp.npm-\(name)",
                        title: "\(manager) run \(name)",
                        subtitle: cmd,
                        icon: "play.circle",
                        category: .build,
                        execute: {
                            Self.runInTerminal(
                                command: "cd '\(root)' && \(manager) run \(name)",
                                title: "\(manager) \(name)")
                        }
                    ))
            }
        }

        actions.append(
            SuperPanelAction(
                id: "sp.npm-install",
                title: "安装依赖",
                subtitle: "npm install",
                icon: "arrow.down.app",
                category: .build,
                execute: {
                    let manager =
                        Self.fileExistsStatic(at: root, name: "pnpm-lock.yaml")
                        ? "pnpm"
                        : Self.fileExistsStatic(at: root, name: "yarn.lock") ? "yarn" : "npm"
                    Self.runInTerminal(
                        command: "cd '\(root)' && \(manager) install",
                        title: "Install Dependencies")
                }
            ))

        return actions
    }

    private func pythonActions(root: String) -> [SuperPanelAction] {
        [
            SuperPanelAction(
                id: "sp.python-run",
                title: "运行主脚本",
                subtitle: "python main.py",
                icon: "play.circle",
                category: .build,
                execute: {
                    let main =
                        Self.fileExistsStatic(at: root, name: "main.py")
                        ? "main.py"
                        : Self.fileExistsStatic(at: root, name: "app.py") ? "app.py" : ""
                    if !main.isEmpty {
                        Self.runInTerminal(
                            command: "cd '\(root)' && python3 \(main)", title: "Python Run")
                    }
                }
            ),
            SuperPanelAction(
                id: "sp.python-test",
                title: "运行测试",
                subtitle: "pytest",
                icon: "testtube.2",
                category: .build,
                execute: {
                    Self.runInTerminal(command: "cd '\(root)' && python3 -m pytest", title: "Pytest")
                }
            ),
            SuperPanelAction(
                id: "sp.pip-install",
                title: "安装依赖",
                subtitle: "pip install -r requirements.txt",
                icon: "arrow.down.app",
                category: .build,
                execute: {
                    Self.runInTerminal(
                        command: "cd '\(root)' && pip3 install -r requirements.txt",
                        title: "Pip Install")
                }
            )
        ]
    }

    private func rustActions(root: String) -> [SuperPanelAction] {
        [
            SuperPanelAction(
                id: "sp.cargo-build",
                title: "Cargo Build",
                subtitle: "cargo build",
                icon: "hammer",
                category: .build,
                execute: {
                    Self.runInTerminal(command: "cd '\(root)' && cargo build", title: "Cargo Build")
                }
            ),
            SuperPanelAction(
                id: "sp.cargo-run",
                title: "Cargo Run",
                subtitle: "cargo run",
                icon: "play.circle",
                category: .build,
                execute: {
                    Self.runInTerminal(command: "cd '\(root)' && cargo run", title: "Cargo Run")
                }
            ),
            SuperPanelAction(
                id: "sp.cargo-test",
                title: "Cargo Test",
                subtitle: "cargo test",
                icon: "testtube.2",
                category: .build,
                execute: {
                    Self.runInTerminal(command: "cd '\(root)' && cargo test", title: "Cargo Test")
                }
            )
        ]
    }

    private func goActions(root: String) -> [SuperPanelAction] {
        [
            SuperPanelAction(
                id: "sp.go-build",
                title: "Go Build",
                subtitle: "go build ./...",
                icon: "hammer",
                category: .build,
                execute: {
                    Self.runInTerminal(
                        command: "cd '\(root)' && go build ./...", title: "Go Build")
                }
            ),
            SuperPanelAction(
                id: "sp.go-test",
                title: "Go Test",
                subtitle: "go test ./...",
                icon: "testtube.2",
                category: .build,
                execute: {
                    Self.runInTerminal(command: "cd '\(root)' && go test ./...", title: "Go Test")
                }
            ),
            SuperPanelAction(
                id: "sp.go-run",
                title: "Go Run",
                subtitle: "go run .",
                icon: "play.circle",
                category: .build,
                execute: {
                    Self.runInTerminal(command: "cd '\(root)' && go run .", title: "Go Run")
                }
            )
        ]
    }

    private func javaActions(root: String) -> [SuperPanelAction] {
        let hasGradle = FileManager.default.fileExists(
            atPath: (root as NSString).appendingPathComponent("build.gradle"))
        let hasMaven = FileManager.default.fileExists(
            atPath: (root as NSString).appendingPathComponent("pom.xml"))

        var actions: [SuperPanelAction] = []

        if hasGradle {
            actions.append(contentsOf: [
                SuperPanelAction(
                    id: "sp.gradle-build",
                    title: "Gradle Build",
                    subtitle: "./gradlew build",
                    icon: "hammer",
                    category: .build,
                    execute: {
                        Self.runInTerminal(
                            command: "cd '\(root)' && ./gradlew build", title: "Gradle Build")
                    }
                ),
                SuperPanelAction(
                    id: "sp.gradle-test",
                    title: "Gradle Test",
                    subtitle: "./gradlew test",
                    icon: "testtube.2",
                    category: .build,
                    execute: {
                        Self.runInTerminal(
                            command: "cd '\(root)' && ./gradlew test", title: "Gradle Test")
                    }
                )
            ])
        }

        if hasMaven {
            actions.append(contentsOf: [
                SuperPanelAction(
                    id: "sp.mvn-build",
                    title: "Maven Build",
                    subtitle: "mvn package",
                    icon: "hammer",
                    category: .build,
                    execute: {
                        Self.runInTerminal(
                            command: "cd '\(root)' && mvn package", title: "Maven Build")
                    }
                ),
                SuperPanelAction(
                    id: "sp.mvn-test",
                    title: "Maven Test",
                    subtitle: "mvn test",
                    icon: "testtube.2",
                    category: .build,
                    execute: {
                        Self.runInTerminal(
                            command: "cd '\(root)' && mvn test", title: "Maven Test")
                    }
                )
            ])
        }

        return actions
    }

    // MARK: - 快速导航

    private func quickNavigationActions(for context: ProjectContext) -> [SuperPanelAction] {
        let root = context.rootPath
        var actions: [SuperPanelAction] = []

        // 常见导航目标
        let navTargets: [(String, String, String)] = [
            ("README.md", "打开 README", "doc.text"),
            (".env", "打开环境变量文件", "lock.shield"),
            ("Makefile", "打开 Makefile", "doc.plaintext"),
            ("Dockerfile", "打开 Dockerfile", "shippingbox"),
            ("docker-compose.yml", "打开 Docker Compose", "shippingbox"),
            (".github", "打开 GitHub 配置", "arrow.triangle.branch")
        ]

        for (file, title, icon) in navTargets {
            let path = (root as NSString).appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: path) {
                actions.append(
                    SuperPanelAction(
                        id: "sp.nav-\(file.replacingOccurrences(of: ".", with: "-"))",
                        title: title,
                        subtitle: file,
                        icon: icon,
                        category: .file,
                        execute: {
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                            EventBus.shared.post(HidePaletteEvent())
                        }
                    ))
            }
        }

        return actions
    }

    // MARK: - 辅助方法

    private func fileExists(at root: String, name: String) -> Bool {
        FileManager.default.fileExists(
            atPath: (root as NSString).appendingPathComponent(name))
    }

    private static func fileExistsStatic(at root: String, name: String) -> Bool {
        FileManager.default.fileExists(
            atPath: (root as NSString).appendingPathComponent(name))
    }

    private func glob(pattern: String) -> [String] {
        let dir = (pattern as NSString).deletingLastPathComponent
        let name = (pattern as NSString).lastPathComponent
        let suffix = String(name.dropFirst())
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir)
        else { return [] }
        return contents.filter { $0.hasSuffix(suffix) }
    }

    // MARK: - 系统操作

    /// 在终端中打开目录
    private static func openInTerminal(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
        EventBus.shared.post(HidePaletteEvent())
    }

    /// 在终端中运行命令
    private static func runInTerminal(command: String, title: String) {
        // 通过 AppleScript 在终端里跑命令
        let escaped = command.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
            tell application "Terminal"
                activate
                do script "\(escaped)"
            end tell
            """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
        EventBus.shared.post(HidePaletteEvent())
    }

    /// 在指定应用中打开路径
    private static func openInApp(path: String, appName: String) {
        let url = URL(fileURLWithPath: path)
        let config = NSWorkspace.OpenConfiguration()
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "") {
            // 按名字找应用
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
        } else {
            // 回退：用 open -a 命令
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-a", appName, path]
            try? task.run()
        }
        EventBus.shared.post(HidePaletteEvent())
    }
}
