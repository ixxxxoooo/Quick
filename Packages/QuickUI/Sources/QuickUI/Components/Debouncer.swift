// Debouncer.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 输入驱动的「防抖 + 后台计算」
///
/// 开发者工具（哈希、JSON、Base64……）以前在 `onChange(of: input)` 里**同步**算，
/// 粘一份几 MB 的文本会让主线程卡住、输入框掉帧。这里按输入体量分两条路：
///
/// - **小输入（≤ `inlineThreshold` 字节）**：同步算、立即回写。打字手感不变，也没有任何延迟。
/// - **大输入**：先等 `delay` 内没有新输入（防抖），再把计算丢到后台，算完回主线程写回；
///   期间又来了新输入就丢弃旧结果，保证界面上永远是最新输入对应的结果。
///
/// 计算函数必须是纯的、只捕获 `Sendable` 的值（把要用的输入与选项先拷成局部常量）。
@MainActor
public final class Debouncer {

    /// 大输入的等待时长
    public let delay: Duration
    /// 不超过它就同步算（字节）
    public let inlineThreshold: Int

    private var task: Task<Void, Never>?
    /// 代数：只有最新一次调度的结果才允许落地
    private var generation = 0

    public init(delay: Duration = .milliseconds(150), inlineThreshold: Int = 4096) {
        self.delay = delay
        self.inlineThreshold = inlineThreshold
    }

    /// 安排一次计算
    ///
    /// - Parameters:
    ///   - weight: 输入体量（通常是 `input.utf8.count`），决定走同步还是后台
    ///   - work: 纯计算
    ///   - apply: 回主线程写回结果
    public func schedule<Value: Sendable>(
        weight: Int,
        work: @escaping @Sendable () -> Value,
        apply: @escaping @MainActor (Value) -> Void
    ) {
        task?.cancel()
        generation += 1
        let current = generation

        if weight <= inlineThreshold {
            task = nil
            apply(work())
            return
        }

        let delay = delay
        task = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            let value = await Task.detached(priority: .userInitiated, operation: work).value
            guard !Task.isCancelled, let self, self.generation == current else { return }
            apply(value)
        }
    }

    /// 放弃尚未落地的计算（视图消失时调用）
    public func cancel() {
        task?.cancel()
        task = nil
        generation += 1
    }
}
