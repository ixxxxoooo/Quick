// NetworkService.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Network
import QuickCore

/// 网络服务
///
/// 提供 IP 查询、DNS 信息和网络连接测试。
@MainActor
@Observable
final class NetworkService {

    /// 网络信息
    struct NetworkInfo: Sendable {
        let localIP: String
        let publicIP: String?
        let dns: [String]
    }

    private(set) var networkInfo: NetworkInfo?
    private(set) var isLoading = false

    /// 公网 IP 的查法（可注入：测试用它替掉真实请求）
    private let fetchPublicIP: @MainActor () async -> String?

    /// - Parameter fetchPublicIP: 查询公网 IP 的实现；默认走网络，测试注入固定值
    init(fetchPublicIP: (@MainActor () async -> String?)? = nil) {
        self.fetchPublicIP = fetchPublicIP ?? Self.publicIPFromNetwork
    }

    /// 设置页「显示公网 IP」的当前取值
    ///
    /// 视图和刷新都看它，现读而不是 init 时读一次 —— 设置页可以在运行期改。
    var showsExternalIP: Bool {
        PluginDefaults.isEnabled(PluginSettingKey.NetworkTools.showExternalIP, default: true)
    }

    /// 获取网络信息
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let localIP = getLocalIP()

        // 开关关掉时不查公网 IP：设置页承诺的是「不展示」，而为了不展示去发一次请求
        // 既没有意义，也白白把本机 IP 告诉了第三方接口
        let publicIP = showsExternalIP ? await fetchPublicIP() : nil

        let dns = getDNSServers()

        networkInfo = NetworkInfo(
            localIP: localIP,
            publicIP: publicIP,
            dns: dns
        )
    }

    /// 获取本机 IP
    private func getLocalIP() -> String {
        var address = "未知"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return address }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            guard addrFamily == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name == "en1" else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            // `String(cString:)` 在 macOS 26 已废弃。地址缓冲区是定长且以 NUL 结尾的，
            // 按 CChar 逐个转成字节再解码，不用碰不安全指针。
            address = String(
                decoding: hostname.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
            break
        }
        return address
    }

    /// 获取公网 IP
    ///
    /// 默认实现，仅在「显示公网 IP」开着时才会被调用（见 `refresh()`）。
    private static func publicIPFromNetwork() async -> String? {
        guard let url = URL(string: "https://api.ipify.org") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// 获取 DNS 服务器
    private func getDNSServers() -> [String] {
        // 解析规则是纯逻辑，见 ResolvConf；这里只负责把文件读进来
        guard let resolv = try? String(contentsOfFile: "/etc/resolv.conf", encoding: .utf8) else {
            return []
        }
        return ResolvConf.dnsServers(in: resolv)
    }
}
