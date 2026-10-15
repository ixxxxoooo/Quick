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
        hexString(of: Data(input.utf8), algorithm: algorithm)
    }

    /// 按 UTF-8 字节计算 HMAC，返回小写十六进制
    ///
    /// 密钥为空时 HMAC 仍有定义（等价于空密钥），但界面上「没填密钥」的意思是不用 HMAC，
    /// 所以那个分支由 `digests(of:hmacKey:)` 处理，不在这里。
    static func hmac(_ input: String, key: String, algorithm: Algorithm) -> String {
        let data = Data(input.utf8)
        let symmetricKey = SymmetricKey(data: Data(key.utf8))
        switch algorithm {
        case .md5:
            return Self.hex(HMAC<Insecure.MD5>.authenticationCode(for: data, using: symmetricKey))
        case .sha1:
            return Self.hex(HMAC<Insecure.SHA1>.authenticationCode(for: data, using: symmetricKey))
        case .sha256:
            return Self.hex(HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey))
        case .sha512:
            return Self.hex(HMAC<SHA512>.authenticationCode(for: data, using: symmetricKey))
        }
    }

    /// 字节序列转小写十六进制
    private static func hex(_ bytes: some Sequence<UInt8>) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func hexString(of data: Data, algorithm: Algorithm) -> String {
        switch algorithm {
        case .md5: return hex(Insecure.MD5.hash(data: data))
        case .sha1: return hex(Insecure.SHA1.hash(data: data))
        case .sha256: return hex(SHA256.hash(data: data))
        case .sha512: return hex(SHA512.hash(data: data))
        }
    }

    /// 一次算出全部算法的摘要
    ///
    /// 空输入返回空列表：界面此时显示的是「输入文本后自动计算」的空状态，
    /// 而不是四个空输入的摘要 —— 后者在用户按下复制时会得到一堆没有意义的值。
    ///
    /// - Parameter hmacKey: 非空时改算 HMAC；空串表示「不用 HMAC」，走普通摘要
    static func digests(
        of input: String, hmacKey: String = ""
    ) -> [(algorithm: Algorithm, value: String)] {
        guard !input.isEmpty else { return [] }
        return Algorithm.allCases.map { algorithm in
            hmacKey.isEmpty
                ? (algorithm, digest(input, algorithm: algorithm))
                : (algorithm, hmac(input, key: hmacKey, algorithm: algorithm))
        }
    }
    // MARK: - 展示与自动复制

    /// 按设置的大小写返回十六进制：存储与计算始终是小写，只在展示 / 复制那一刻转换，
    /// 这样切换设置不需要重新算一遍
    static func display(_ value: String, uppercase: Bool) -> String {
        uppercase ? value.uppercased() : value
    }

    /// 「计算后自动复制」复制哪一条：SHA256（最通用的校验值），没有结果时为空
    static func autoCopyValue(
        in results: [(algorithm: Algorithm, value: String)], uppercase: Bool
    ) -> String? {
        results.first { $0.algorithm == .sha256 }.map { display($0.value, uppercase: uppercase) }
    }

    /// 输入停手多久之后才自动复制：边打边复制会把每个中间状态的哈希都灌进剪贴板历史
    static let autoCopyDelay: Duration = .milliseconds(800)
}
