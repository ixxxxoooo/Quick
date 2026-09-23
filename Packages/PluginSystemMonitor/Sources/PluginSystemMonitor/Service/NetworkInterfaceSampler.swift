// NetworkInterfaceSampler.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Darwin
import Foundation

/// 枚举本机网络接口与字节计数器
enum NetworkInterfaceSampler {

    /// 当前接口列表（跳过 loopback）
    nonisolated static func interfaces() -> [NetworkInterfaceInfo] {
        var addressPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressPointer) == 0, let first = addressPointer else { return [] }
        defer { freeifaddrs(first) }

        var grouped: [String: (up: Bool, addresses: [String])] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let iface = cursor {
            defer { cursor = iface.pointee.ifa_next }
            let name = String(cString: iface.pointee.ifa_name)
            guard !name.hasPrefix("lo") else { continue }

            let flags = Int32(iface.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0
            var entry = grouped[name] ?? (false, [])
            entry.up = entry.up || isUp

            if let addr = iface.pointee.ifa_addr {
                let family = addr.pointee.sa_family
                if family == UInt8(AF_INET) || family == UInt8(AF_INET6) {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let status = getnameinfo(
                        addr,
                        socklen_t(addr.pointee.sa_len),
                        &host,
                        socklen_t(host.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    if status == 0 {
                        let ip = String(decoding: host.prefix { $0 != 0 }.map(UInt8.init), as: UTF8.self)
                        if !entry.addresses.contains(ip) {
                            entry.addresses.append(ip)
                        }
                    }
                }
            }
            grouped[name] = entry
        }

        return grouped.keys.sorted().map { name in
            let info = grouped[name]!
            return NetworkInterfaceInfo(
                id: name,
                name: name,
                addresses: info.addresses,
                isUp: info.up
            )
        }
    }

    /// 接口字节计数器（用于吞吐）
    nonisolated static func counters(now: Date = Date()) -> [NetworkCounterSample] {
        var addressPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressPointer) == 0, let first = addressPointer else { return [] }
        defer { freeifaddrs(first) }

        var samples: [String: NetworkCounterSample] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let iface = cursor {
            defer { cursor = iface.pointee.ifa_next }
            let name = String(cString: iface.pointee.ifa_name)
            guard !name.hasPrefix("lo") else { continue }
            guard let addr = iface.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) else {
                continue
            }
            guard let data = iface.pointee.ifa_data else { continue }

            let ifdata = data.assumingMemoryBound(to: if_data.self).pointee
            samples[name] = NetworkCounterSample(
                interface: name,
                bytesIn: UInt64(ifdata.ifi_ibytes),
                bytesOut: UInt64(ifdata.ifi_obytes),
                timestamp: now
            )
        }
        return Array(samples.values)
    }
}
