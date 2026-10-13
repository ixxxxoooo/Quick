// PingRunner.swift
// Quick — 原生 macOS 效率启动器
// @author ygw

import Foundation

/// 一次 Ping 的结果
enum PingOutcome: Equatable, Sendable {
    /// 正常结束（含 100% 丢包：那也是一个有效结论）
    case finished(summary: PingSummary, rawOutput: String)
    /// 没跑起来或输出读不懂（例如主机名解析失败）
    case failed(message: String)
}

/// 调用 `/sbin/ping`
///
/// 路径写死、参数走数组而不是 shell，目标须先过 `PingTarget.validated`。
/// 可取消：任务被取消时终止子进程，不留孤儿 `ping`。
enum PingRunner {

    nonisolated static func run(host: String, count: Int, timeoutSeconds: Int) async -> PingOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        // -c 包数；-W 每个包等回应的毫秒数；-t 整体兜底秒数（发包间隔 1 秒 + 最后一个包的等待）
        process.arguments = [
            "-c", String(count), "-W", String(timeoutSeconds * 1000),
            "-t", String(count + timeoutSeconds), host,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<PingOutcome, Never>) in
                // 读取与等待都是阻塞调用，放到后台队列，不占协作线程池
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(returning: .failed(message: "无法启动 ping：\(error.localizedDescription)"))
                        return
                    }
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let output = String(decoding: data, as: UTF8.self)
                    if let summary = PingParser.parse(output) {
                        continuation.resume(returning: .finished(summary: summary, rawOutput: output))
                    } else {
                        let line = output.trimmingCharacters(in: .whitespacesAndNewlines)
                            .components(separatedBy: .newlines).last ?? ""
                        continuation.resume(
                            returning: .failed(message: line.isEmpty ? "ping 没有输出结果" : line))
                    }
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}
