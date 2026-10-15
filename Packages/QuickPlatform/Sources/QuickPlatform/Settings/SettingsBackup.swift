// SettingsBackup.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 设置备份的导出与导入（纯逻辑，不碰真实 UserDefaults）
///
/// 文件格式是 XML plist：`{ format, version, exportedAt, values }`。选 plist 而不是 JSON，
/// 是因为 `UserDefaults` 里本来就是 plist 类型，`Bool` / `Int` / `Double` / `Data` / `Date`
/// 往返都不丢类型（JSON 会把 `5.0` 读回 `Int`、把 `Data` 直接丢掉）。
///
/// 安全边界：
/// - **导出**只带 Quick 自己的键，系统与框架写进同一个域的键（`NS*`、`Apple*` 等）一律不带。
///   密钥类数据在钥匙串里，本来就不在这里。
/// - **导入**同样按这条规则过滤，**不信任文件内容**：一个被篡改的备份不能借导入去改
///   系统键或写出超大的值。
public enum SettingsBackup {

    /// 文件格式标识
    public static let formatIdentifier = "quick-settings"

    /// 当前格式版本。读到更高版本一律拒绝，而不是猜着解析
    public static let currentVersion = 1

    /// 备份文件体积上限：正常设置只有几十 KB，几 MB 以上基本是选错了文件
    public static let maximumFileSize = 5 * 1024 * 1024

    /// 单个键名的长度上限
    public static let maximumKeyLength = 200

    /// 不导出也不导入的键前缀
    ///
    /// 窗口位置（`NSWindow Frame …`）、分栏宽度、语言与区域设置都属于「这台机器」而不是「这个用户的偏好」。
    public static let excludedKeyPrefixes = [
        "NS", "Apple", "com.apple.", "WebKit", "NavPanel", "Sparkle"
    ]

    /// 导入失败的原因
    public enum Failure: Error, Equatable, LocalizedError {
        case tooLarge
        case notABackup
        case unsupportedVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .tooLarge: "文件过大，不像是 Quick 的设置备份"
            case .notABackup: "这不是 Quick 的设置备份文件"
            case .unsupportedVersion(let version):
                "备份来自更新版本的 Quick（格式 v\(version)），请先升级后再导入"
            }
        }
    }

    /// 一次导入的解析结果
    public struct ImportPlan: Sendable {
        /// 通过校验、可以写入的键值（plist 类型，调用方负责写进 `UserDefaults`）
        public let values: [String: PropertyListValue]
        /// 因键不合规被丢弃的条目数
        public let skipped: Int
        /// 备份文件里记录的导出时间
        public let exportedAt: Date?
    }

    /// 一个键是否可以出现在备份里
    public static func isPortable(key: String) -> Bool {
        guard !key.isEmpty, key.count <= maximumKeyLength else { return false }
        return !excludedKeyPrefixes.contains { key.hasPrefix($0) }
    }

    // MARK: - 导出

    /// 把一份偏好域序列化成备份文件内容
    ///
    /// - Parameters:
    ///   - domain: 应用的持久化偏好域（`UserDefaults.persistentDomain(forName:)`）
    ///   - exportedAt: 导出时间。由调用方注入，模型层不读系统时钟
    public static func export(domain: [String: Any], exportedAt: Date) throws -> Data {
        let values = domain.filter { isPortable(key: $0.key) }
        let document: [String: Any] = [
            "format": formatIdentifier,
            "version": currentVersion,
            "exportedAt": exportedAt,
            "values": values
        ]
        return try PropertyListSerialization.data(
            fromPropertyList: document, format: .xml, options: 0)
    }

    // MARK: - 导入

    /// 解析并校验一份备份
    ///
    /// 只做解析与过滤，**不写入任何存储** —— 写入由调用方决定，也方便测试。
    public static func parse(_ data: Data) throws -> ImportPlan {
        guard data.count <= maximumFileSize else { throw Failure.tooLarge }
        guard
            let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let document = object as? [String: Any],
            document["format"] as? String == formatIdentifier,
            let rawValues = document["values"] as? [String: Any]
        else { throw Failure.notABackup }

        let version = document["version"] as? Int ?? 0
        guard version >= 1 else { throw Failure.notABackup }
        guard version <= currentVersion else { throw Failure.unsupportedVersion(version) }

        var accepted: [String: PropertyListValue] = [:]
        var skipped = 0
        for (key, value) in rawValues {
            if isPortable(key: key), let wrapped = PropertyListValue(value) {
                accepted[key] = wrapped
            } else {
                skipped += 1
            }
        }
        return ImportPlan(
            values: accepted, skipped: skipped, exportedAt: document["exportedAt"] as? Date)
    }
}

/// 一个确认是 plist 类型的值
///
/// 把 `Any` 收窄成 `Sendable` 的枚举，既能跨 actor 传递（Swift 6 严格并发），
/// 又在入口处挡掉非 plist 类型。
public enum PropertyListValue: Sendable, Equatable {
    case bool(Bool)
    case integer(Int)
    case double(Double)
    case string(String)
    case data(Data)
    case date(Date)
    case array([PropertyListValue])
    case dictionary([String: PropertyListValue])

    /// 从 plist 反序列化出来的任意值构造；类型不在白名单里时返回 nil
    init?(_ value: Any) {
        switch value {
        case let number as NSNumber:
            // `NSNumber` 同时承载 Bool 与数值，必须先按 CFBoolean 区分，
            // 否则 `true` 会被当成整数 1 写回去
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if CFNumberIsFloatType(number) {
                self = .double(number.doubleValue)
            } else {
                self = .integer(number.intValue)
            }
        case let string as String: self = .string(string)
        case let data as Data: self = .data(data)
        case let date as Date: self = .date(date)
        case let array as [Any]:
            let items = array.compactMap(PropertyListValue.init)
            guard items.count == array.count else { return nil }
            self = .array(items)
        case let dictionary as [String: Any]:
            var items: [String: PropertyListValue] = [:]
            for (key, element) in dictionary {
                guard let wrapped = PropertyListValue(element) else { return nil }
                items[key] = wrapped
            }
            self = .dictionary(items)
        default:
            return nil
        }
    }

    /// 还原成可以直接交给 `UserDefaults.set(_:forKey:)` 的值
    public var anyValue: Any {
        switch self {
        case .bool(let value): value
        case .integer(let value): value
        case .double(let value): value
        case .string(let value): value
        case .data(let value): value
        case .date(let value): value
        case .array(let value): value.map(\.anyValue)
        case .dictionary(let value): value.mapValues(\.anyValue)
        }
    }
}
