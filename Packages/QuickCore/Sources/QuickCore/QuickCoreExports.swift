// QuickCoreExports.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

// 统一导出，使用者只需 `import QuickCore`
//
// `os` 一并导出，是因为 `QuickLog` 的公开 API 返回 `Logger` / `OSSignposter`：
// 调用方写 `private let log = QuickLog.plugin(X.id)` 时需要能看到这些类型，
// 否则编译器会报「cannot use struct 'Logger' in a property declaration」。
// 让每个插件作者都记得额外 `import os` 是个没必要的坑。
@_exported import os
