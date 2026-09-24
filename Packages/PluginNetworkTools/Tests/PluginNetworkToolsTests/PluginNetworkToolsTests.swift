// PluginNetworkToolsTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Testing

@testable import PluginNetworkTools

// MARK: - 纯逻辑

@Suite("resolv.conf 解析")
struct ResolvConfTests {

    /// 仿真实文件：一堆注释 + domain + 三条 nameserver
    private static let sample = """
        #
        # macOS Notice
        #
        # This file is not consulted for DNS hostname resolution, address
        # resolution, or the DNS query routing mechanism used by most
        # processes on this system.
        #
        domain example.com
        nameserver 192.168.1.1
        nameserver 8.8.8.8
        nameserver 2001:4860:4860::8888
        """

    @Test("按出现顺序收集 nameserver，IPv4 与 IPv6 都要")
    func collectsNameserversInOrder() {
        #expect(
            ResolvConf.dnsServers(in: Self.sample)
                == ["192.168.1.1", "8.8.8.8", "2001:4860:4860::8888"]
        )
    }

    @Test("空内容与非 nameserver 内容都得到空列表")
    func unrelatedContentYieldsNothing() {
        #expect(ResolvConf.dnsServers(in: "").isEmpty)
        #expect(ResolvConf.dnsServers(in: "\n\n").isEmpty)
        #expect(ResolvConf.dnsServers(in: "domain example.com").isEmpty)
        #expect(ResolvConf.dnsServers(in: "search example.com\noptions timeout:2").isEmpty)
    }

    @Test("注释掉的 nameserver 不算配置")
    func commentedDirectiveIsIgnored() {
        #expect(ResolvConf.dnsServers(in: "# nameserver 1.1.1.1").isEmpty)
        #expect(ResolvConf.dnsServers(in: "\tnameserver 1.1.1.1").isEmpty)
    }

    @Test("缺地址的裸指令会被跳过")
    func bareDirectiveIsSkipped() {
        #expect(ResolvConf.dnsServers(in: "nameserver").isEmpty)
        #expect(
            ResolvConf.dnsServers(in: "nameserver\nnameserver 8.8.8.8") == ["8.8.8.8"],
            "裸指令要跳过，后面的有效行仍要保留"
        )
    }

    @Test("制表符分隔与单个空格一样有效")
    func tabSeparatorWorks() {
        #expect(ResolvConf.dnsServers(in: "nameserver\t8.8.8.8") == ["8.8.8.8"])
    }

    @Test("多出来的参数被忽略，只取第一个地址")
    func extraArgumentsAreIgnored() {
        #expect(ResolvConf.dnsServers(in: "nameserver 8.8.8.8 8.8.4.4") == ["8.8.8.8"])
    }

    @Test("最后一行没有换行符也能解析")
    func lastLineWithoutNewlineWorks() {
        #expect(ResolvConf.dnsServers(in: "nameserver 1.1.1.1") == ["1.1.1.1"])
    }

    @Test("私有网段地址原样保留")
    func privateRangesAreKeptAsIs() {
        #expect(
            ResolvConf.dnsServers(in: "nameserver 10.0.0.1\nnameserver 172.16.5.5")
                == ["10.0.0.1", "172.16.5.5"]
        )
    }

    // MARK: 现状缺陷（按现状固定，未改动实现）

    @Test("连续空格会解析出一个空串地址（已知缺陷）")
    func consecutiveSpacesProduceEmptyEntry() {
        // components(separatedBy:) 不合并连续分隔符，于是第 2 段是空串。
        // macOS 实际写的是单个空白，所以暂时没暴露；一旦手工编辑过 resolv.conf
        // 就会在界面上出现一个空白的 DNS 条目。
        #expect(ResolvConf.dnsServers(in: "nameserver   8.8.8.8") == [""])
    }

    @Test("CRLF 行尾会把 \\r 留在地址里（已知缺陷）")
    func carriageReturnIsKeptInAddress() {
        // split 用的是 "\n"，而 \r 不属于 CharacterSet.whitespaces，
        // 于是地址末尾粘上一个回车。macOS 用 LF，所以只影响手工放进来的 CRLF 文件。
        #expect(ResolvConf.dnsServers(in: "nameserver 8.8.8.8\r\n") == ["8.8.8.8\r"])
    }

    @Test("指令名只要以 nameserver 开头就算命中（已知宽松点）")
    func prefixMatchOnDirectiveName() {
        #expect(ResolvConf.dnsServers(in: "nameserverX 1.2.3.4") == ["1.2.3.4"])
    }
}

// MARK: - 插件契约

@Suite("网络工具插件契约")
@MainActor
struct NetworkToolsPluginTests {

    @Test("id 是约定的字面量且为 kebab-case")
    func identifierConvention() {
        #expect(NetworkToolsPlugin.id == "networktools")
        #expect(
            NetworkToolsPlugin.id.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" },
            "id 是事件路由与设置存储的主键，必须是 kebab-case，实际为 \(NetworkToolsPlugin.id)"
        )
    }

    @Test("名称、图标与触发词非空")
    func displayMetadataIsPresent() {
        #expect(!NetworkToolsPlugin.name.isEmpty)
        #expect(!NetworkToolsPlugin.icon.isEmpty)
        #expect(!NetworkToolsPlugin.triggerWords.isEmpty)
    }

    /// 入口由静态命令承载，不再由搜索现算 —— 原来这条测试问的是 `searchItems` 的返回，
    /// 那个遗留 API 已删除（见 docs/refactor-plan.md Phase 0）。
    ///
    /// 整词匹配（clipboard 里的 ip 不该唤醒本插件）现在由 `matchesAnyTrigger` 保证，
    /// 它仍在闸门与命令关键词里用。
    @Test("命令覆盖四项网络工具，且功能命令带插件前缀")
    func commandsCoverTools() {
        let commands = NetworkToolsPlugin.commands
        let ids = commands.map(\.id)

        #expect(ids.contains("networktools.localIP"))
        #expect(ids.contains("networktools.publicIP"))
        #expect(ids.contains("networktools.dns"))
        #expect(ids.contains("networktools.speed"))
        let functionIDs = commands.filter { !$0.id.hasPrefix("plugin.open.") }.map(\.id)
        #expect(functionIDs.allSatisfy { $0.hasPrefix("networktools.") })
        #expect(commands.allSatisfy { $0.pluginID == NetworkToolsPlugin.id })
    }

    @Test("整词匹配：clipboard / description 里的 ip 不命中触发词")
    func unrelatedWordContainingTriggerDoesNotMatch() {
        let triggers = NetworkToolsPlugin.triggerWords

        #expect(!"clipboard".matchesAnyTrigger(triggers))
        #expect(!"description".matchesAnyTrigger(triggers))
        #expect("ip".matchesAnyTrigger(triggers))
    }

    @Test("插件不参与按查询现算")
    func doesNotTakePartInDynamicSearch() async {
        let plugin = NetworkToolsPlugin()

        #expect(!plugin.accepts(query: "ip"))
        #expect(await plugin.dynamicSearch(query: "definitely-unrelated").isEmpty)
    }
}
