import Foundation
import Observation
import AgeOSCore

/// Root ViewModel — cầu nối duy nhất giữa SwiftUI và AgeOSCore (không IPC,
/// gọi thẳng lib). Mọi việc nặng chạy detached rồi cập nhật state trên MainActor.
@MainActor
@Observable
final class AppModel {
    // MARK: - State cho các màn

    private(set) var skills: [IndexDB.SkillRow] = []
    private(set) var sources: [SourceDescriptor] = []
    private(set) var adapters: [AdapterSpec] = []
    private(set) var lock = Lockfile()
    private(set) var inventory: EffectiveLoadScanner.Inventory?
    private(set) var scanReport: ScanEngine.ScanReport?
    private(set) var budgets: [BudgetMeter.Report] = []
    private(set) var mcpServers: [McpServerModel] = []
    private(set) var healthByName: [String: HealthCheck.Report] = [:]
    private(set) var doctorFindings: [Doctor.Finding] = []

    var lastError: String?
    private(set) var busy = false
    /// FSEvents thấy thay đổi ngoài ý muốn trong thư mục agent → gợi ý doctor.
    private(set) var suggestsDoctor = false
    private(set) var lastSyncAt: Date?

    private let watcher = FsEventsWatcher()

    // MARK: - Core access (tạo mới mỗi lần dùng — struct rẻ, tránh giữ state cũ)

    nonisolated private func makeEngine() throws -> SyncEngine {
        try SyncEngine(home: AgeOSHome())
    }

    nonisolated private func makeAdapters() throws -> AdapterRegistry {
        try AdapterRegistry(home: AgeOSHome())
    }

    // MARK: - Vòng đời

    func start() async {
        await refreshAll()
        startWatching()
    }

    func refreshAll() async {
        await run { [self] in
            let engine = try makeEngine()
            let registry = try makeAdapters()
            let loadedSkills = try engine.index.listSkills()
            let loadedSources = try engine.registry.load()
            let loadedLock = try Lockfile.load(from: engine.home.lockfilePath)
            let loadedMcp = try McpLibrary(home: engine.home).load()
            let scanner = EffectiveLoadScanner(adapters: registry)
            let loadedInventory = scanner.scan()
            await MainActor.run {
                self.skills = loadedSkills
                self.sources = loadedSources
                self.adapters = registry.adapters
                self.lock = loadedLock
                self.mcpServers = loadedMcp
                self.inventory = loadedInventory
            }
        }
    }

    // MARK: - Target Matrix

    /// Adapter hiển thị trong matrix: phát hiện được + hỗ trợ skills.
    var matrixAdapters: [AdapterSpec] {
        adapters.filter { $0.isDetected() && $0.skills != nil }
    }

    func isEnabled(skillId: String, adapterId: String) -> Bool {
        lock.skills[skillId]?.targets.keys.contains { $0.hasPrefix("\(adapterId)@") } ?? false
    }

    func toggle(skillId: String, adapterId: String, enabled: Bool) async {
        await run { [self] in
            let engine = try makeEngine()
            let registry = try makeAdapters()
            let linkEngine = LinkEngine(home: engine.home, store: engine.store, adapters: registry)
            guard let ref = SkillRef(id: skillId) else {
                throw AgeOSError(.notFound, "Id không hợp lệ: \(skillId)")
            }
            if enabled {
                let row = try engine.index.resolveSkill(query: skillId)
                _ = try linkEngine.enable(ref, sourceId: row.sourceId, adapterId: adapterId)
            } else {
                _ = try linkEngine.disable(ref, adapterId: adapterId)
            }
            let newLock = try Lockfile.load(from: engine.home.lockfilePath)
            await MainActor.run { self.lock = newLock }
        }
    }

    // MARK: - Actions

    func addSource(_ input: String) async {
        await run { [self] in
            let engine = try makeEngine()
            _ = try await engine.addSource(input)
        }
        if lastError == nil { await refreshAll() }
    }

    func syncAll() async {
        await run { [self] in
            let engine = try makeEngine()
            _ = try await engine.sync()
            await MainActor.run { self.lastSyncAt = Date() }
        }
        if lastError == nil { await refreshAll() }
    }

