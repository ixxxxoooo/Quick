// UUIDGeneratorPluginTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import PluginUUIDGenerator

@Suite("UUID 生成逻辑")
struct UUIDGeneratorLogicTests {

    /// 固定 UUID：让「大小写 / 连字符」两个开关的断言不依赖随机源
    private let fixedUUID = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")

    @Test("默认输出沿用 UUID.uuidString 的大写带连字符形式")
    func producesUppercasedHyphenatedByDefault() throws {
        let uuid = try #require(fixedUUID)
        let generated = UUIDGeneratorLogic.generate(
            count: 1, uppercase: true, removeDashes: false, using: { uuid })
        #expect(generated == ["E621E1F8-C36C-495A-93FC-0C247A3E6E5F"])
    }

    @Test("关掉大写后整串转小写")
    func lowercasesWhenAsked() throws {
        let uuid = try #require(fixedUUID)
        let generated = UUIDGeneratorLogic.generate(
            count: 1, uppercase: false, removeDashes: false, using: { uuid })
        #expect(generated == ["e621e1f8-c36c-495a-93fc-0c247a3e6e5f"])
    }

    @Test("去连字符后是 32 位紧凑形式，大小写开关仍然生效")
    func removesDashes() throws {
        let uuid = try #require(fixedUUID)
        let upper = UUIDGeneratorLogic.generate(
            count: 1, uppercase: true, removeDashes: true, using: { uuid })
        let lower = UUIDGeneratorLogic.generate(
            count: 1, uppercase: false, removeDashes: true, using: { uuid })
        #expect(upper == ["E621E1F8C36C495A93FC0C247A3E6E5F"])
        #expect(lower == ["e621e1f8c36c495a93fc0c247a3e6e5f"])
    }

    @Test("数量为 0 时返回空数组")
    func zeroCountProducesNothing() {
        #expect(UUIDGeneratorLogic.generate(count: 0, uppercase: true, removeDashes: false).isEmpty)
    }

    @Test("负数数量返回空数组而不是崩溃")
    func negativeCountProducesNothing() {
        #expect(UUIDGeneratorLogic.generate(count: -3, uppercase: true, removeDashes: false).isEmpty)
    }

    @Test("真实随机源下：数量、形状、唯一性都成立")
    func randomBatchShapeAndUniqueness() {
        let generated = UUIDGeneratorLogic.generate(count: 100, uppercase: true, removeDashes: false)
        #expect(generated.count == 100)
        #expect(generated.allSatisfy { $0.count == 36 })
        // 8-4-4-4-12 的连字符位置是 UUID 文本形式的定义，跑偏了说明拼接逻辑错了
        #expect(
            generated.allSatisfy { $0.filter(\.isNumber).count + $0.filter { $0.isHexLetter }.count == 32 })
        #expect(
            generated.allSatisfy {
                $0.enumerated().allSatisfy { offset, character in
                    [8, 13, 18, 23].contains(offset) ? character == "-" : character != "-"
                }
            })
        #expect(Set(generated).count == 100, "批量生成不允许重复")
    }

    @Test("去连字符的真实批量都是 32 位")
    func randomBatchWithoutDashes() {
        let generated = UUIDGeneratorLogic.generate(count: 20, uppercase: false, removeDashes: true)
        #expect(generated.count == 20)
        #expect(generated.allSatisfy { $0.count == 32 })
        #expect(generated.allSatisfy { $0.allSatisfy { $0.isNumber || ("a"..."f").contains($0) } })
    }
}

extension Character {
    /// 是否是十六进制字母（0-9 由 `isNumber` 覆盖）
    fileprivate var isHexLetter: Bool { ("a"..."f").contains(self) || ("A"..."F").contains(self) }
}

@Suite("UUID 生成器插件契约")
@MainActor
struct UUIDGeneratorPluginTests {

    /// 插件 id 必须是 kebab-case
    private func isKebabCase(_ value: String) -> Bool {
        !value.isEmpty
            && !value.contains("_")
            && value.allSatisfy { $0.isNumber || $0 == "-" || ("a"..."z").contains($0) }
    }

    @Test("id 是 kebab-case 且与约定一致")
    func identifierConvention() {
        #expect(UUIDGeneratorPlugin.id == "uuid-generator")
        #expect(isKebabCase(UUIDGeneratorPlugin.id))
    }

    @Test("名称、图标、触发词都不为空")
    func metadataIsPresent() {
        #expect(!UUIDGeneratorPlugin.name.isEmpty)
        #expect(!UUIDGeneratorPlugin.icon.isEmpty)
        #expect(!UUIDGeneratorPlugin.triggerWords.isEmpty)
    }

    /// 单面板插件只暴露唯一入口命令，触发词收敛到 `triggerWords`。
    @Test("单面板插件只暴露打开插件入口命令")
    func commandsCoverGenerate() {
        let commands = UUIDGeneratorPlugin.commands
        #expect(commands.map(\.id) == ["plugin.open.uuid-generator"])
        #expect(commands.allSatisfy { $0.pluginID == UUIDGeneratorPlugin.id })
    }

    /// 插件不参与按查询现算：闸门恒为 false，聚合器因此不会在每次按键时叫醒它。
    @Test("不参与动态搜索")
    func doesNotTakePartInDynamicSearch() async {
        let plugin = UUIDGeneratorPlugin()
        #expect(!plugin.accepts(query: "uuid"))
        #expect(await plugin.dynamicSearch(query: "uuid").isEmpty)
    }
}

@Suite("UUID v7")
struct UUIDv7Tests {

    @Test("版本位是 7，变体位是 10，高 48 位是毫秒时间戳")
    func layoutFollowsRFC9562() {
        let uuid = UUIDGeneratorLogic.makeV7(
            milliseconds: 0x0123_4567_89AB, random: [UInt8](repeating: 0xFF, count: 10))
        let text = uuid.uuidString
        // 形如 01234567-89AB-7FFF-BFFF-FFFFFFFFFFFF
        #expect(text.hasPrefix("01234567-89AB-7"))
        let variant = text.split(separator: "-")[3].first
        #expect(variant == "B")
    }

    @Test("随机字节全 0 时版本位与变体位依然正确")
    func versionBitsSurviveZeroRandom() {
        let text = UUIDGeneratorLogic.makeV7(milliseconds: 0, random: []).uuidString
        #expect(text == "00000000-0000-7000-8000-000000000000")
    }

    @Test("同一毫秒内生成的一批 UUID 严格递增，字符串排序即生成顺序")
    func batchIsStrictlyIncreasing() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let batch = UUIDGeneratorLogic.generateV7(count: 50, now: now).map { $0.uuidString }
        #expect(batch.count == 50)
        #expect(batch == batch.sorted())
        #expect(Set(batch).count == 50)
    }

    @Test("generate 选 v7 时输出合法 UUID，且大小写开关依然生效")
    func generateHonorsVersionAndCase() {
        let lower = UUIDGeneratorLogic.generate(
            count: 3, uppercase: false, removeDashes: true, version: .v7)
        #expect(lower.count == 3)
        for text in lower {
            #expect(text.count == 32)
            #expect(text == text.lowercased())
            #expect(text[text.index(text.startIndex, offsetBy: 12)] == "7")
        }
    }

    @Test("负数数量按 0 处理，不会崩")
    func negativeCountIsEmpty() {
        #expect(UUIDGeneratorLogic.generateV7(count: -3).isEmpty)
    }
}
