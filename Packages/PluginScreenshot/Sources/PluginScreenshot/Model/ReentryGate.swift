// ReentryGate.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

/// 防重入门：一次只放一个「正在进行」的操作进来
///
/// 用于有多处 `await` 的异步流程 —— 挂起期间状态还没落地，普通的「是否已在展示」判断会被连按穿透。
struct ReentryGate {
    private(set) var isBusy = false

    /// 尝试进入；已有人在里面时返回 `false`
    mutating func tryEnter() -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        return true
    }

    /// 离开
    mutating func leave() {
        isBusy = false
    }
}
