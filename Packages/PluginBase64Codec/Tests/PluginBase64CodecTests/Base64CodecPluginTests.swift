// Base64CodecPluginTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Testing
@testable import PluginBase64Codec

@Suite("Base64 编解码逻辑")
struct Base64CodecLogicTests {

    @Test("编码结果符合标准 Base64")
    func encodesToStandardBase64() throws {
        #expect(try Base64CodecLogic.encode("hello") == "aGVsbG8=")
        #expect(try Base64CodecLogic.encode("") == "")
        #expect(try Base64CodecLogic.encode("你好") == "5L2g5aW9")
    }

    @Test("编码解码往返一致")
    func roundTrips() throws {
        for original in ["hello", "", "你好，世界", "line1\nline2", "a+b/c="] {
            let encoded = try Base64CodecLogic.encode(original)
            #expect(try Base64CodecLogic.decode(encoded) == original)
        }
    }

    /// 用户从网页或接口里复制来的 Base64 常常没有补位，这类输入必须报错而不是产出乱码
    @Test("非法 Base64 抛出 invalidBase64")
    func invalidBase64Throws() throws {
        #expect(throws: Base64CodecLogic.Failure.invalidBase64) {
            _ = try Base64CodecLogic.decode("!!!")
        }
        #expect(throws: Base64CodecLogic.Failure.invalidBase64) {
            _ = try Base64CodecLogic.decode("aGVsbG8")
        }
        // 空串是合法 Base64（解出空文本），视图在输入为空时提前 return，走不到这里
        #expect(try Base64CodecLogic.decode("") == "")
    }

    /// `//4=` 是合法 Base64，但解出来是 0xFF 0xFE —— 不是文本，
    /// 视图不能再往下走，否则会把二进制塞进 TextEditor
    @Test("解码结果不是 UTF-8 文本时同样失败")
    func nonUTF8PayloadThrows() {
        #expect(throws: Base64CodecLogic.Failure.invalidBase64) {
            _ = try Base64CodecLogic.decode("//4=")
        }
    }

    // MARK: - urlSafe

    @Test("URL-Safe 编码替换字母表并省略填充")
    func urlSafeEncoding() throws {
        let options = Base64CodecLogic.Options(isURLSafe: true)
        // "ÿÿ" 的标准 Base64 是 w7/Dvw==：含 / 且带填充，正好覆盖两条规则
        #expect(try Base64CodecLogic.encode("ÿÿ", options: options) == "w7_Dvw")
        #expect(try Base64CodecLogic.encode("hello", options: options) == "aGVsbG8")
    }

    @Test("URL-Safe 往返一致，含标准字母表会出 +/ 的输入")
    func urlSafeRoundTrip() throws {
        let options = Base64CodecLogic.Options(isURLSafe: true)
        for original in ["hello", "你好，世界", "a+b/c=", "ÿÿ", ""] {
            let encoded = try Base64CodecLogic.encode(original, options: options)
            #expect(!encoded.contains("+") && !encoded.contains("/") && !encoded.contains("="))
            #expect(try Base64CodecLogic.decode(encoded, options: options) == original)
        }
    }

    @Test("URL-Safe 解码补回缺失的填充")
    func urlSafeDecodeRestoresPadding() throws {
        let options = Base64CodecLogic.Options(isURLSafe: true)
        // 缺填充的 "aGVsbG8" 在标准模式下是非法输入，URL-Safe 模式必须能解
        #expect(try Base64CodecLogic.decode("aGVsbG8", options: options) == "hello")
    }

    // MARK: - wrapLines

    @Test("折行编码每行 64 个字符")
    func wrapLinesEncoding() throws {
        let options = Base64CodecLogic.Options(wrapsLines: true)
        let input = String(repeating: "a", count: 100)
        let encoded = try Base64CodecLogic.encode(input, options: options)
        let lines = encoded.split(separator: "\n", omittingEmptySubsequences: false)

        #expect(lines.allSatisfy { $0.count <= 64 })
        #expect(lines.dropLast().allSatisfy { $0.count == 64 })
        // 去掉换行后与标准编码一致 —— 折行只是排版，不改变内容
        #expect(encoded.replacingOccurrences(of: "\n", with: "") == (try Base64CodecLogic.encode(input)))
    }

    @Test("折行输出能原样粘回来解码")
    func wrappedOutputDecodes() throws {
        let options = Base64CodecLogic.Options(wrapsLines: true)
        let original = String(repeating: "你好", count: 50)
        let encoded = try Base64CodecLogic.encode(original, options: options)
        #expect(encoded.contains("\n"))
        #expect(try Base64CodecLogic.decode(encoded, options: options) == original)
    }

    @Test("模式原始值是中文标签且覆盖编解码")
    func modeLabels() {
        #expect(Base64CodecLogic.Mode.allCases.count == 2)
        #expect(Base64CodecLogic.Mode.encode.rawValue == "编码")
        #expect(Base64CodecLogic.Mode.decode.rawValue == "解码")
    }
}

@MainActor
@Suite("Base64 编解码插件契约")
struct Base64CodecPluginTests {

    @Test("元数据符合插件约定")
    func metadata() {
        #expect(Base64CodecPlugin.id == "base64-codec")
        #expect(Base64CodecPlugin.id.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" })
        #expect(!Base64CodecPlugin.name.isEmpty)
        #expect(!Base64CodecPlugin.icon.isEmpty)
        #expect(!Base64CodecPlugin.triggerWords.isEmpty)
    }

    /// 入口由静态命令提供，不再由搜索现算 —— 这条测试因此问的是 `commands`。
    /// 以前它问的是 `searchItems`，而那个遗留 API 已经删掉了（见 docs/refactor-plan.md Phase 0）。
    ///
    /// 注意 id 有两套前缀：默认的「打开本插件」用 `plugin.open.<id>`，
    /// 功能命令用 `<id>.<功能>`。这不是笔误，是既有约定，见 docs/architecture.md。
    @Test("声明的命令覆盖编解码两个功能，且 id 带插件前缀")
    func commandsCoverBothDirections() {
        let commands = Base64CodecPlugin.commands
        let ids = commands.map(\.id)

        #expect(ids.contains("base64-codec.encode"))
        #expect(ids.contains("base64-codec.decode"))
        #expect(ids.contains("plugin.open.base64-codec"))
        // 功能命令必须带插件前缀：宿主按 "<pluginID>." 前缀回退找执行者
        let functionIDs = commands.filter { !$0.id.hasPrefix("plugin.open.") }.map(\.id)
        #expect(functionIDs.allSatisfy { $0.hasPrefix("base64-codec.") })
        #expect(commands.allSatisfy { $0.pluginID == Base64CodecPlugin.id })
    }

    /// 插件不参与按查询现算：闸门恒为 false，聚合器因此不会在每次按键时叫醒它。
    @Test("不参与动态搜索")
    func doesNotTakePartInDynamicSearch() async {
        let plugin = Base64CodecPlugin()
        #expect(!plugin.accepts(query: "base64"))
        #expect(await plugin.dynamicSearch(query: "base64").isEmpty)
    }
}
