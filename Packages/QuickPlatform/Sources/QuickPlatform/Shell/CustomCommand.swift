// CustomCommand.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 用户自定义 Shell 命令
public struct CustomCommand: Codable, Hashable, Identifiable, Sendable {

    public let id: UUID
    public var name: String
    public var command: String
    public var isEnabled: Bool
    public var alias: String?
    public var workingDirectory: String?
    public var showsOutput: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        command: String,
        isEnabled: Bool = true,
        alias: String? = nil,
        workingDirectory: String? = nil,
        showsOutput: Bool = true
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.isEnabled = isEnabled
        self.alias = alias
        self.workingDirectory = workingDirectory
        self.showsOutput = showsOutput
    }
}
