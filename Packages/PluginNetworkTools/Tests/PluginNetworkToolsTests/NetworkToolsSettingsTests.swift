// NetworkToolsSettingsTests.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import QuickCore
import Testing

@testable import PluginNetworkTools

/// 这一组验证设置页上的「显示公网 IP」真的改变了行为，而不是只把值写进 `UserDefaults`。
///
/// 服务读的是标准偏好存储，用例也只能写标准存储 —— 换成独立 suite 就测不到接线了。
/// 标准存储是进程共享的，所以用例必须串行并自己收尾（见 `withStandardDefaults`）。
@Suite("网络工具的设置接线", .serialized)
@MainActor
struct NetworkToolsSettingWiringTests {

    private static let touchedKeys = [PluginSettingKey.NetworkTools.showExternalIP]

    /// 查询实现固定成这个测试地址：真发请求会让用例依赖网络，也等于让 CI 去调第三方接口
    private static let stubIP = "203.0.113.9"

    private static func makeService() -> NetworkService {
        NetworkService(fetchPublicIP: { stubIP })
    }

    /// 跑完把这个键的旧值原样放回去，不让用例互相污染，也不留在真实偏好里
    private static func withStandardDefaults(_ body: () async throws -> Void) async throws {
        var saved: [String: Any] = [:]
        for key in touchedKeys {
            saved[key] = UserDefaults.standard.object(forKey: key)
        }
        defer {
            for key in touchedKeys {
                if let previous = saved[key] {
                    UserDefaults.standard.set(previous, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
        try await body()
    }

    @Test("开关关着时不查公网 IP，开着时才用查询结果")
    func publicIPFollowsTheSetting() async throws {
        try await Self.withStandardDefaults {
            UserDefaults.standard.set(false, forKey: PluginSettingKey.NetworkTools.showExternalIP)
            let off = Self.makeService()
            #expect(!off.showsExternalIP, "开关关着时视图不该显示公网 IP 这一行")
            await off.refresh()
            #expect(off.networkInfo?.publicIP == nil, "开关关着却仍然查了公网 IP")

            UserDefaults.standard.set(true, forKey: PluginSettingKey.NetworkTools.showExternalIP)
            let on = Self.makeService()
            #expect(on.showsExternalIP)
            await on.refresh()
            #expect(on.networkInfo?.publicIP == Self.stubIP, "开关开着却没有采用查询结果")
        }
    }

    @Test("没设置过时按设置页显示的「开」")
    func unsetFallsBackToOn() async throws {
        try await Self.withStandardDefaults {
            UserDefaults.standard.removeObject(forKey: PluginSettingKey.NetworkTools.showExternalIP)

            let service = Self.makeService()
            #expect(service.showsExternalIP)
            await service.refresh()
            #expect(service.networkInfo?.publicIP == Self.stubIP, "没设置过时应当按默认的开处理")
        }
    }

    @Test("运行期关掉开关后再刷新，公网 IP 从结果里撤掉")
    func turningOffRemovesTheValue() async throws {
        try await Self.withStandardDefaults {
            UserDefaults.standard.set(true, forKey: PluginSettingKey.NetworkTools.showExternalIP)
            let service = Self.makeService()
            await service.refresh()
            #expect(service.networkInfo?.publicIP == Self.stubIP)

            UserDefaults.standard.set(false, forKey: PluginSettingKey.NetworkTools.showExternalIP)
            await service.refresh()
            #expect(service.networkInfo?.publicIP == nil, "关掉开关后刷新不该再带上公网 IP")
            // 本机 IP 与 DNS 与这个开关无关，仍要照常给出
            #expect(service.networkInfo != nil)
        }
    }
}

@Suite("Ping 解析与校验")
struct PingTests {

    @Test("解析 macOS ping 的汇总行")
    func parsesSummary() throws {
        let output = """
            PING apple.com (17.253.144.10): 56 data bytes
            64 bytes from 17.253.144.10: icmp_seq=0 ttl=52 time=20.1 ms

            --- apple.com ping statistics ---
            4 packets transmitted, 3 packets received, 25.0% packet loss
            round-trip min/avg/max/stddev = 19.5/21.25/23.0/1.4 ms
            """
        let summary = try #require(PingParser.parse(output))
        #expect(summary.transmitted == 4)
        #expect(summary.received == 3)
        #expect(summary.lossPercent == 25.0)
        #expect(summary.minMs == 19.5)
        #expect(summary.avgMs == 21.25)
        #expect(summary.maxMs == 23.0)
        #expect(summary.headline.contains("21.2") || summary.headline.contains("21.3"))
    }

    @Test("全部丢包时没有往返行，仍给出汇总")
    func parsesTotalLoss() throws {
        let output = "4 packets transmitted, 0 packets received, 100.0% packet loss"
        let summary = try #require(PingParser.parse(output))
        #expect(summary.received == 0)
        #expect(summary.avgMs == nil)
        #expect(summary.headline.hasPrefix("不可达"))
    }

    @Test("主机解析失败等无汇总输出返回 nil")
    func unparsableOutputIsNil() {
        #expect(PingParser.parse("ping: cannot resolve nohost.invalid: Unknown host") == nil)
        #expect(PingParser.parse("") == nil)
    }

    @Test("目标校验：放行主机名与 IP，拒绝选项与注入字符")
    func validatesTargets() {
        #expect(PingTarget.validated(" apple.com ") == "apple.com")
        #expect(PingTarget.validated("192.168.1.1") == "192.168.1.1")
        #expect(PingTarget.validated("fe80::1") == "fe80::1")
        #expect(PingTarget.validated("-f") == nil)
        #expect(PingTarget.validated("a.com; rm -rf /") == nil)
        #expect(PingTarget.validated("") == nil)
        #expect(PingTarget.validated(String(repeating: "a", count: 300)) == nil)
    }

    @Test("偏好夹到合理范围，缺省取默认")
    func preferencesAreClamped() {
        let suite = UserDefaults(suiteName: "networktools.prefs.\(UUID().uuidString)")!
        #expect(NetworkToolsPreferences.pingCount(defaults: suite) == 4)
        #expect(NetworkToolsPreferences.timeout(defaults: suite) == 5)
        suite.set(0, forKey: PluginSettingKey.NetworkTools.pingCount)
        suite.set(9999, forKey: PluginSettingKey.NetworkTools.timeout)
        #expect(NetworkToolsPreferences.pingCount(defaults: suite) == 1)
        #expect(NetworkToolsPreferences.timeout(defaults: suite) == 30)
    }

    @Test("真实 ping 本机回环：能跑通并解析出 0 丢包")
    func pingsLoopback() async {
        let outcome = await PingRunner.run(host: "127.0.0.1", count: 2, timeoutSeconds: 2)
        guard case let .finished(summary, _) = outcome else {
            Issue.record("ping 回环失败：\(outcome)")
            return
        }
        #expect(summary.received == 2)
        #expect(summary.lossPercent == 0)
    }

    @Test("取消任务会终止 ping 子进程，不会等满全部包数")
    func cancellationTerminatesThePingProcess() async {
        let started = ContinuousClock.now
        let task = Task { await PingRunner.run(host: "127.0.0.1", count: 20, timeoutSeconds: 2) }
        try? await Task.sleep(for: .milliseconds(300))
        task.cancel()
        _ = await task.value
        // 20 个包按 1 秒间隔要 19 秒以上；被终止则应在几秒内返回
        #expect(ContinuousClock.now - started < .seconds(8))
    }
}
