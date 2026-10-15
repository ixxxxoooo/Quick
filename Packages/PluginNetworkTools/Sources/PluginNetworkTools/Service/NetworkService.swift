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

    /// Ping 的界面状态
    enum PingState: Equatable {
        case idle
        case running(host: String)
        case finished(host: String, summary: PingSummary, rawOutput: String)
        case failed(host: String, message: String)
    }

    private(set) var networkInfo: NetworkInfo?
    private(set) var isLoading = false
    private(set) var pingState: PingState = .idle

    private let log = QuickLog.plugin("networktools")
    private var pingTask: Task<Void, Never>?
    /// 刷新的代数：旧一轮刷新晚回来时不覆盖新一轮的结果
    private var refreshGeneration = 0

    /// 公网 IP 的查法（可注入：测试用它替掉真实请求）
    private let fetchPublicIP: @MainActor () async -> String?

    /// - Parameter fetchPublicIP: 查询公网 IP 的实现；默认走网络，测试注入固定值
    init(fetchPublicIP: (@MainActor () async -> String?)? = nil) {
        self.fetchPublicIP = fetchPublicIP ?? { await Self.publicIPFromNetwork() }
    }

    /// 设置页「显示公网 IP」的当前取值
    ///
    /// 视图和刷新都看它，现读而不是 init 时读一次 —— 设置页可以在运行期改。
    var showsExternalIP: Bool {
        PluginDefaults.isEnabled(PluginSettingKey.NetworkTools.showExternalIP, default: true)
    }

    /// 获取网络信息
    ///
    /// 可重入：再次调用会让较早的一轮作废（结果不落地）；任务被取消时同样丢弃结果。
    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        isLoading = true
        defer { if generation == refreshGeneration { isLoading = false } }

        let localIP = getLocalIP()

        // 开关关掉时不查公网 IP：设置页承诺的是「不展示」，而为了不展示去发一次请求
        // 既没有意义，也白白把本机 IP 告诉了第三方接口
        let publicIP = showsExternalIP ? await fetchPublicIP() : nil

        let dns = getDNSServers()

        guard generation == refreshGeneration, !Task.isCancelled else { return }
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
    /// 超时取设置页的「超时时间」；失败写日志而不是静默吞掉。
    private static func publicIPFromNetwork() async -> String? {
        guard let url = URL(string: "https://api.ipify.org") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = TimeInterval(NetworkToolsPreferences.timeout())
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            // 只收 IP 字面量：被运营商劫持时返回的可能是一整页 HTML
            guard let text, !text.isEmpty, text.count <= 45,
                text.allSatisfy({ $0.isHexDigit || $0 == "." || $0 == ":" })
            else { return nil }
            return text
        } catch {
            QuickLog.plugin("networktools").error("查询公网 IP 失败：\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Ping

    /// 开始 Ping；上一次还没结束就先取消它
    ///
    /// - Parameter rawHost: 用户输入，会先校验；不合法直接给出失败状态，不起进程
    func startPing(host rawHost: String) {
        pingTask?.cancel()
        guard let host = PingTarget.validated(rawHost) else {
            pingState = .failed(host: rawHost, message: "请输入有效的主机名或 IP 地址")
            return
        }
        let count = NetworkToolsPreferences.pingCount()
        let timeout = NetworkToolsPreferences.timeout()
        pingState = .running(host: host)
        log.notice("开始 ping \(host, privacy: .private)，\(count) 次，超时 \(timeout) 秒")
        pingTask = Task { [weak self] in
            let outcome = await PingRunner.run(host: host, count: count, timeoutSeconds: timeout)
            guard !Task.isCancelled, let self else { return }
            switch outcome {
            case let .finished(summary, rawOutput):
                pingState = .finished(host: host, summary: summary, rawOutput: rawOutput)
            case let .failed(message):
                log.error("ping 失败：\(message, privacy: .public)")
                pingState = .failed(host: host, message: message)
            }
        }
    }

    /// 取消正在进行的 Ping（视图消失时调用）
    func cancelPing() {
        pingTask?.cancel()
        pingTask = nil
        if case .running = pingState { pingState = .idle }
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
