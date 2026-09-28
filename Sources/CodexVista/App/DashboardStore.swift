import Foundation
import Observation

enum DashboardLoadState: Sendable {
    case loading
    case loaded(DashboardSnapshot, SourceSummary)
    case empty(SourceSummary)
    case stale(DashboardSnapshot, SourceSummary, String)
    case failed(String)
    case unsupported(String)
}

enum SourceHealth: String, Sendable {
    case connected
    case missing
    case degraded
    case unsupported
}

struct SourceSummary: Sendable {
    let cli: SourceHealth
    let desktop: SourceHealth
    let index: SourceHealth
    let lastSuccessfulRefresh: Date?
}

enum DashboardDataResult: Sendable {
    case loaded(DashboardSnapshot, SourceSummary)
    case empty(SourceSummary)
    case stale(DashboardSnapshot, SourceSummary, String)
    case unsupported(String)
}

protocol DashboardDataClient: Sendable {
    func loadCached() async throws -> DashboardDataResult
    func refreshUsage() async throws -> DashboardDataResult
    func backfillHistory() async throws -> DashboardDataResult
    func rebuildFromLocalData(
        progress: @escaping CodexImportProgressHandler
    ) async throws -> DashboardDataResult
}

extension DashboardDataClient {
    func rebuildFromLocalData() async throws -> DashboardDataResult {
        try await rebuildFromLocalData(progress: { _ in })
    }
}

