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

    /// 是否用交互式 shell（`zsh -ilc`）执行
    ///
    /// `.zshrc` 只在交互式 shell 里被 source，所以别名与写在那里的 PATH 段（nvm、pyenv）
    /// 在默认的 `-lc` 下都不存在。打开它就是拿每次执行多付一份配置加载时间，换回「跟我在
    /// 终端里敲的一模一样」—— 用户自己决定值不值。
    public var loadsShellEnvironment: Bool

    public var alias: String?
    public var workingDirectory: String?
    public var showsOutput: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        command: String,
        isEnabled: Bool = true,
        loadsShellEnvironment: Bool = false,
        alias: String? = nil,
        workingDirectory: String? = nil,
        showsOutput: Bool = true
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.isEnabled = isEnabled
        self.loadsShellEnvironment = loadsShellEnvironment
        self.alias = alias
        self.workingDirectory = workingDirectory
        self.showsOutput = showsOutput
    }

    // MARK: - 解码

    // 手写解码，不用合成的那个
    //
    // 合成的解码器会在**缺任何一个 key** 时整条失败，而这里的调用点（`LauncherPlugin`、
    // `AppCore`）用的是 `try?`：一条命令读不出来，`[CustomCommand]` 整个数组就变成 nil，
    // 用户存过的命令会**全部**从面板里消失，且没有任何日志。加一个字段就会踩到这件事，
    // 所以新字段一律 `decodeIfPresent`，并且给回默认值。
    private enum CodingKeys: String, CodingKey {
        case id, name, command, isEnabled, loadsShellEnvironment, alias, workingDirectory, showsOutput
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        command = try container.decode(String.self, forKey: .command)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        loadsShellEnvironment =
            try container.decodeIfPresent(Bool.self, forKey: .loadsShellEnvironment) ?? false
        alias = try container.decodeIfPresent(String.self, forKey: .alias)
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        showsOutput = try container.decodeIfPresent(Bool.self, forKey: .showsOutput) ?? true
    }
}
