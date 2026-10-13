// CurrencyRates.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 一份汇率快照（以 USD 为基准）
///
/// 纯数据：怎么拿到它（网络、缓存）在 Service 层；这里只负责换算与解析，
/// 所以任何汇率都能用固定样本测试，不依赖当天行情。
nonisolated struct CurrencyRates: Codable, Equatable, Sendable {

    /// 1 USD 兑换多少该币种；键为大写三位代码
    let perUSD: [String: Double]
    /// 数据源给出的更新时间
    let updatedAt: Date

    /// 币种别名 → 代码（别名一律小写）
    private static let aliases: [String: String] = [
        "美元": "USD", "美金": "USD", "刀": "USD",
        "人民币": "CNY", "rmb": "CNY", "元": "CNY", "块": "CNY",
        "欧元": "EUR", "日元": "JPY", "日币": "JPY", "英镑": "GBP",
        "港币": "HKD", "港元": "HKD", "韩元": "KRW", "澳元": "AUD", "澳币": "AUD",
        "加元": "CAD", "加币": "CAD", "新台币": "TWD", "台币": "TWD",
        "新加坡元": "SGD", "新币": "SGD", "瑞士法郎": "CHF", "卢布": "RUB",
        "泰铢": "THB", "印度卢比": "INR", "卢比": "INR", "澳门元": "MOP",
    ]

    /// 把用户写的币种名规整成代码；不是币种返回 `nil`
    func code(for name: String) -> String? {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        if let code = Self.aliases[key], perUSD[code] != nil { return code }
        let upper = key.uppercased()
        return upper.count == 3 && perUSD[upper] != nil ? upper : nil
    }

    /// 换算；任一币种未知返回 `nil`
    func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard let source = code(for: from), let target = code(for: to),
            let sourceRate = perUSD[source], let targetRate = perUSD[target], sourceRate > 0
        else { return nil }
        return amount / sourceRate * targetRate
    }

    /// 解析 `open.er-api.com` 的返回
    ///
    /// 只收 `result == "success"` 且有合理数量币种的响应：
    /// 被劫持或限流时返回的是别的 JSON，拿来当汇率会算出离谱的结果。
    static func parse(_ data: Data) -> CurrencyRates? {
        struct Payload: Decodable {
            let result: String
            let time_last_update_unix: TimeInterval?
            let rates: [String: Double]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
            payload.result == "success", payload.rates.count >= 20, payload.rates["USD"] == 1
        else { return nil }
        let valid = payload.rates.filter { $0.value > 0 && $0.value.isFinite }
        return CurrencyRates(
            perUSD: valid,
            updatedAt: payload.time_last_update_unix.map { Date(timeIntervalSince1970: $0) } ?? Date())
    }
}
