// ColorComparePluginTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Testing

@testable import PluginColorCompare

@Suite("颜色识别与转换")
@MainActor
struct ColorCompareLogicTests {

    // MARK: - HEX 解析

    @Test("三位缩写 HEX 补全成六位并转大写")
    func shorthandHexIsExpanded() throws {
        let colors = ColorCompareLogic.parse("#fff")

        #expect(colors.count == 1)
        let color = try #require(colors.first)
        #expect(color.hex == "#FFFFFF")
        #expect(color.r == 255)
        #expect(color.g == 255)
        #expect(color.b == 255)
        #expect(color.rgbString == "rgb(255, 255, 255)")
    }

    @Test("不带 # 的裸 HEX 不被识别")
    func bareHexIsNotRecognized() {
        // 识别依赖 "#..." 正则，裸 fff 会被当成普通文本忽略
        #expect(ColorCompareLogic.parse("fff").isEmpty)
        #expect(ColorCompareLogic.parse("FF8800").isEmpty)
    }

    @Test("六位 HEX 原样保留并补足 rgb 分量")
    func explicitHexIsPreserved() throws {
        let color = try #require(ColorCompareLogic.parse("#FF8800").first)

        #expect(color.hex == "#FF8800")
        #expect(color.r == 255)
        #expect(color.g == 136)
        #expect(color.b == 0)
        #expect(color.rgbString == "rgb(255, 136, 0)")
    }

    @Test("小写 HEX 归一化为大写")
    func lowercaseHexIsUppercased() throws {
        let color = try #require(ColorCompareLogic.parse("#ff8800").first)

        #expect(color.hex == "#FF8800")
    }

    @Test("超长 HEX 只取前六位")
    func overlongHexTakesFirstSixDigits() throws {
        // 正则先试 6 位再试 3 位，所以 7 位输入剩下的一位被丢掉
        let color = try #require(ColorCompareLogic.parse("#1234567").first)

        #expect(color.hex == "#123456")
    }

    // MARK: - rgb() 解析

    @Test("rgb() 转成 HEX，允许空格且大小写不敏感")
    func rgbFunctionIsConvertedToHex() throws {
        let spaced = try #require(ColorCompareLogic.parse("rgb(255, 136, 0)").first)
        #expect(spaced.hex == "#FF8800")
        #expect(spaced.rgbString == "rgb(255, 136, 0)")

        let upper = try #require(ColorCompareLogic.parse("RGB(255,87,51)").first)
        #expect(upper.hex == "#FF5733")
        #expect(upper.rgbString == "rgb(255, 87, 51)")
    }

    @Test("非法输入不产生颜色")
    func invalidInputYieldsNothing() {
        #expect(ColorCompareLogic.parse("").isEmpty)
        #expect(ColorCompareLogic.parse("hello world").isEmpty)
        // #GGGGGG 不是合法十六进制
        #expect(ColorCompareLogic.parse("#GGGGGG").isEmpty)
        // 只支持 rgb()，alpha 通道形式识别不了
        #expect(ColorCompareLogic.parse("rgba(255, 0, 0, 0.5)").isEmpty)
    }

    @Test("越界分量夹到 0...255")
    func outOfRangeComponentsAreClamped() throws {
        let color = try #require(ColorCompareLogic.parse("rgb(300, 0, 0)").first)

        // 夹取而不是报错，与 CSS 一致：否则会拼出 `#12C0000` 这种 7 位色值
        #expect(color.r == 255)
        #expect(color.g == 0)
        #expect(color.b == 0)
        #expect(color.rgbString == "rgb(255, 0, 0)")
        #expect(color.hex == "#FF0000")
    }

    // MARK: - 扫描顺序

    @Test("两趟扫描决定顺序：先全部 HEX，再全部 rgb()")
    func hexMatchesComeBeforeRGBMatches() {
        let mixed = ColorCompareLogic.parse("rgb(0,0,0) #FF8800").map(\.hex)

        // 输入里 rgb() 在前，结果仍是 HEX 在前 —— 网格与亮度条的排序依赖这个顺序
        #expect(mixed == ["#FF8800", "#000000"])

        let split = ColorCompareLogic.parse("#FF8800 and rgb(0,0,0)").map(\.hex)
        #expect(split == ["#FF8800", "#000000"])
    }

    // MARK: - 亮度

