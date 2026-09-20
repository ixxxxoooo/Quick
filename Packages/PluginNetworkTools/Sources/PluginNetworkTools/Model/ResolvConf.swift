// ResolvConf.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// `/etc/resolv.conf` 的解析
///
/// 纯逻辑：把文件内容切成 DNS 服务器地址列表。读文件那一步留在 NetworkService，
/// 这里只处理文本 —— 于是各种畸形行（缺地址、多空格、CRLF）都能用固定样本覆盖，
/// 不必依赖本机当时连在哪个网络上。
public enum ResolvConf {

    /// 解析出 `nameserver` 指令的地址
    ///
    /// 按现状实现：逐行看，行首是 `nameserver` 才算，取空白分隔后的第 2 段。
    /// 因此「指令名后面必须紧跟空白」是隐含前提，缺少地址的裸指令会被跳过。
    ///
    /// - Parameter content: 文件全文
    /// - Returns: 按出现顺序排列的 DNS 地址（可能含空串，见已知缺陷）
    public static func dnsServers(in content: String) -> [String] {
        var servers: [String] = []
        for line in content.components(separatedBy: "\n") {
            // 用行首前缀而不是 contains：注释里的
            // `# nameserver 1.1.1.1` 不该被当成配置
            if line.hasPrefix("nameserver") {
                let parts = line.components(separatedBy: .whitespaces)
                if parts.count >= 2 { servers.append(parts[1]) }
            }
        }
        return servers
    }
}
