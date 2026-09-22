// CalcHistoryEntry.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 一条计算历史
///
/// 只保存**展示所需的成品**：表达式原文与格式化后的结果。之所以不在展示时用
/// `CalcEngine` 重算，是因为格式化选项（小数位数、千分位）随时会被设置页改掉 ——
/// 重算会让「当时算出来的 0.67」在改设置后变成 0.666667，历史就不再是历史。
struct CalcHistoryEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let expression: String
    let result: String
    let timestamp: Date
}