    @Test("相对亮度落在 WCAG 的两个端点上")
    func luminanceEndpoints() throws {
        let white = try #require(ColorCompareLogic.parse("#FFFFFF").first)
        let black = try #require(ColorCompareLogic.parse("#000000").first)

        #expect(abs(white.luminance - 1.0) < 1e-12)
        #expect(black.luminance == 0.0)
    }

    @Test("亮度公式在中灰与纯绿上的取值")
    func luminanceFormulaOnKnownColors() throws {
        let gray = try #require(ColorCompareLogic.parse("#808080").first)
        let green = try #require(ColorCompareLogic.parse("#00FF00").first)
        let orange = try #require(ColorCompareLogic.parse("#FF8800").first)

        #expect(abs(gray.luminance - 0.21586050011389923) < 1e-12)
        // 绿色权重 0.7152，红蓝为 0 时亮度恰好等于权重本身
        #expect(abs(green.luminance - 0.7152) < 1e-12)
        #expect(abs(orange.luminance - 0.38868318886144393) < 1e-12)
    }

    @Test("亮度排序从亮到暗")
    func sortingIsDescending() {
        let colors = ColorCompareLogic.parse("#808080 #FFFFFF #000000")

        #expect(
            ColorCompareLogic.sortedByLuminance(colors).map(\.hex) == [
                "#FFFFFF", "#808080", "#000000"
            ])
    }

    @Test("亮度百分比按一位小数展示")
    func luminancePercentageFormatting() throws {
        let gray = try #require(ColorCompareLogic.parse("#808080").first)
        let white = try #require(ColorCompareLogic.parse("#FFFFFF").first)

        #expect(String(format: "%.1f%%", gray.luminance * 100) == "21.6%")
        #expect(String(format: "%.1f%%", white.luminance * 100) == "100.0%")
    }

    // MARK: - 导出文本

    @Test("全部复制的文本格式")
    func copyTextFormat() {
        let colors = ColorCompareLogic.parse("#FF8800 rgb(0, 0, 0)")

        #expect(
            ColorCompareLogic.copyText(colors)
                == "#FF8800 | rgb(255, 136, 0)\n#000000 | rgb(0, 0, 0)"
        )
        #expect(ColorCompareLogic.copyText([]).isEmpty)
    }
}

@Suite("颜色工具插件契约")
@MainActor
struct ColorComparePluginTests {

    @Test("插件 id 是 kebab-case 且等于约定值")
    func identifierConvention() {
        let id = ColorComparePlugin.id

        #expect(id == "color-compare")
        #expect(!id.hasPrefix("-") && !id.hasSuffix("-") && !id.contains("--"))
        #expect(id.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" })
    }

    @Test("名称、图标、触发词齐备")
    func metadataIsComplete() {
        #expect(ColorComparePlugin.name == "颜色工具")
        #expect(ColorComparePlugin.icon == "paintpalette.fill")
        #expect(!ColorComparePlugin.triggerWords.isEmpty)
        #expect(ColorComparePlugin.triggerWords.allSatisfy { !$0.isEmpty })
    }

    /// 入口由静态命令提供，不再由搜索现算。原测试断言的是 `searchItems` 的返回，
    /// 而那个遗留 API 已删除（见 docs/refactor-plan.md Phase 0）。
    @Test("声明的命令覆盖识别与对比度，且 id 带插件前缀")
    func commandsCoverFeatures() {
        let commands = ColorComparePlugin.commands
        let ids = commands.map(\.id)

        #expect(ids.contains("color-compare.identify"))
        #expect(ids.contains("color-compare.contrast"))
        // 功能命令带插件前缀，宿主按它回退找执行者；「打开本插件」用 plugin.open. 前缀
        let functionIDs = commands.filter { !$0.id.hasPrefix("plugin.open.") }.map(\.id)
        #expect(functionIDs.allSatisfy { $0.hasPrefix("color-compare.") })
        #expect(commands.allSatisfy { $0.pluginID == ColorComparePlugin.id })
        #expect(commands.allSatisfy { !$0.title.isEmpty })
    }

    /// 插件不参与按查询现算：聚合器因此不会在每次按键时叫醒它。
    @Test("不参与动态搜索")
    func doesNotTakePartInDynamicSearch() async {
        let plugin = ColorComparePlugin()

        #expect(!plugin.accepts(query: "颜色"))
        #expect(await plugin.dynamicSearch(query: "").isEmpty)
        #expect(await plugin.dynamicSearch(query: "天气").isEmpty)
    }
}
