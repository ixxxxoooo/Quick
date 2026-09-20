// HashCalculatorPluginTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Testing

@testable import PluginHashCalculator

@Suite("哈希计算逻辑")
struct HashCalculatorLogicTests {

    // MARK: - 已知答案

    @Test("abc 的四种摘要都是标准向量")
    func knownAnswersForABC() {
        #expect(
            HashCalculatorLogic.digest("abc", algorithm: .md5)
                == "900150983cd24fb0d6963f7d28e17f72")
        #expect(
            HashCalculatorLogic.digest("abc", algorithm: .sha1)
                == "a9993e364706816aba3e25717850c26c9cd0d89d")
        #expect(
            HashCalculatorLogic.digest("abc", algorithm: .sha256)
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(
            HashCalculatorLogic.digest("abc", algorithm: .sha512)
                == """
                ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a\
                2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f
                """)
    }

    @Test("空串摘要有定义：这是空输入的哈希，不是「没有输入」")
    func knownAnswersForEmptyString() {
        #expect(
            HashCalculatorLogic.digest("", algorithm: .md5)
                == "d41d8cd98f00b204e9800998ecf8427e")
        #expect(
            HashCalculatorLogic.digest("", algorithm: .sha1)
                == "da39a3ee5e6b4b0d3255bfef95601890afd80709")
        #expect(
            HashCalculatorLogic.digest("", algorithm: .sha256)
                == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test("非 ASCII 按 UTF-8 字节计算，不是按 UTF-16 或本地编码")
    func unicodeUsesUTF8Bytes() {
        #expect(
            HashCalculatorLogic.digest("中", algorithm: .md5)
                == "aed1dfbc31703955e64806b799b67645")
        #expect(
            HashCalculatorLogic.digest("中", algorithm: .sha256)
                == "a567bdaa11367f260f0708391f4d10766b5962f565d9e432f17981a3584fe1e2")
        // 同样的字在 UTF-16 下的字节完全不同，撞上说明编码选错了
        #expect(
            HashCalculatorLogic.digest("中", algorithm: .sha256)
                != HashCalculatorLogic.digest("a", algorithm: .sha256))
    }

    // MARK: - 输出格式

    @Test("摘要一律小写十六进制，长度与算法对应")
    func hexFormatAndLength() {
        let expectedLengths: [HashCalculatorLogic.Algorithm: Int] = [
            .md5: 32, .sha1: 40, .sha256: 64, .sha512: 128
        ]
        for algorithm in HashCalculatorLogic.Algorithm.allCases {
            let value = HashCalculatorLogic.digest("quick", algorithm: algorithm)
            #expect(value.count == expectedLengths[algorithm])
            #expect(value.allSatisfy { $0.isNumber || ("a"..."f").contains($0) })
        }
    }

    @Test("算法名就是界面显示名，顺序固定")
    func algorithmNamesAndOrder() {
        #expect(
            HashCalculatorLogic.Algorithm.allCases.map(\.rawValue)
                == ["MD5", "SHA1", "SHA256", "SHA512"])
    }

    // MARK: - 批量结果

    @Test("非空输入一次返回四种算法，顺序与 allCases 一致")
    func digestsCoverEveryAlgorithm() {
        let results = HashCalculatorLogic.digests(of: "abc")
        #expect(results.map(\.algorithm) == HashCalculatorLogic.Algorithm.allCases)
        #expect(results.allSatisfy { !$0.value.isEmpty })
    }

    @Test("空输入返回空列表：界面走「还没有输入」的空状态")
    func emptyInputProducesNoRows() {
        #expect(HashCalculatorLogic.digests(of: "").isEmpty)
    }

    @Test("换行与空白是内容的一部分，不能被忽略")
    func whitespaceIsPartOfTheInput() {
        #expect(
            HashCalculatorLogic.digest(" abc", algorithm: .md5)
                != HashCalculatorLogic.digest("abc", algorithm: .md5))
        #expect(
            HashCalculatorLogic.digest("a\nb", algorithm: .md5)
                != HashCalculatorLogic.digest("ab", algorithm: .md5))
    }
}

@Suite("Hash 计算器插件契约")
@MainActor
struct HashCalculatorPluginTests {

    /// 插件 id 必须是 kebab-case
    private func isKebabCase(_ value: String) -> Bool {
        !value.isEmpty
            && !value.contains("_")
            && value.allSatisfy { $0.isNumber || $0 == "-" || ("a"..."z").contains($0) }
    }

    @Test("id 是 kebab-case 且与约定一致")
    func identifierConvention() {
        #expect(HashCalculatorPlugin.id == "hash-calculator")
        #expect(isKebabCase(HashCalculatorPlugin.id))
    }

    @Test("名称、图标、触发词都不为空")
    func metadataIsPresent() {
        #expect(!HashCalculatorPlugin.name.isEmpty)
        #expect(!HashCalculatorPlugin.icon.isEmpty)
        #expect(!HashCalculatorPlugin.triggerWords.isEmpty)
    }

    @Test("任一触发词都能唤醒插件，且只返回一个入口", arguments: ["hash", "md5", "sha256", "哈希"])
    func searchItemsMatchTrigger(_ trigger: String) async {
        let items = await HashCalculatorPlugin().searchItems(query: trigger)
        #expect(items.count == 1)
        #expect(items.first?.id == "hash-calculator.open")
        #expect(items.first?.pluginID == HashCalculatorPlugin.id)
    }

    @Test("无关查询不返回结果")
    func unrelatedQueryReturnsNothing() async {
        let items = await HashCalculatorPlugin().searchItems(query: "天气")
        #expect(items.isEmpty)
    }
}
