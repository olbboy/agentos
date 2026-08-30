import Foundation

/// Điều phối MCP: add (registry/.mcpb/manual) → enable vào client (backup + parse-merge)
/// → health → disable/restore. Mọi đường ghi config đi qua đúng một chỗ này.
public struct McpManager: Sendable {
    public let home: AgeOSHome
    public let adapters: AdapterRegistry
    public let library: McpLibrary
    let warningSink: (@Sendable (String) -> Void)?

    public init(home: AgeOSHome, adapters: AdapterRegistry,
                warningSink: (@Sendable (String) -> Void)? = nil) {
        self.home = home
        self.adapters = adapters
        self.library = McpLibrary(home: home)
        self.warningSink = warningSink
    }

    func writer(for format: AdapterSpec.ConfigFormat) -> any ConfigWriter {
        switch format {
        case .json:
            return JsonConfigWriter()
        case .toml:
            var w = TomlConfigWriter()
            w.onWarning = warningSink
            return w
        }
    }

    /// Resolve file config theo adapter + scope.
    func configFile(adapter: AdapterSpec, project: URL?) throws -> (file: URL, scope: String, mcp: AdapterSpec.McpBlock) {
        guard let mcp = adapter.mcp else {
            throw AgeOSError(.unsupported, "Adapter '\(adapter.id)' không hỗ trợ MCP",
                             remedy: "Xem `ageos targets list` — cột mcp")
        }
        if let project {
            guard let projectConfig = mcp.projectConfigPath else {
                throw AgeOSError(.unsupported, "Adapter '\(adapter.id)' không có config MCP scope project",
                                 remedy: "Enable global (bỏ --project)")
            }
            return (project.appendingPathComponent(projectConfig), "project", mcp)
        }
        return (AgeOSHome.expand(mcp.configPath), "global", mcp)
    }

    public struct McpOutcome: Sendable, Codable {
        public var serverId: String
        public var entryName: String
        public var adapterId: String
        public var scope: String
        public var configPath: String
        public var backupPath: String?
        public var sensitiveEnv: [String]
        public var note: String?
    }

    // MARK: - Enable

    public func enable(query: String, adapterId: String, project: URL? = nil,
                       envOverrides: [String: String] = [:]) throws -> McpOutcome {
        try LockfileMutex.withExclusiveLock(home: home) {
            try enableLocked(query: query, adapterId: adapterId, project: project, envOverrides: envOverrides)
        }
    }

    private func enableLocked(query: String, adapterId: String, project: URL?,
                              envOverrides: [String: String]) throws -> McpOutcome {
        var model = try library.find(query)
        let adapter = try adapters.adapter(id: adapterId)
        let (file, scope, mcp) = try configFile(adapter: adapter, project: project)

        for (k, v) in envOverrides { model.launch.env[k] = v }
        let missing = model.missingRequiredEnv()
        guard missing.isEmpty else {
            let names = missing.map(\.name).joined(separator: ", ")
            throw AgeOSError(.conflict, "Thiếu env bắt buộc cho \(model.id): \(names)",
                             remedy: "Truyền qua --env \(missing[0].name)=<giá trị> (lặp lại cho từng biến)")
        }

        let writerImpl = writer(for: mcp.format)
        let lock = try Lockfile.load(from: home.lockfilePath)
        let key = Lockfile.targetKey(adapter: adapterId, projectPath: project?.path)
        let owned = lock.mcpServers[model.id]?.targets[key] != nil
        if try writerImpl.hasEntry(name: model.name, keyPath: mcp.keyPath, in: file) && !owned {
            throw AgeOSError(.conflict, "Config \(file.lastPathComponent) đã có entry '\(model.name)' KHÔNG do AgeOS quản lý",
                             remedy: "Đổi tên server (`ageos mcp add --manual`) hoặc gỡ entry tay đó nếu muốn AgeOS quản lý")
        }

        let backup = try ConfigBackup.backup(file, home: home)
        try writerImpl.upsertEntry(name: model.name, launch: model.launch, keyPath: mcp.keyPath, in: file)

        var lockAfter = try Lockfile.load(from: home.lockfilePath)
        var entry = lockAfter.mcpServers[model.id]
            ?? .init(source: model.source, version: model.version, sensitiveEnv: model.sensitiveEnvKeys)
        entry.version = model.version
        entry.sensitiveEnv = model.sensitiveEnvKeys
        entry.targets[key] = .init(scope: scope, linkMode: .config, path: file.path)
        lockAfter.mcpServers[model.id] = entry
        try lockAfter.save(to: home.lockfilePath)
        try library.upsert(model) // nhớ env đã điền (plaintext MVP — Keychain v1.1)

        var note: String?
        if !model.sensitiveEnvKeys.isEmpty {
            note = "env nhạy cảm (\(model.sensitiveEnvKeys.joined(separator: ", "))) đang ở PLAINTEXT trong config client — Keychain là milestone v1.1"
        }
        return McpOutcome(serverId: model.id, entryName: model.name, adapterId: adapterId,
                          scope: scope, configPath: file.path, backupPath: backup?.path,
                          sensitiveEnv: model.sensitiveEnvKeys, note: note)
    }

