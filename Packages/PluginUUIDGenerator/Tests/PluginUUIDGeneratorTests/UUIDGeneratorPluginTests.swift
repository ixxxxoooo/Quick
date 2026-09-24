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

    /// 入口由静态命令提供，不再由搜索现算 —— 这条测试因此问的是 `commands`。
    ///
    /// id 有两套前缀：默认的「打开本插件」是 `plugin.open.<id>`，功能命令是
    /// `<id>.<功能>`。宿主按 `<pluginID>.` 前缀回退找执行者，所以功能命令必须带前缀。
    @Test("声明的命令覆盖生成功能，且功能命令带插件前缀")
    func commandsCoverGenerate() {
        let commands = UUIDGeneratorPlugin.commands
        let ids = commands.map(\.id)

        #expect(ids.contains("uuid-generator.generate"))
        #expect(ids.contains("plugin.open.uuid-generator"))
        let functionIDs = commands.filter { !$0.id.hasPrefix("plugin.open.") }.map(\.id)
        #expect(functionIDs.allSatisfy { $0.hasPrefix("uuid-generator.") })
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
