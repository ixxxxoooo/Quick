// NetworkService.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation
import Network

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

    /// 获取网络信息
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let localIP = getLocalIP()
        let publicIP = await getPublicIP()
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
            address = String(cString: hostname)
            break
        }
        return address
    }

    /// 获取公网 IP
    private func getPublicIP() async -> String? {
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
        var servers: [String] = []
        if let resolv = try? String(contentsOfFile: "/etc/resolv.conf", encoding: .utf8) {
            for line in resolv.components(separatedBy: "\n") {
                if line.hasPrefix("nameserver") {
                    let parts = line.components(separatedBy: .whitespaces)
                    if parts.count >= 2 { servers.append(parts[1]) }
                }
            }
        }
        return servers
    }
}
