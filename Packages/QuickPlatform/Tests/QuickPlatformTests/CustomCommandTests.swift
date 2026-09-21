// CustomCommandTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import QuickPlatform

@Suite("自定义命令模型")
struct CustomCommandTests {

    /// 加字段不能把用户存过的命令弄丢
    ///
    /// 合成的解码器只缺一个 key 就整条失败，而调用点用的是 `try?` 加上**整个数组**
    /// （`LauncherPlugin` 与 `AppCore.loadCustomCommands`）：一条命令读不出来，用户存过的
    /// 命令就全部从面板里消失，而且没有任何日志。所以解码必须对缺字段宽容。
    @Test("缺字段的旧数据仍然可以解码")
    func decodesLegacyPayloadWithoutNewKeys() throws {
        let legacy = """
            [{"id":"\(UUID().uuidString)","name":"清理缓存","command":"rm -rf .build","alias":"cc"}]
            """
        let decoded = try JSONDecoder().decode([CustomCommand].self, from: Data(legacy.utf8))

        #expect(decoded.count == 1)
        #expect(decoded[0].name == "清理缓存")
        #expect(decoded[0].alias == "cc")
        #expect(decoded[0].isEnabled, "没写过的开关要回落到默认值")
        #expect(!decoded[0].loadsShellEnvironment)
        #expect(decoded[0].showsOutput)
    }

    @Test("新字段能往返编解码")
    func roundTripsNewField() throws {
        let original = CustomCommand(
            name: "跑测试", command: "swift test", loadsShellEnvironment: true)
        let decoded = try JSONDecoder().decode(
            [CustomCommand].self, from: JSONEncoder().encode([original]))

        #expect(decoded == [original])
    }
}