    func runScan() async {
        await run { [self] in
            let engine = try makeEngine()
            let registry = try makeAdapters()
            let report = try ScanEngine(home: engine.home, adapters: registry, index: engine.index).run()
            await MainActor.run { self.scanReport = report }
        }
    }

    func runBudget() async {
        await run { [self] in
            let engine = try makeEngine()
            let registry = try makeAdapters()
            let index = engine.index
            let meter = BudgetMeter(adapters: registry,
                                    mcpSchemaTokens: { try? index.mcpSchemaTokens(entryName: $0) })
            var reports: [BudgetMeter.Report] = []
            for adapter in registry.detected() where adapter.skills != nil || adapter.mcp != nil {
                reports.append(try meter.compute(adapterId: adapter.id))
            }
            let final = reports
            await MainActor.run { self.budgets = final }
        }
    }

    func runAdopt(importSkills: Bool) async -> EffectiveLoadScanner.AdoptReport? {
        busy = true
        defer { busy = false }
        do {
            let report = try await Task.detached(priority: .userInitiated) { [self] () -> EffectiveLoadScanner.AdoptReport? in
                let engine = try makeEngine()
                let registry = try makeAdapters()
                let scanner = EffectiveLoadScanner(adapters: registry)
                let adoptReport = importSkills
                    ? try await scanner.adoptImport(home: engine.home, engine: engine)
                    : nil
                let loadedInventory = scanner.scan()
                await MainActor.run { self.inventory = loadedInventory }
                return adoptReport
            }.value
            lastError = nil
            if importSkills { await refreshAll() }
            return report
        } catch let error as AgeOSError {
            lastError = error.description
            return nil
        } catch {
            lastError = "\(error)"
            return nil
        }
    }

    func runDoctor(fix: Bool) async {
        await run { [self] in
            let engine = try makeEngine()
            let registry = try makeAdapters()
            let findings = try Doctor(home: engine.home, store: engine.store, adapters: registry).run(fix: fix)
            await MainActor.run {
                self.doctorFindings = findings
                self.suggestsDoctor = false
            }
        }
        if fix { await refreshAll() }
    }

    func healthCheck(serverQuery: String) async {
        await run { [self] in
            let engine = try makeEngine()
            let registry = try makeAdapters()
            let manager = McpManager(home: engine.home, adapters: registry)
            let report = try manager.health(query: serverQuery)
            if let model = try? manager.library.find(serverQuery) {
                try? engine.index.recordMcpHealth(entryName: model.name, report: report)
                await MainActor.run { self.healthByName[model.name] = report }
            }
        }
    }

    func mcpToggle(serverQuery: String, adapterId: String, enabled: Bool, env: [String: String] = [:]) async {
        await run { [self] in
            let engine = try makeEngine()
            let registry = try makeAdapters()
            let manager = McpManager(home: engine.home, adapters: registry)
            if enabled {
                _ = try manager.enable(query: serverQuery, adapterId: adapterId, envOverrides: env)
            } else {
                _ = try manager.disable(query: serverQuery, adapterId: adapterId)
            }
            let newLock = try Lockfile.load(from: engine.home.lockfilePath)
            await MainActor.run { self.lock = newLock }
        }
    }

    func mcpIsEnabled(serverId: String, adapterId: String) -> Bool {
        lock.mcpServers[serverId]?.targets.keys.contains { $0.hasPrefix("\(adapterId)@") } ?? false
    }

    // MARK: - FSEvents

    private func startWatching() {
        let paths = matrixAdapters.compactMap { adapter -> String? in
            guard let skills = adapter.skills else { return nil }
            let url = AgeOSHome.expand(skills.globalPath)
            return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
        }
        guard !paths.isEmpty else { return }
        watcher.onChange = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.suggestsDoctor = true
                await self.refreshAll()
            }
        }
        watcher.start(paths: paths)
    }

    // MARK: - Helpers

    private func run(_ work: @escaping @Sendable () async throws -> Void) async {
        busy = true
        lastError = nil // action mới bắt đầu — lỗi cũ hết hiệu lực
        defer { busy = false }
        do {
            try await Task.detached(priority: .userInitiated) { try await work() }.value
        } catch let error as AgeOSError {
            lastError = error.description
        } catch {
            lastError = "\(error)"
        }
    }
}