    // MARK: - Disable

    public func disable(query: String, adapterId: String, project: URL? = nil) throws -> McpOutcome {
        try LockfileMutex.withExclusiveLock(home: home) {
            try disableLocked(query: query, adapterId: adapterId, project: project)
        }
    }

    private func disableLocked(query: String, adapterId: String, project: URL?) throws -> McpOutcome {
        let model = try library.find(query)
        let adapter = try adapters.adapter(id: adapterId)
        let (file, scope, mcp) = try configFile(adapter: adapter, project: project)

        var lock = try Lockfile.load(from: home.lockfilePath)
        let key = Lockfile.targetKey(adapter: adapterId, projectPath: project?.path)
        guard var entry = lock.mcpServers[model.id], entry.targets[key] != nil else {
            throw AgeOSError(.notFound, "\(model.id) chưa enable cho '\(key)' theo lockfile",
                             remedy: "Entry trong config nếu có là do user tự thêm — AgeOS không đụng")
        }

        let backup = try ConfigBackup.backup(file, home: home)
        try writer(for: mcp.format).removeEntry(name: model.name, keyPath: mcp.keyPath, in: file)

        entry.targets.removeValue(forKey: key)
        if entry.targets.isEmpty {
            lock.mcpServers.removeValue(forKey: model.id)
        } else {
            lock.mcpServers[model.id] = entry
        }
        try lock.save(to: home.lockfilePath)

        return McpOutcome(serverId: model.id, entryName: model.name, adapterId: adapterId,
                          scope: scope, configPath: file.path, backupPath: backup?.path,
                          sensitiveEnv: [], note: nil)
    }

    // MARK: - Remove khỏi library

    /// Gỡ hẳn model khỏi library. TỪ CHỐI khi server còn enabled ở bất kỳ client nào
    /// (lockfile còn targets) — buộc disable trước để không mồ côi entry trong config client.
    public func removeFromLibrary(query: String) throws -> McpServerModel {
        let model = try library.find(query)
        let lock = try Lockfile.load(from: home.lockfilePath)
        if let entry = lock.mcpServers[model.id], !entry.targets.isEmpty {
            let targets = entry.targets.keys.sorted().joined(separator: ", ")
            throw AgeOSError(.conflict, "\(model.id) còn enabled ở: \(targets)",
                             remedy: "Disable trước: `ageos mcp disable \(model.name) --target <adapter>` rồi remove lại")
        }
        var all = try library.load()
        all.removeAll { $0.id == model.id }
        try library.save(all)
        return model
    }

    // MARK: - Health

    public func health(query: String, timeout: TimeInterval = 15) throws -> HealthCheck.Report {
        let model = try library.find(query)
        return HealthCheck.run(model.launch, timeout: timeout)
    }
}
