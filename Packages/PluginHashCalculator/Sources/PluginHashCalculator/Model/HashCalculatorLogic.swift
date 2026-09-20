// HashCalculatorLogic.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import CryptoKit
import Foundation

/// 哈希计算的纯逻辑
///
/// 视图只负责持有 `@State`，摘要算法集中在这里 ——
/// `Model/` 里禁止出现任何 UI 框架，因此这块逻辑能被测试独立验证。
enum HashCalculatorLogic {

    /// 支持的摘要算法
    ///
    /// rawValue 直接就是界面上显示的算法名；`allCases` 的顺序就是结果列表的顺序。
    enum Algorithm: String, CaseIterable {
        case md5 = "MD5"
        case sha1 = "SHA1"
        case sha256 = "SHA256"
        case sha512 = "SHA512"
    }

    /// 按 UTF-8 字节计算单个摘要
    ///
    /// 返回小写十六进制 —— 这是各家哈希工具的通行写法，也便于直接比对。
    /// 空串的摘要在数学上有定义（空输入的哈希），所以这里不做「空输入」特殊处理；
    /// 「还没输入」的语义留给 `digests(of:)`。
    static func digest(_ input: String, algorithm: Algorithm) -> String {
        let data = Data(input.utf8)
        switch algorithm {
        case .md5:
            return Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case .sha1:
            return Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case .sha256:
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case .sha512:
            return SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }

    /// 一次算出全部算法的摘要
    ///
    /// 空输入返回空列表：界面此时显示的是「输入文本后自动计算」的空状态，
    /// 而不是四个空输入的摘要 —— 后者在用户按下复制时会得到一堆没有意义的值。
    static func digests(of input: String) -> [(algorithm: Algorithm, value: String)] {
        guard !input.isEmpty else { return [] }
        return Algorithm.allCases.map { algorithm in
            (algorithm, digest(input, algorithm: algorithm))
        }
    }
}
