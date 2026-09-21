// ProjectContext.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 当前项目上下文
///
/// 超级面板的核心数据：通过前台应用检测当前项目的路径和类型，
/// 据此提供上下文相关的快速操作。
struct ProjectContext: Sendable, Equatable {

    /// 项目根目录
    let rootPath: String

    /// 项目名称（目录名）
    let name: String

    /// 项目类型
    let type: ProjectType

    /// 是否是 Git 仓库
    let isGitRepo: Bool

    /// Git 当前分支名（如果是 Git 仓库）
    let gitBranch: String?

    /// 来源应用的 Bundle ID
    let sourceBundleID: String?

    /// 项目类型枚举
    enum ProjectType: String, Sendable {
        /// Swift / Xcode 项目
        case xcode
        /// Node.js 项目
        case node
        /// Python 项目
        case python
        /// Rust 项目
        case rust
        /// Go 项目
        case golang
        /// Java / Gradle / Maven
        case java
        /// 通用（有 Git 但无法识别具体类型）
        case generic

        var icon: String {
            switch self {
            case .xcode: "hammer"
            case .node: "shippingbox"
            case .python: "curlybraces"
            case .rust: "gearshape.2"
            case .golang: "server.rack"
            case .java: "cup.and.saucer"
            case .generic: "folder"
            }
        }

        var displayName: String {
            switch self {
            case .xcode: "Xcode"
            case .node: "Node.js"
            case .python: "Python"
            case .rust: "Rust"
            case .golang: "Go"
            case .java: "Java"
            case .generic: "项目"
            }
        }
    }
}

/// 超级面板的一条快速操作
struct SuperPanelAction: Identifiable, Sendable {

    let id: String
    let title: String
    let subtitle: String
    let icon: String

    /// 操作类别
    let category: Category

    /// 执行闭包
    let execute: @Sendable @MainActor () -> Void

    enum Category: String, Sendable, CaseIterable {
        case git = "Git"
        case build = "构建"
        case file = "文件"
        case terminal = "终端"
        case quick = "快捷"
    }
}