actor LiveDashboardDataClient: DashboardDataClient {
    private let codexRootURL: URL
    private let store: UsageStore
    private let importer: CodexImporter
    private let sourceDiscovery: CodexSourceDiscovery
    private let queryService: DashboardQueryService
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private let usageCalendar: Calendar
    private let firstSubscriptionDate: @Sendable () -> Date?
    private let beforeImport: @Sendable (ImportScope) async -> Void
    private let beforeQuery: @Sendable () async -> Void
    private var operationIsRunning = false
    private var operationWaiters: [OperationWaiter] = []

    init(
        codexRootURL: URL,
        databaseURL: URL,
        now: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = .current,
        usageCalendar: Calendar = CodexUsageCalendar.utc,
        fileManager: FileManager = .default,
        firstSubscriptionDate: @escaping @Sendable () -> Date? = { nil },
        beforeImport: @escaping @Sendable (ImportScope) async -> Void = { _ in },
        beforeQuery: @escaping @Sendable () async -> Void = {}
    ) throws {
        try fileManager.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let store = try UsageStore(databaseURL: databaseURL)
        self.codexRootURL = codexRootURL
        self.store = store
        importer = CodexImporter(
            rootURL: codexRootURL,
            store: store,
            calendar: calendar
        )
        sourceDiscovery = CodexSourceDiscovery(fileManager: fileManager)
        queryService = DashboardQueryService(store: store)
        self.now = now
        self.calendar = calendar
        self.usageCalendar = usageCalendar
        self.firstSubscriptionDate = firstSubscriptionDate
        self.beforeImport = beforeImport
        self.beforeQuery = beforeQuery
    }

    func loadCached() async throws -> DashboardDataResult {
        try await acquireOperation()
        defer { releaseOperation() }
        try Task.checkCancellation()
        return try await makeResult(importResult: nil)
    }

    func refreshUsage() async throws -> DashboardDataResult {
        try await acquireOperation()
        defer { releaseOperation() }
        try Task.checkCancellation()
        await beforeImport(.foreground)
        try Task.checkCancellation()
        let importResult = await importer.refresh(scope: .foreground)
        try Task.checkCancellation()
        try store.persistSourceStatus(
            indexHealth: importResult.indexHealth,
            discoveredFileIDs: importResult.discoveredFileIDs,
            issues: importResult.issues,
            processedFileCount: importResult.processedFileCount,
            refreshAtMilliseconds: Int64(now().timeIntervalSince1970 * 1_000)
        )
        return try await makeResult(importResult: importResult)
    }

    func backfillHistory() async throws -> DashboardDataResult {
        try await acquireOperation()
        defer { releaseOperation() }
        try Task.checkCancellation()
        await beforeImport(.history)
        try Task.checkCancellation()
        let importResult = await importer.refresh(scope: .history)
        try Task.checkCancellation()
        try store.persistSourceStatus(
            indexHealth: importResult.indexHealth,
            discoveredFileIDs: importResult.discoveredFileIDs,
            issues: importResult.issues,
            processedFileCount: importResult.processedFileCount
        )
        return try await makeResult(importResult: importResult)
    }

    func rebuildFromLocalData(
        progress: @escaping CodexImportProgressHandler
    ) async throws -> DashboardDataResult {
        try await acquireOperation()
        defer { releaseOperation() }
        try Task.checkCancellation()
        await progress(.resetting)
        await beforeImport(.history)
        try Task.checkCancellation()
        let importResult = await importer.rebuildFromLocalData(progress: progress)
        try Task.checkCancellation()
        let totalFileCount = importResult.discoveredFileIDs?.count
            ?? importResult.processedFileCount + importResult.skippedFileCount
        await progress(.finalizing(total: totalFileCount))
        try store.persistSourceStatus(
            indexHealth: importResult.indexHealth,
            discoveredFileIDs: importResult.discoveredFileIDs,
            issues: importResult.issues,
            processedFileCount: importResult.processedFileCount
        )
        return try await makeResult(importResult: importResult)
    }

    private func acquireOperation() async throws {
        try Task.checkCancellation()
        guard operationIsRunning else {
            operationIsRunning = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                operationWaiters.append(OperationWaiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelOperationWaiter(id: id) }
        }
    }

    private func releaseOperation() {
        guard !operationWaiters.isEmpty else {
            operationIsRunning = false
            return
        }
        operationWaiters.removeFirst().continuation.resume()
    }

    private func cancelOperationWaiter(id: UUID) {
        guard let index = operationWaiters.firstIndex(where: { $0.id == id }) else { return }
        operationWaiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func makeResult(importResult: ImportResult?) async throws -> DashboardDataResult {
        await beforeQuery()
        try Task.checkCancellation()
        let currentDate = now()
        let threadMetadata = sourceDiscovery.threadDashboardMetadata(rootURL: codexRootURL)
        let storedSnapshot = try queryService.snapshot(
            now: currentDate,
            calendar: calendar,
            usageCalendar: usageCalendar,
            firstSubscriptionDate: firstSubscriptionDate(),
            threadTitlesByThreadID: threadMetadata.displayTitlesByThreadID,
            parentThreadIDsByChildThreadID: threadMetadata.parentThreadIDsByChildThreadID,
            childThreadRelationsByChildThreadID: threadMetadata.childThreadRelationsByChildThreadID
        )
        let snapshot = storedSnapshot
        let facts = try store.sourceFacts()
        let summary = SourceSummary(
            cli: facts.hasCLIData ? .connected : .missing,
            desktop: facts.hasDesktopData ? .connected : .missing,
            index: sourceHealth(for: facts.indexHealth),
            lastSuccessfulRefresh: facts.lastSuccessfulRefreshMilliseconds.map {
                Date(timeIntervalSince1970: TimeInterval($0) / 1_000)
            }
        )
        let issues = importResult?.issues ?? []
        let hasUsage = snapshot.totalTokens > 0
        let hasDegradedIndex: Bool
        if case .degraded = facts.indexHealth {
            hasDegradedIndex = true
        } else {
            hasDegradedIndex = false
        }

        if hasUsage {
            if !issues.isEmpty || hasDegradedIndex
                || facts.hasDegradedFiles || facts.hasUnsupportedFiles {
                return .stale(
                    snapshot,
                    summary,
                    "部分数据暂不可用，正在显示已成功读取的数据。"
                )
            }
            return .loaded(snapshot, summary)
        }

        if issues.contains(where: { $0.kind == .unsupportedFormat })
            || facts.hasUnsupportedFiles {
            return .unsupported("Codex 数据格式暂不兼容。")
        }
        if facts.hasDegradedFiles {
            throw LiveDashboardDataError.importFailed
        }
        if issues.contains(where: { issue in
            switch issue.kind {
            case .discovery, .read, .decode, .store: true
            case .index, .unsupportedFormat: false
            }
        }) {
            throw LiveDashboardDataError.importFailed
        }
        return .empty(summary)
    }

    private func sourceHealth(for health: CodexIndexHealth) -> SourceHealth {
        switch health {
        case .available: .connected
        case .missing: .missing
        case .degraded: .degraded
        }
    }
}

private struct OperationWaiter {
    let id: UUID
    let continuation: CheckedContinuation<Void, any Error>
}

private enum LiveDashboardDataError: Error {
    case initializationFailed
    case importFailed
}

private actor UnavailableDashboardDataClient: DashboardDataClient {
    func loadCached() async throws -> DashboardDataResult {
        throw LiveDashboardDataError.initializationFailed
    }

    func refreshUsage() async throws -> DashboardDataResult {
        throw LiveDashboardDataError.initializationFailed
    }

    func backfillHistory() async throws -> DashboardDataResult {
        throw LiveDashboardDataError.initializationFailed
    }

    func rebuildFromLocalData(
        progress: @escaping CodexImportProgressHandler
    ) async throws -> DashboardDataResult {
        throw LiveDashboardDataError.initializationFailed
    }
}

@MainActor
@Observable
final class DashboardStore {
    typealias Sleeper = @Sendable (Duration) async throws -> Void

    private(set) var state: DashboardLoadState = .loading
    private(set) var isRefreshing = false
    private(set) var isRebuildingData = false
    private(set) var rebuildProgress: CodexImportProgress?
    private(set) var isAutomaticRefreshEnabled: Bool
    private(set) var sourceSummary: SourceSummary?

    private let client: any DashboardDataClient
    private let usageRefreshInterval: Duration
    private let sleeper: Sleeper
    private var hasLoadedCached = false
    private var hasStarted = false
    private var publicationRevision: UInt64 = 0
    private var foregroundRevision: UInt64 = 0
    private var startTask: Task<Void, Never>?
    private var inFlightManualRefresh: Task<Void, Never>?
    private var inFlightRefresh: Task<Void, Never>?
    private var inFlightRebuild: Task<Void, Never>?
    private var backfillTask: Task<Void, Never>?
    private var automaticUsageRefreshTask: Task<Void, Never>?

    init(
        client: any DashboardDataClient,
        usageRefreshInterval: Duration = .seconds(60),
        automaticRefreshEnabled: Bool = true,
        sleeper: @escaping Sleeper = { duration in
            try await ContinuousClock().sleep(for: duration)
        }
    ) {
        self.client = client
        self.usageRefreshInterval = usageRefreshInterval
        isAutomaticRefreshEnabled = automaticRefreshEnabled
        self.sleeper = sleeper
    }

    static func live() -> DashboardStore {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codexRoot = home.appendingPathComponent(".codex", isDirectory: true)
        let client: any DashboardDataClient
        do {
            let databaseURL = try AppIdentityMigration.prepareDatabase(
                applicationSupportURL: home.appendingPathComponent("Library/Application Support", isDirectory: true)
            )
            client = try LiveDashboardDataClient(
                codexRootURL: codexRoot,
                databaseURL: databaseURL,
                firstSubscriptionDate: { SubscriptionCyclePreference.load() }
            )
        } catch {
            client = UnavailableDashboardDataClient()
        }
        let automaticRefreshEnabled = UserDefaults.standard.object(
            forKey: AppPreferenceKeys.automaticRefreshEnabled
        ) as? Bool ?? true
        let store = DashboardStore(
            client: client,
            automaticRefreshEnabled: automaticRefreshEnabled
        )
        Task { @MainActor [weak store] in
            await store?.start()
        }
        return store
    }

    static func testHost() -> DashboardStore {
        DashboardStore(
            client: UnavailableDashboardDataClient(),
            automaticRefreshEnabled: false
        )
    }

    var snapshot: DashboardSnapshot? {
        switch state {
        case .loaded(let snapshot, _), .stale(let snapshot, _, _): snapshot
        case .loading, .empty, .failed, .unsupported: nil
        }
    }

    func menuBarLabel(configuration: MenuBarLabelConfiguration) -> String {
        snapshot?.menuBarLabel(configuration: configuration) ?? "CodexVista"
    }

    func start() async {
        if let startTask {
            await startTask.value
            return
        }
        guard !hasStarted else { return }
        hasStarted = true

        let task = Task { @MainActor [weak self] in
            await self?.loadCached()
            await self?.refresh()
            self?.launchBackfill()
            self?.launchAutomaticRefresh()
        }
        startTask = task
        await task.value
        startTask = nil
    }

    func loadCached() async {
        guard !hasLoadedCached else { return }
        hasLoadedCached = true
        do {
            publish(try await client.loadCached())
        } catch {
            state = .failed("无法读取已保存的 CodexVista 数据。")
        }
    }

    func refresh() async {
        if let inFlightManualRefresh {
            await inFlightManualRefresh.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refreshUsage()
        }
        inFlightManualRefresh = task
        await task.value
        inFlightManualRefresh = nil
    }

    func refreshUsage() async {
        if let inFlightRebuild {
            await inFlightRebuild.value
            return
        }
        if let inFlightRefresh {
            await inFlightRefresh.value
            return
        }

        foregroundRevision &+= 1
        isRefreshing = true
        let client = self.client
        let task = Task { @MainActor [weak self, client] in
            do {
                let firstResult = try await client.refreshUsage()
                let result: DashboardDataResult
                if case .stale = firstResult {
                    // A local index or active rollout can be briefly unavailable while Codex
                    // writes it. Confirm once before exposing a partial result to the UI.
                    result = try await client.refreshUsage()
                } else {
                    result = firstResult
                }
                guard !Task.isCancelled else { return }
                self?.publish(result)
            } catch {
                guard !Task.isCancelled else { return }
                self?.publishRefreshFailure()
            }
        }
        inFlightRefresh = task
        await task.value
        inFlightRefresh = nil
        isRefreshing = false
    }

    func rebuildFromLocalData() async {
        if let inFlightRebuild {
            await inFlightRebuild.value
            return
        }
        if let inFlightRefresh {
            await inFlightRefresh.value
            if let inFlightRebuild {
                await inFlightRebuild.value
                return
            }
        }

        backfillTask?.cancel()
        backfillTask = nil
        foregroundRevision &+= 1
        publicationRevision &+= 1
        isRebuildingData = true
        rebuildProgress = .resetting
        sourceSummary = nil
        state = .loading

        let client = self.client
        let task = Task { @MainActor [weak self, client] in
            let progressHandler: CodexImportProgressHandler = { [weak self] progress in
                await self?.updateRebuildProgress(progress)
            }
            do {
                let result = try await client.rebuildFromLocalData(progress: progressHandler)
                guard !Task.isCancelled else { return }
                self?.publish(result)
            } catch {
                guard !Task.isCancelled else { return }
                self?.publicationRevision &+= 1
                self?.state = .failed("无法重新抓取 Codex 本地数据，请稍后重试。")
            }
        }
        inFlightRebuild = task
        await task.value
        inFlightRebuild = nil
        isRebuildingData = false
        rebuildProgress = nil
    }

    private func updateRebuildProgress(_ progress: CodexImportProgress) {
        guard isRebuildingData else { return }
        rebuildProgress = progress
    }

    func setAutomaticRefreshEnabled(_ isEnabled: Bool) {
        guard isAutomaticRefreshEnabled != isEnabled else { return }
        isAutomaticRefreshEnabled = isEnabled

        if isEnabled {
            guard hasStarted else { return }
            launchAutomaticRefresh()
        } else {
            automaticUsageRefreshTask?.cancel()
            automaticUsageRefreshTask = nil
        }
    }

    func subscriptionPreferenceDidChange() async {
        do {
            publish(try await client.loadCached())
        } catch {
            publishRefreshFailure()
        }
    }

    private func launchBackfill() {
        guard backfillTask == nil else { return }
        let client = self.client
        let capturedPublicationRevision = publicationRevision
        let capturedForegroundRevision = foregroundRevision
        backfillTask = Task { @MainActor [weak self, client] in
            do {
                let result = try await client.backfillHistory()
                guard !Task.isCancelled,
                      let self,
                      self.publicationRevision == capturedPublicationRevision,
                      self.foregroundRevision == capturedForegroundRevision else {
                    return
                }
                self.publish(result)
            } catch {
                // Foreground state remains authoritative when optional history work fails.
            }
        }
    }

    private func launchAutomaticRefresh() {
        guard isAutomaticRefreshEnabled else { return }
        let sleeper = self.sleeper
        if automaticUsageRefreshTask == nil {
            let interval = usageRefreshInterval
            automaticUsageRefreshTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do {
                        try await sleeper(interval)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    await self?.refreshUsage()
                }
            }
        }
    }

    private func publish(_ result: DashboardDataResult) {
        publicationRevision &+= 1
        switch result {
        case .loaded(let snapshot, let summary):
            sourceSummary = summary
            state = .loaded(snapshot, summary)
        case .empty(let summary):
            sourceSummary = summary
            state = .empty(summary)
        case .stale(let snapshot, let summary, let message):
            sourceSummary = summary
            state = .stale(snapshot, summary, message)
        case .unsupported(let message):
            if let snapshot, let summary = sourceSummary {
                state = .stale(snapshot, summary, "数据格式发生变化，正在显示上次可用数据。")
            } else {
                state = .unsupported(message)
            }
        }
    }

    private func publishRefreshFailure() {
        publicationRevision &+= 1
        if let snapshot, let summary = sourceSummary {
            state = .stale(snapshot, summary, "暂时无法刷新，正在显示上次可用数据。")
        } else {
            state = .failed("暂时无法读取 Codex 数据，请稍后重试。")
        }
    }

    isolated deinit {
        startTask?.cancel()
        inFlightManualRefresh?.cancel()
        inFlightRefresh?.cancel()
        inFlightRebuild?.cancel()
        backfillTask?.cancel()
        automaticUsageRefreshTask?.cancel()
    }
}
