// AppDirectoryWatcher.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore

/// 应用程序目录实时文件系统变动监听器
///
/// 基于 `DispatchSourceFileSystemObject` 监听应用搜索范围（如 `/Applications`、`~/Applications`）
/// 的目录内容变动（创建、删除、重命名、移动等）。
/// 发生变动时内置防抖机制（默认 1.2 秒），待文件写入/安装稳定后再触发外部回调，
/// 避免在拷贝大体积 App 时反复无效重扫。
public final class AppDirectoryWatcher: @unchecked Sendable {

    private let log = QuickLog.platform

    /// 监听触发回调（主线程）
    private let onChange: @MainActor @Sendable () -> Void

    /// 防抖等待时长
    private let debounceInterval: TimeInterval

    /// 专用后台分发队列
    private let queue = DispatchQueue(label: "quick.platform.app-directory-watcher", qos: .utility)

    /// 正在监听的目录路径映射到 DispatchSource 及其文件描述符
    private var sources: [String: (source: any DispatchSourceFileSystemObject, fd: Int32)] = [:]

    /// 防抖工作项
    private var debounceWorkItem: DispatchWorkItem?

    /// 锁保护内部状态
    private let lock = NSLock()

    /// 初始化监听器
    /// - Parameters:
    ///   - paths: 要监听的目录绝对路径列表
    ///   - debounceInterval: 防抖间隔（秒），默认 1.2 秒
    ///   - onChange: 目录变动且防抖结束后的回调
    public init(
        paths: [String] = [],
        debounceInterval: TimeInterval = 1.2,
        onChange: @escaping @MainActor @Sendable () -> Void
    ) {
        self.debounceInterval = debounceInterval
        self.onChange = onChange
        if !paths.isEmpty {
            update(paths: paths)
        }
    }

    deinit {
        stop()
    }

    /// 更新监听的目录列表（会停止不再需要的目录，启动新增的目录）
    public func update(paths: [String]) {
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }

            let targetPaths = Set(paths.filter { FileManager.default.fileExists(atPath: $0) })
            let currentPaths = Set(self.sources.keys)

            // 移除不再监听的
            for path in currentPaths.subtracting(targetPaths) {
                if let entry = self.sources.removeValue(forKey: path) {
                    entry.source.cancel()
                    self.log.debug("停止监听应用目录：\(path, privacy: .public)")
                }
            }

            // 添加新目录
            for path in targetPaths.subtracting(currentPaths) {
                self.watchDirectory(at: path)
            }
        }
    }

    /// 停止所有监听
    public func stop() {
        queue.sync {
            lock.lock()
            defer { lock.unlock() }

            debounceWorkItem?.cancel()
            debounceWorkItem = nil

            for (path, entry) in sources {
                entry.source.cancel()
                log.debug("停止监听应用目录：\(path, privacy: .public)")
            }
            sources.removeAll()
        }
    }

    // MARK: - 私有方法

    private func watchDirectory(at path: String) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            log.debug("无法以 O_EVTONLY 打开应用目录：\(path, privacy: .public)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.handleEvent(for: path)
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        sources[path] = (source: source, fd: fd)
        log.debug("开始监听应用目录：\(path, privacy: .public)")
    }

    private func handleEvent(for path: String) {
        log.debug("检测到应用目录变动：\(path, privacy: .public)")

        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.log.notice("应用目录变动防抖完成，触发索引刷新")
            Task { @MainActor [onChange = self.onChange] in
                onChange()
            }
        }
        debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
}
