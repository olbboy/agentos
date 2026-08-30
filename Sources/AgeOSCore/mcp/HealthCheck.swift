import Foundation

/// Health-check MCP stdio: spawn → initialize → tools/list → đo latency + schema tokens.
/// Cam kết process-hygiene: LUÔN terminate (SIGTERM → 2s → SIGKILL) — không để mồ côi.
public enum HealthCheck {
    public struct Report: Sendable, Codable {
        public var ok: Bool
        public var latencyMs: Int
        public var toolCount: Int
        /// Ước lượng token schema tools (chars/4 — hệ số spike, ±20%).
        public var schemaTokens: Int
        public var serverInfo: String?
        public var error: String?
        public var stderrTail: String?
    }

    /// Chạy đồng bộ (CLI one-shot). `timeout` cho TOÀN bộ flow.
    public static func run(_ launch: McpServerModel.Launch, timeout: TimeInterval = 15) -> Report {
        guard launch.transport == .stdio, let command = launch.command else {
            return Report(ok: false, latencyMs: 0, toolCount: 0, schemaTokens: 0,
                          error: "MVP only health-checks the stdio transport (http servers are skipped)")
        }

        let process = Process()
        // Resolve command qua /usr/bin/env để ăn PATH (npx, uvx, binary tuyệt đối đều chạy).
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + launch.args
        var env = ProcessInfo.processInfo.environment
        for (k, v) in launch.env { env[k] = v }
        process.environment = env

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        // Gom stdout theo dòng bằng readabilityHandler + semaphore báo mỗi dòng mới.
        let collector = LineCollector()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                collector.markEOF() // server đóng stdout (crash/thoát) → fail nhanh, khỏi đợi hết timeout
            } else {
                collector.feed(data)
            }
        }
        let stderrBox = DataBox()
        stderr.fileHandleForReading.readabilityHandler = { handle in
            stderrBox.append(handle.availableData)
        }

        defer {
            // Dọn process bất kể kết quả — tuân process-management rules.
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            if process.isRunning {
                process.terminate() // SIGTERM
                let deadline = Date().addingTimeInterval(2)
                while process.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
            try? stdin.fileHandleForWriting.close()
        }

        let started = Date()
        do {
            try process.run()
        } catch {
            return Report(ok: false, latencyMs: 0, toolCount: 0, schemaTokens: 0,
                          error: "Cannot spawn '\(command)': \(error)")
        }
        let deadline = started.addingTimeInterval(timeout)

        func send(_ json: String) {
            stdin.fileHandleForWriting.write(Data((json + "\n").utf8))
        }
        func readResponse(id: Int) -> [String: Any]? {
            while Date() < deadline {
                if let line = collector.nextLine(waitUntil: deadline) {
                    guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                        continue // log line không phải JSON → bỏ qua
                    }
                    if let rid = obj["id"] as? Int, rid == id { return obj }
                    // notification/response khác → bỏ qua, đọc tiếp
                } else if !process.isRunning {
                    return nil
                }
            }
            return nil
        }

        send(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"ageos-health","version":"0.1.0"}}}"#)
        guard let initResp = readResponse(id: 1), let initResult = initResp["result"] as? [String: Any] else {
            let tail = String(data: stderrBox.snapshot(), encoding: .utf8)?.suffix(300)
            return Report(ok: false, latencyMs: Int(Date().timeIntervalSince(started) * 1000),
                          toolCount: 0, schemaTokens: 0,
                          error: "initialize did not respond within \(Int(timeout))s, or returned an error",
                          stderrTail: tail.map(String.init))
        }
        let initLatency = Int(Date().timeIntervalSince(started) * 1000)
        let serverInfo = (initResult["serverInfo"] as? [String: Any])
            .flatMap { info in (info["name"] as? String).map { "\($0) \(info["version"] as? String ?? "")" } }

        send(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        send(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        guard let toolsResp = readResponse(id: 2),
              let toolsResult = toolsResp["result"] as? [String: Any],
              let tools = toolsResult["tools"] as? [[String: Any]] else {
            let tail = String(data: stderrBox.snapshot(), encoding: .utf8)?.suffix(300)
            return Report(ok: false, latencyMs: initLatency, toolCount: 0, schemaTokens: 0,
                          serverInfo: serverInfo, error: "tools/list did not respond",
                          stderrTail: tail.map(String.init))
        }
        let schemaChars = (try? JSONSerialization.data(withJSONObject: tools))?.count ?? 0
        return Report(ok: true, latencyMs: initLatency, toolCount: tools.count,
                      schemaTokens: schemaChars / 4, serverInfo: serverInfo, error: nil, stderrTail: nil)
    }
}

/// Hộp Data thread-safe cho readabilityHandler (chạy trên thread nền).
final class DataBox: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ d: Data) {
        lock.lock(); data.append(d); lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock(); defer { lock.unlock() }
        return data
    }
}

/// Gom bytes thành dòng, cho phép chờ dòng kế với deadline (thread-safe).
final class LineCollector: @unchecked Sendable {
    private var buffer = Data()
    private var lines: [String] = []
    private let lock = NSCondition()

    private var eof = false

    func markEOF() {
        lock.lock()
        eof = true
        lock.signal()
        lock.unlock()
    }

    func feed(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffer.append(data)
        while let nl = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer.prefix(upTo: nl)
            buffer.removeSubrange(...nl)
            if let s = String(data: lineData, encoding: .utf8), !s.isEmpty {
                lines.append(s)
            }
        }
        lock.signal()
        lock.unlock()
    }

    func nextLine(waitUntil deadline: Date) -> String? {
        lock.lock()
        defer { lock.unlock() }
        while lines.isEmpty && !eof && Date() < deadline {
            // Chờ theo nhịp ngắn để còn thoát khi process chết mà không signal.
            _ = lock.wait(until: min(deadline, Date().addingTimeInterval(0.2)))
        }
        return lines.isEmpty ? nil : lines.removeFirst()
    }
}
