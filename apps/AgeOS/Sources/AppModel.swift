import Foundation
import Observation
import AgeOSCore

/// The root view model — the only bridge between SwiftUI and AgeOSCore (no IPC, it
/// calls the library directly). Heavy work runs detached, then updates state on MainActor.
@MainActor
@Observable
final class AppModel {
    // MARK: - State for the screens

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
    /// FSEvents saw an unexpected change inside an agent folder → suggest doctor.
    private(set) var suggestsDoctor = false
    private(set) var lastSyncAt: Date?

    private let watcher = FsEventsWatcher()

    // MARK: - Core access (built fresh each time — structs are cheap, and stale state is not)

    nonisolated private func makeEngine() throws -> SyncEngine {
        try SyncEngine(home: AgeOSHome())
    }

    nonisolated private func makeAdapters() throws -> AdapterRegistry {
        try AdapterRegistry(home: AgeOSHome())
    }

    // MARK: - Lifecycle

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
                self.skillTokenEstimates = self.recomputeTokenEstimates(loadedSkills)
                self.sources = loadedSources
                self.adapters = registry.adapters
                self.lock = loadedLock
                self.mcpServers = loadedMcp
                self.inventory = loadedInventory
                self.recomputeDiagnostics()
            }
        }
    }

    // MARK: - Diagnostics (the shared count)

    /// Every current problem, normalized from Doctor, Scan and the inventory.
    ///
    /// Overview shows counts, Diagnostics shows detail, the menu bar shows a total —
    /// all three read from HERE. Letting each screen aggregate for itself is the
    /// surest way to have them report three different numbers for one machine.
    ///
    /// STORED rather than computed: the linter runs over every skill, so with a
    /// library of ~100 this list easily reaches 150-250 entries. `DiagnosticsView`
    /// reads it four times per render (three severity groups plus the summary bar),
    /// and every change to `busy` triggers another render. Rebuilding it on each read
    /// is pure waste — the same reason `skillTokenEstimates` below is cached.
    private(set) var diagnostics: [DiagnosticItem] = []

    private(set) var attentionSummary: (errors: Int, warnings: Int, info: Int) = (0, 0, 0)

    private func recomputeDiagnostics() {
        diagnostics = DiagnosticsBuilder.build(doctorFindings: doctorFindings,
                                               scanReport: scanReport,
                                               inventory: inventory)
        attentionSummary = (diagnostics.filter { $0.severity == .error }.count,
                            diagnostics.filter { $0.severity == .warning }.count,
                            diagnostics.filter { $0.severity == .info }.count)
    }

    /// The shared axis for EVERY `RatioMeter` drawing budget, on Overview or on Budget.
    ///
    /// It lives here rather than being duplicated per view: its whole purpose is that
    /// the two screens draw on the SAME scale. If each view kept its own copy of the
    /// formula, that would hold only until someone edited one — nothing enforces it.
    ///
    /// Thresholds go into the `max` too, so an agent under its threshold can still see
    /// how far it is from it, instead of the highest agent always filling the bar.
    var budgetScaleMax: Int {
        max(budgets.map(\.totalTokens).max() ?? 0,
            budgets.compactMap(\.warnThreshold).max() ?? 0)
    }

    /// Whether diagnostics have ever run. Different from "ran and came back clean" —
    /// the Diagnostics screen has to tell those two apart.
    var hasRunDiagnostics: Bool {
        scanReport != nil || !doctorFindings.isEmpty
    }

    // MARK: - Target Matrix

    /// Adapters shown in the matrix: detected, and supporting skills.
    var matrixAdapters: [AdapterSpec] {
        adapters.filter { $0.isDetected() && $0.skills != nil }
    }

    /// Estimated tokens per skill, computed ONCE when `skills` changes rather than on
    /// every row render. The formula is cheap, but calling it for every row while
    /// scrolling is still waste for nothing.
    private(set) var skillTokenEstimates: [String: Int] = [:]

    private func recomputeTokenEstimates(_ rows: [IndexDB.SkillRow]) -> [String: Int] {
        var table: [String: Int] = [:]
        for row in rows {
            // truncateChars 0 = no truncation: this is a general figure, not tied to an adapter.
            table[row.id] = BudgetMeter.skillTokens(name: row.name,
                                                    description: row.description,
                                                    truncateChars: 0)
        }
        return table
    }

    /// How many DISTINCT adapters have this skill enabled.
    ///
    /// Not `targets.count`: a key in `targets` is `<adapterId>@global` OR
    /// `<adapterId>@<projectPath>`, so one adapter can hold several entries and
    /// `targets.count` would over-count.
    func enabledAdapterCount(skillId: String) -> Int {
        guard let targets = lock.skills[skillId]?.targets.keys else { return 0 }
        return Set(targets.compactMap { $0.split(separator: "@").first.map(String.init) }).count
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
                throw AgeOSError(.notFound, "Invalid id: \(skillId)")
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
            await MainActor.run {
                self.scanReport = report
                self.recomputeDiagnostics()
            }
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
                await MainActor.run {
                    self.inventory = loadedInventory
                    self.recomputeDiagnostics()
                }
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
                self.recomputeDiagnostics()
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
        lastError = nil // a new action begins — the old error no longer applies
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
