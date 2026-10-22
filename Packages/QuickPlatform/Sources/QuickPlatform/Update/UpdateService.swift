// UpdateService.swift
// Quick — 原生 macOS 效率启动器
// @author ixxxxoooo

import Foundation
import QuickCore

/// 自动更新失败的原因
public enum UpdateError: Error, LocalizedError, Sendable {
    case notReleaseBuild
    case badResponse
    case mountFailed
    case appNotFound
    case verifyFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notReleaseBuild: "开发渠道（Quick Dev）不支持自动更新"
        case .badResponse: "无法获取最新版本信息"
        case .mountFailed: "无法挂载更新镜像"
        case .appNotFound: "更新镜像里没有 Quick.app"
        case .verifyFailed(let why): "新版本签名校验失败：\(why)"
        }
    }
}

/// 基于 GitHub Releases 的自更新服务（不依赖 Sparkle）
///
/// 流程：查询 `releases/latest` → 下载 DMG → 挂载并拷出 Quick.app → 校验签名 →
/// 起一个脱离的 shell 等本进程退出后替换 bundle 并重新打开。
/// 新旧包都由同一张证书「Quick」签名，所以替换后 TCC 授权不丢。
public struct UpdateService: Sendable {

    private static let latestURL = URL(string: "https://api.github.com/repos/ixxxxoooo/Quick/releases/latest")!
    private static let releaseBundleID = "com.ixxxxoooo.quick"
    private let log = QuickLog.platform

    public init() {}

    /// 当前运行的版本号
    public static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// 查询是否有更新
    /// - Returns: 有更新时返回发布信息，已是最新返回 nil
    /// - Throws: 网络或解析失败
    public func checkForUpdate() async throws -> UpdateRelease? {
        var request = URLRequest(url: Self.latestURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
            let release = UpdateRelease.parse(data)
        else { throw UpdateError.badResponse }
        let newer = UpdateRelease.isNewer(release.version, than: Self.currentVersion)
        log.notice("检查更新：当前 \(Self.currentVersion, privacy: .public)，最新 \(release.version, privacy: .public)")
        return newer ? release : nil
    }

    /// 下载并安装更新；成功后脱离的 shell 会在本进程退出后完成替换并重启
    ///
    /// 调用方在本方法返回后应调用 `NSApp.terminate`。
    /// - Parameter release: 要安装的版本
    /// - Throws: 下载、挂载、签名校验失败
    public func prepareInstall(_ release: UpdateRelease) async throws {
        guard Bundle.main.bundleIdentifier == Self.releaseBundleID else { throw UpdateError.notReleaseBuild }
        let bundleURL = Bundle.main.bundleURL
        let (tmpDMG, _) = try await URLSession.shared.download(from: release.downloadURL)
        let staging = bundleURL.deletingLastPathComponent()
            .appendingPathComponent(".Quick-update-\(UUID().uuidString)", isDirectory: true)
        let dmg = FileManager.default.temporaryDirectory.appendingPathComponent("Quick-update.dmg")
        try? FileManager.default.removeItem(at: dmg)
        try FileManager.default.moveItem(at: tmpDMG, to: dmg)
        let stagedApp = try await Task.detached { try Self.extract(dmg: dmg, to: staging) }.value
        try? FileManager.default.removeItem(at: dmg)
        try Self.spawnInstaller(stagedApp: stagedApp, staging: staging, target: bundleURL)
        log.notice("更新 \(release.version, privacy: .public) 已就绪，等待退出后替换")
    }

    /// 挂载 DMG，把 Quick.app 拷到 staging 并校验签名
    nonisolated private static func extract(dmg: URL, to staging: URL) throws -> URL {
        let mount = FileManager.default.temporaryDirectory
            .appendingPathComponent("quick-update-mount-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        guard run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noverify",
                                      "-mountpoint", mount.path, dmg.path]) == 0
        else { throw UpdateError.mountFailed }
        defer {
            _ = run("/usr/bin/hdiutil", ["detach", "-force", mount.path])
            try? FileManager.default.removeItem(at: mount)
        }
        let source = mount.appendingPathComponent("Quick.app")
        guard FileManager.default.fileExists(atPath: source.path) else { throw UpdateError.appNotFound }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let staged = staging.appendingPathComponent("Quick.app")
        guard run("/usr/bin/ditto", [source.path, staged.path]) == 0 else {
            throw UpdateError.verifyFailed("拷贝失败")
        }
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path]) == 0 else {
            try? FileManager.default.removeItem(at: staging)
            throw UpdateError.verifyFailed("codesign --verify 未通过")
        }
        return staged
    }

    /// 起脱离的 shell：等本进程退出 → 替换 bundle → 解隔离 → 重新打开
    private static func spawnInstaller(stagedApp: URL, staging: URL, target: URL) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
            while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
            rm -rf "$3" && mv "$2" "$3" && /usr/bin/xattr -dr com.apple.quarantine "$3"
            rm -rf "$4"
            exec /usr/bin/open -n "$3"
            """
        let waiter = Process()
        waiter.executableURL = URL(fileURLWithPath: "/bin/sh")
        waiter.arguments = ["-c", script, "quick-update", String(pid), stagedApp.path, target.path, staging.path]
        try waiter.run()
    }

    /// 同步执行命令并返回退出码（只在 detached 任务里调用）
    nonisolated private static func run(_ path: String, _ args: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
