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
