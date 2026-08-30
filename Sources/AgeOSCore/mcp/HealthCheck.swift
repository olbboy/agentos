import Foundation

/// Health-checks an MCP stdio server: spawn → initialize → tools/list → measure latency and schema tokens.
/// A process-hygiene promise: it ALWAYS terminates (SIGTERM → 2s → SIGKILL) — nothing is orphaned.
public enum HealthCheck {
    public struct Report: Sendable, Codable {
        public var ok: Bool
        public var latencyMs: Int
        public var toolCount: Int
        /// An estimate of the tools' schema tokens (chars/4 — the spike factor, ±20%).
        public var schemaTokens: Int
        public var serverInfo: String?
        public var error: String?
        public var stderrTail: String?
    }

    /// Runs synchronously (the CLI is one-shot). `timeout` covers the WHOLE flow.
    public static func run(_ launch: McpServerModel.Launch, timeout: TimeInterval = 15) -> Report {
        guard launch.transport == .stdio, let command = launch.command else {
            return Report(ok: false, latencyMs: 0, toolCount: 0, schemaTokens: 0,
                          error: "MVP only health-checks the stdio transport (http servers are skipped)")
        }

        let process = Process()
        // Resolve the command through /usr/bin/env so PATH applies (npx, uvx and absolute binaries all work).
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + launch.args
        var env = ProcessInfo.processInfo.environment
        for (k, v) in launch.env { env[k] = v }
        process.environment = env

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        // Collect stdout line by line with readabilityHandler, signalling a semaphore per line.
        let collector = LineCollector()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                collector.markEOF() // the server closed stdout (crash or exit) → fail fast instead of waiting out the timeout
            } else {
                collector.feed(data)
            }
        }
        let stderrBox = DataBox()
        stderr.fileHandleForReading.readabilityHandler = { handle in
            stderrBox.append(handle.availableData)
        }

        defer {
            // Clean the process up whatever the outcome — per the process-management rules.
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
                        continue // a log line, not JSON → skip it
                    }
                    if let rid = obj["id"] as? Int, rid == id { return obj }
                    // some other notification or response → skip it and keep reading
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

/// A thread-safe box for Data, for readabilityHandler (which runs on a background thread).
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

/// Collects bytes into lines and lets a caller wait for the next line with a deadline (thread-safe).
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
            // Wait in short beats so we can still bail out when the process dies without signalling.
            _ = lock.wait(until: min(deadline, Date().addingTimeInterval(0.2)))
        }
        return lines.isEmpty ? nil : lines.removeFirst()
    }
}
