import Foundation
import XCTest
@testable import CodexVista

final class CodexImporterTests: XCTestCase {
    func testVisualizationRootsMergeHistoricalUsageWithoutChangingTokensOrCheckpoint() async throws {
        let fixture = try CodexFixture.make(events: [.sessionCLI])
        let root = "/synthetic/business"
        let output = fixture.codexRoot.appending(path:
            "visualizations/2026/09/02/00000000-0000-4000-8000-000000000001").path
        try fixture.append(.turnInWorkspace(model: "gpt-synthetic", roots: [root, output]))
        try fixture.append(.token(input: 100, cached: 40, output: 20, reasoning: 5, plan: "plus"))
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let initial = await CodexImporter(rootURL: fixture.codexRoot, store: store).refresh(scope: .history)
        XCTAssertTrue(initial.isSuccessful)
        let clean = try XCTUnwrap(store.usageEvents().first?.workspace)
        XCTAssertEqual(clean.name, "business")
        XCTAssertEqual(clean.rootCount, 1)
        let fileID = try XCTUnwrap(initial.discoveredFileIDs?.first)
        let offset = try store.fileCheckpoint(fileID: fileID)?.committedOffset

        // Recreate the identity saved by older versions, retaining original event evidence.
        let legacy = try XCTUnwrap(WorkspaceIdentity.resolve(rootPaths: [root, output]))
        let database = try SQLiteDatabase(url: fixture.databaseURL)
        try database.execute(sql:
            "UPDATE usage_events SET workspace_id = ?, workspace_name = ?, workspace_root_count = 2",
            bindings: [.text(legacy.id), .text(legacy.name)])
        let restarted = CodexImporter(rootURL: fixture.codexRoot, store: store)
        let repaired = await restarted.refresh(scope: .foreground)
        XCTAssertTrue(repaired.isSuccessful)
        XCTAssertEqual(try store.workspaceAliases()[legacy.id], clean.id)
        XCTAssertEqual(try store.fileCheckpoint(fileID: fileID)?.committedOffset, offset)
        XCTAssertEqual(try store.usageEvents().first?.workspace, legacy)

        try fixture.append(.turnInWorkspace(model: "gpt-synthetic", roots: [root]))
        try fixture.append(.token(input: 200, cached: 80, output: 40, reasoning: 10, plan: "plus", second: 6))
        let refreshed = await restarted.refresh(scope: .history)
        XCTAssertTrue(refreshed.isSuccessful)
        let ranking = try DashboardQueryService(store: store)
            .snapshot(now: Date(timeIntervalSince1970: 2_000_000_000), calendar: .current).workspaceUsage.allTime
        XCTAssertEqual(ranking.workspaceCount, 1)
        XCTAssertEqual(ranking.entries.first?.name, "business")
        XCTAssertEqual(ranking.totalTokens, 240)
        let rebuilt = await restarted.rebuildFromLocalData()
        XCTAssertTrue(rebuilt.isSuccessful)
        XCTAssertEqual(try store.totalUsage(), 240)
        XCTAssertTrue(try store.usageEvents().allSatisfy { $0.workspace == clean })
    }

    func testVisualizationFilteringPreservesBusinessUUIDDirectoriesAndMultipleRoots() async throws {
        let fixture = try CodexFixture.make(events: [.sessionCLI])
        let roots = ["/synthetic/business", "/synthetic/00000000-0000-4000-8000-000000000001"]
        let output = fixture.codexRoot.appending(path:
            "visualizations/2026/09/02/00000000-0000-4000-8000-000000000002").path
        try fixture.append(.turnInWorkspace(model: "gpt-synthetic", roots: roots + [output]))
        try fixture.append(.token(input: 100, cached: 40, output: 20, reasoning: 5, plan: "plus"))
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let result = await CodexImporter(rootURL: fixture.codexRoot, store: store).refresh(scope: .history)
        XCTAssertTrue(result.isSuccessful)
        XCTAssertEqual(try store.usageEvents().first?.workspace, WorkspaceIdentity.resolve(rootPaths: roots))
    }

    func testRefreshBindsHistoricalUsageAfterRepositoryIdentityChanges() async throws {
        let roots = ["/synthetic/public-project", "/synthetic/private-project"]
        let fixture = try CodexFixture.make(events: [
            .sessionCLI,
            .turnInWorkspace(model: "gpt-synthetic", roots: roots),
            .token(input: 100, cached: 40, output: 20, reasoning: 5, plan: "plus")
        ])
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let originalImporter = CodexImporter(
            rootURL: fixture.codexRoot, store: store,
            repositoryResolver: MappingRepositoryIdentityResolver(repositoryIDs: [
                roots[0]: "old-public-repository", roots[1]: "old-private-repository"
            ])
        )
        let imported = await originalImporter.refresh(scope: .history)
        XCTAssertTrue(imported.isSuccessful)
        let originalUsage = try XCTUnwrap(store.usageEvents().first)
        let fileID = try XCTUnwrap(imported.discoveredFileIDs?.first)
        let originalOffset = try store.fileCheckpoint(fileID: fileID)?.committedOffset
        try Data(#"{"local-projects":{"project-a":{"name":"Two directories","rootPaths":["/synthetic/public-project","/synthetic/private-project"],"updatedAt":2000}}}"#.utf8)
            .write(to: fixture.codexRoot.appending(path: ".codex-global-state.json"))
        let restartedImporter = CodexImporter(
            rootURL: fixture.codexRoot, store: store,
            repositoryResolver: MappingRepositoryIdentityResolver(repositoryIDs: [
                roots[0]: "new-public-repository", roots[1]: "new-private-repository"
            ])
        )

        let refreshed = await restartedImporter.refresh(scope: .foreground)
        let entry = try XCTUnwrap(DashboardQueryService(store: store)
            .snapshot(now: Date(timeIntervalSince1970: 2_000_000_000), calendar: .current)
            .workspaceUsage.allTime.entries.first)

        XCTAssertTrue(refreshed.isSuccessful)
        XCTAssertEqual(refreshed.processedFileCount, 0)
        XCTAssertEqual(entry.name, "Two directories")
        XCTAssertEqual(entry.configuredDirectories.map(\.name), ["private-project", "public-project"])
        XCTAssertEqual(entry.tokens, 120)
        XCTAssertEqual(try store.usageEventCount(), 1)
        XCTAssertEqual(try store.usageEvents().first?.workspace, originalUsage.workspace)
        XCTAssertEqual(try store.fileCheckpoint(fileID: fileID)?.committedOffset, originalOffset)
    }

    func testHistoricalBindingRepairKeepsReusedTurnIDsInDifferentRootSetsSeparate() async throws {
        let firstRoots = ["/synthetic/first", "/synthetic/first-private"]
        let secondRoots = ["/synthetic/second", "/synthetic/second-private"]
        let fixture = try CodexFixture.make(events: [
            .sessionCLI,
            .turnInWorkspace(model: "gpt-synthetic", roots: firstRoots),
            .token(input: 100, cached: 40, output: 20, reasoning: 5, plan: "plus"),
            .turnInWorkspace(model: "gpt-synthetic", roots: secondRoots),
            .token(input: 200, cached: 80, output: 40, reasoning: 10, plan: "plus", second: 6)
        ])
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let roots = firstRoots + secondRoots
        let oldImporter = CodexImporter(
            rootURL: fixture.codexRoot, store: store,
            repositoryResolver: MappingRepositoryIdentityResolver(
                repositoryIDs: Dictionary(uniqueKeysWithValues: roots.map { ($0, "old-\($0)") })
            )
        )
        let initial = await oldImporter.refresh(scope: .history)
        XCTAssertTrue(initial.isSuccessful)
        let state: [String: Any] = ["local-projects": [
            "a": ["name": "First", "rootPaths": firstRoots],
            "b": ["name": "Second", "rootPaths": secondRoots]
        ]]
        try JSONSerialization.data(withJSONObject: state)
            .write(to: fixture.codexRoot.appending(path: ".codex-global-state.json"))
        let newImporter = CodexImporter(
            rootURL: fixture.codexRoot, store: store,
            repositoryResolver: MappingRepositoryIdentityResolver(
                repositoryIDs: Dictionary(uniqueKeysWithValues: roots.map { ($0, "new-\($0)") })
            )
        )

        let refreshed = await newImporter.refresh(scope: .foreground)
        let ranking = try DashboardQueryService(store: store)
            .snapshot(now: Date(timeIntervalSince1970: 2_000_000_000), calendar: .current)
            .workspaceUsage.allTime

        XCTAssertTrue(refreshed.isSuccessful)
        XCTAssertEqual(ranking.entries.map(\.name), ["First", "Second"])
        XCTAssertEqual(ranking.entries.map(\.tokens), [120, 120])
        XCTAssertEqual(ranking.entries.map { $0.configuredDirectories.map(\.name) },
                       [["first", "first-private"], ["second", "second-private"]])
        XCTAssertEqual(try store.usageEventCount(), 2)
    }

    func testWorkspaceDirectoryChangesRefreshWithoutNewUsageAndSurviveRestart() async throws {
        let fixture = try CodexFixture.make(events: [
            .sessionCLI,
            .turnInWorkspace(model: "gpt-synthetic", roots: ["/synthetic/first", "/synthetic/second"]),
            .token(input: 100, cached: 40, output: 20, reasoning: 5, plan: "plus")
        ])
        let stateURL = fixture.codexRoot.appending(path: ".codex-global-state.json")
        try Data(#"{"local-projects":{"project-a":{"name":"Project A","rootPaths":["/synthetic/first","/synthetic/second"],"updatedAt":1000}}}"#.utf8).write(to: stateURL)
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let importer = CodexImporter(rootURL: fixture.codexRoot, store: store)
        let first = await importer.refresh(scope: .history)
        XCTAssertTrue(first.isSuccessful)
        let query = DashboardQueryService(store: store)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let original = try XCTUnwrap(query.snapshot(now: now, calendar: .current).workspaceUsage.allTime.entries.first)
        XCTAssertEqual(original.rootCount, 2)

        try Data(#"{"local-projects":{"project-a":{"name":"Renamed Project","rootPaths":["/synthetic/first","/synthetic/second","/synthetic/third"],"updatedAt":2000}}}"#.utf8).write(to: stateURL)
        let refreshed = await importer.refresh(scope: .foreground)
        XCTAssertTrue(refreshed.isSuccessful)
        XCTAssertEqual(refreshed.processedFileCount, 0)
        let updated = try XCTUnwrap(query.snapshot(now: now, calendar: .current).workspaceUsage.allTime.entries.first)
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.name, "Renamed Project")
        XCTAssertEqual(updated.rootCount, 3)
        XCTAssertEqual(updated.configuredDirectories.map(\.name), ["first", "second", "third"])
        XCTAssertEqual(updated.tokens, 120)

        // A replacement removes both original roots; matching by overlap cannot repair this.
        try Data(#"{"local-projects":{"project-a":{"name":"Renamed Project","rootPaths":["/synthetic/replacement"],"updatedAt":3000}}}"#.utf8).write(to: stateURL)
        let reopenedStore = try UsageStore(databaseURL: fixture.databaseURL)
        let restarted = CodexImporter(rootURL: fixture.codexRoot, store: reopenedStore)
        let result = await restarted.refresh(scope: .foreground)
        XCTAssertTrue(result.isSuccessful)
        let final = try XCTUnwrap(DashboardQueryService(store: reopenedStore)
            .snapshot(now: now, calendar: .current).workspaceUsage.allTime.entries.first)
        XCTAssertEqual(final.id, original.id)
        XCTAssertEqual(final.rootCount, 1)
        XCTAssertEqual(final.configuredDirectories.map(\.name), ["replacement"])
        XCTAssertEqual(final.tokens, 120)
        XCTAssertEqual(try reopenedStore.usageEventCount(), 1)

        try fixture.append(.turnInWorkspace(model: "gpt-synthetic", roots: ["/synthetic/replacement"]))
        try fixture.append(.token(input: 200, cached: 80, output: 40, reasoning: 10, plan: "plus", second: 6))
        let appended = await restarted.refresh(scope: .history)
        XCTAssertTrue(appended.isSuccessful)
        let ranking = try DashboardQueryService(store: reopenedStore)
            .snapshot(now: now, calendar: .current).workspaceUsage.allTime
        XCTAssertEqual(ranking.workspaceCount, 1)
        XCTAssertEqual(ranking.totalTokens, 240)
        XCTAssertEqual(ranking.entries.first?.id, original.id)

        try FileManager.default.removeItem(at: stateURL)
        let rebuilt = await restarted.rebuildFromLocalData()
        XCTAssertTrue(rebuilt.isSuccessful)
        let restored = try XCTUnwrap(DashboardQueryService(store: reopenedStore)
            .snapshot(now: now, calendar: .current).workspaceUsage.allTime.entries.first)
        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.configuredDirectories.map(\.name), ["replacement"])
        XCTAssertEqual(restored.tokens, 240)
    }

    func testImportsUsageQuotaAndSessionOnceAcrossRefreshes() async throws {
        let fixture = try CodexFixture.make(events: [
            .sessionDesktop,
            .turn(model: "gpt-synthetic"),
            .started,
            .token(input: 1_000, cached: 600, output: 100, reasoning: 40, plan: "plus"),
            .completed,
            .unknown
        ])
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let importer = CodexImporter(rootURL: fixture.codexRoot, store: store)

        let first = await importer.refresh(scope: .history)
        let second = await importer.refresh(scope: .history)

        XCTAssertTrue(first.isSuccessful)
        XCTAssertEqual(first.processedFileCount, 1)
        XCTAssertEqual(first.discoveredFileIDs?.count, 1)
        XCTAssertEqual(second.skippedFileCount, 1)
        XCTAssertEqual(try store.totalUsage(), 1_100)
        XCTAssertEqual(try store.usageEvents().first?.project.name, "CodexVistaFixture")
        XCTAssertEqual(try store.usageEvents().first?.workspace.name, "CodexVistaFixture")
        XCTAssertTrue(try store.usageEvents().first?.workspace.isInferred ?? false)
        let inferredWorkspace = try XCTUnwrap(store.usageEvents().first?.workspace)
        let fileID = try XCTUnwrap(first.discoveredFileIDs?.first)
        XCTAssertEqual(try store.fileCheckpoint(fileID: fileID)?.workspace, inferredWorkspace)
        XCTAssertEqual(
            try store.threadCheckpoint(threadID: CodexFixture.threadID)?.currentWorkspace,
            inferredWorkspace
        )
        XCTAssertEqual(try store.usageEvents().first?.turnID, "turn-1")
        XCTAssertEqual(try store.latestQuotas().map(\.observation.kind), [.fiveHour, .weekly])
        XCTAssertEqual(try store.sessions().first?.activity, .completed)
        XCTAssertEqual(try store.sessions().first?.sourceKind, .desktop)
        XCTAssertEqual(try store.usageEventCount(), 1)
        XCTAssertEqual(try store.quotaEventCount(), 2)
        XCTAssertEqual(try store.sessionStateEventCount(), 2)
    }

    func testImporterAttributesUsageAndCheckpointsToTurnWorkspace() async throws {
        let roots = [
            "/synthetic/guide-performance",
            "/synthetic/retail-sales"
        ]
        let fixture = try CodexFixture.make(events: [
            .sessionCLI,
            .turnInWorkspace(model: "gpt-synthetic", roots: roots),
            .token(input: 100, cached: 40, output: 20, reasoning: 5, plan: "plus")
        ])
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let result = await CodexImporter(rootURL: fixture.codexRoot, store: store)
            .refresh(scope: .history)

        XCTAssertTrue(result.isSuccessful, "workspace import issues: \(result.issues)")
        let expected = try XCTUnwrap(WorkspaceIdentity.resolve(rootPaths: roots))
        XCTAssertEqual(try store.usageEvents().first?.workspace, expected)
        XCTAssertFalse(try store.usageEvents().first?.workspace.isInferred ?? true)
        let fileID = try XCTUnwrap(result.discoveredFileIDs?.first)
        XCTAssertEqual(try store.fileCheckpoint(fileID: fileID)?.workspace, expected)
        XCTAssertEqual(
            try store.threadCheckpoint(threadID: CodexFixture.threadID)?.currentWorkspace,
            expected
        )
    }

    func testImporterUsesArchivedCodexWorkspaceNameAndKeepsItAcrossRebuilds() async throws {
        let roots = ["/synthetic/retail-sales", "/synthetic/guide-performance"]
        let fixture = try CodexFixture.make(events: [
            .sessionCLI,
            .turnInWorkspace(model: "gpt-synthetic", roots: roots),
            .token(input: 100, cached: 40, output: 20, reasoning: 5, plan: "plus")
        ])
        let archivedState = fixture.codexRoot
            .appending(path: "..codex-global-state.json.tmp-archived")
        try Data(#"{"local-projects":{"archived":{"name":"open-api","rootPaths":["/synthetic/retail-sales","/synthetic/guide-performance"]}}}"#.utf8)
            .write(to: archivedState)
        let repositoryResolver = MappingRepositoryIdentityResolver(repositoryIDs: [
            "/synthetic/retail-sales": "retail-repository",
            "/synthetic/guide-performance": "guide-repository"
        ])
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let firstImporter = CodexImporter(
            rootURL: fixture.codexRoot,
            store: store,
            repositoryResolver: repositoryResolver
        )

        let first = await firstImporter.refresh(scope: .history)

        XCTAssertTrue(first.isSuccessful)
        let firstWorkspace = try XCTUnwrap(store.usageEvents().first?.workspace)
        XCTAssertEqual(firstWorkspace.name, "open-api")
        XCTAssertEqual(firstWorkspace.rootCount, 2)

        try FileManager.default.removeItem(at: archivedState)
        let secondImporter = CodexImporter(
            rootURL: fixture.codexRoot,
            store: store,
            repositoryResolver: repositoryResolver
        )
        let rebuilt = await secondImporter.rebuildFromLocalData()

        XCTAssertTrue(rebuilt.isSuccessful)
        XCTAssertEqual(try store.usageEvents().first?.workspace, firstWorkspace)
        XCTAssertEqual(try store.workspaceCatalog()[firstWorkspace.id]?.name, "open-api")
    }

    func testImporterPersistsRepositoryIdentityResolvedFromSessionWorkingDirectory() async throws {
        let fixture = try CodexFixture.make(events: [
            .sessionCLI,
            .turn(model: "gpt-synthetic"),
            .token(input: 100, cached: 40, output: 20, reasoning: 5, plan: "plus")
        ])
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let importer = CodexImporter(
            rootURL: fixture.codexRoot,
            store: store,
            repositoryResolver: FixedRepositoryIdentityResolver(repositoryID: "repository-1")
        )

        let result = await importer.refresh(scope: .history)

        XCTAssertTrue(result.isSuccessful)
        XCTAssertEqual(try store.usageEvents().first?.project.repositoryID, "repository-1")
        XCTAssertEqual(
            try store.fileCheckpoint(fileID: try XCTUnwrap(result.discoveredFileIDs?.first))?
                .project?.repositoryID,
            "repository-1"
        )
    }

    func testImporterPrefersEmbeddedRepositoryIdentityOverWorkingDirectoryFallback() async throws {
        let fixture = try CodexFixture.make(events: [
            .sessionCLIWithRepository,
            .turn(model: "gpt-synthetic"),
            .token(input: 100, cached: 40, output: 20, reasoning: 5, plan: "plus")
        ])
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let importer = CodexImporter(
            rootURL: fixture.codexRoot,
            store: store,
            repositoryResolver: FixedRepositoryIdentityResolver(repositoryID: "fallback-repository")
        )

        let result = await importer.refresh(scope: .history)

        XCTAssertTrue(result.isSuccessful)
        XCTAssertEqual(
            try store.usageEvents().first?.project.repositoryID,
            GitRepositoryIdentityResolver.repositoryID(
                repositoryURL: "git@github.com:ychp-ai/CodexVista.git"
            )
        )
    }

    func testRebuildFromLocalDataClearsAllImportedRowsAndRescansHistory() async throws {
        let fixture = try CodexFixture.make(events: [
            .sessionCLI,
            .turn(model: "gpt-synthetic"),
            .activity,
            .token(input: 100, cached: 40, output: 20, reasoning: 5, plan: "plus")
        ])
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let importer = CodexImporter(rootURL: fixture.codexRoot, store: store)
        _ = await importer.refresh(scope: .history)

        try store.commit(ImportBatch(
            file: FileCheckpoint(
                fileID: "stale-file", deviceID: 1, inode: 1,
                path: "/synthetic/stale.jsonl", fileSize: 1, committedOffset: 1,
                generation: 0, threadID: "stale-thread", lastRecordAtMilliseconds: 1_000,
                lastSuccessAtMilliseconds: 1_000, formatStatus: "supported", lastError: nil,
                activityCommittedOffset: 1
            ),
            usageEvents: [StoredUsageEvent(
                fingerprint: "stale-usage", observedAtMilliseconds: 1_000,
                threadID: "stale-thread", sourceKind: .cli, model: "stale-model",
                plan: PlanResolver.resolve(rawValue: "plus"),
                usage: TokenUsageDelta(
                    uncachedInput: 500, cachedInput: 0, visibleOutput: 0, reasoning: 0
                ),
                sourceFileID: "stale-file", sourceOffset: 1
            )],
            quotaEvents: [],
            stateEvents: [],
            activityEvents: [StoredActivityEvent(
                fingerprint: "stale-activity", observedAtMilliseconds: 1_000,
                threadID: "stale-thread", turnID: "stale-turn", kind: .tool,
                name: "stale-tool", sourceKind: .cli,
                sourceFileID: "stale-file", sourceOffset: 1
            )],
            sessions: [],
            threadCheckpoints: []
        ))
        XCTAssertEqual(try store.totalUsage(), 620)
        XCTAssertEqual(try store.activityEventCount(), 3)

        let progressRecorder = ImportProgressRecorder()
        let result = await importer.rebuildFromLocalData { progress in
            await progressRecorder.record(progress)
        }

        XCTAssertTrue(result.isSuccessful)
        XCTAssertEqual(result.scope, .history)
        XCTAssertEqual(result.processedFileCount, 1)
        let progressUpdates = await progressRecorder.updates
        XCTAssertEqual(
            progressUpdates,
            [
                .resetting,
                .discovering,
                .importing(completed: 0, total: 1),
                .importing(completed: 1, total: 1)
            ]
        )
        XCTAssertEqual(try store.totalUsage(), 120)
        XCTAssertEqual(try store.activityEventCount(), 2)
        XCTAssertNil(try store.fileCheckpoint(fileID: "stale-file"))
        XCTAssertEqual(
            try store.activityCounts(
                kind: .tool, fromMilliseconds: nil, toMilliseconds: nil, limit: 6
            ).map(\.name),
            ["exec_command"]
        )
    }

    func testActivityHistoryBackfillUsesIndependentCheckpointAndIsIdempotent() async throws {
        let fixture = try CodexFixture.make(events: [
            .sessionCLI,
            .turn(model: "gpt-synthetic"),
            .started,
            .activity,
            .completed
        ])
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let importer = CodexImporter(rootURL: fixture.codexRoot, store: store)
        _ = await importer.refresh(scope: .history)
        XCTAssertEqual(try store.activityEventCount(), 2)

        let database = try SQLiteDatabase(url: fixture.databaseURL)
        try database.execute(sql: "DELETE FROM activity_events")
        try database.execute(sql: "UPDATE source_files SET activity_committed_offset = 0")

        let backfill = await CodexImporter(rootURL: fixture.codexRoot, store: store).refresh(scope: .history)
        let checkpoint = try XCTUnwrap(try store.fileCheckpoint(fileID: try XCTUnwrap(
            CodexSourceDiscovery().discover(rootURL: fixture.codexRoot).rollouts.first?.fileID
        )))

        XCTAssertTrue(backfill.isSuccessful)
        XCTAssertEqual(backfill.processedFileCount, 1)
        XCTAssertEqual(checkpoint.committedOffset, try fixture.rolloutSize())
        XCTAssertEqual(checkpoint.activityCommittedOffset, try fixture.rolloutSize())
        XCTAssertEqual(try store.activityEventCount(), 2)
        let skills = try store.activityCounts(
            kind: .skill, fromMilliseconds: nil, toMilliseconds: nil, limit: 6
        )
        let tools = try store.activityCounts(
            kind: .tool, fromMilliseconds: nil, toMilliseconds: nil, limit: 6
        )
        XCTAssertEqual(skills.map(\.name), ["ai-code-review"])
        XCTAssertEqual(skills.map(\.count), [1])
        XCTAssertEqual(tools.map(\.name), ["exec_command"])
        XCTAssertEqual(tools.map(\.count), [1])

        let repeated = await CodexImporter(rootURL: fixture.codexRoot, store: store).refresh(scope: .history)
        XCTAssertEqual(repeated.skippedFileCount, 1)
        XCTAssertEqual(try store.activityEventCount(), 2)
    }

    func testMalformedActivityPayloadDoesNotBlockUsageImport() async throws {
        let fixture = try CodexFixture.make(events: [
            .sessionCLI,
            .turn(model: "gpt-synthetic")
        ])
        try fixture.appendRaw(#"{"timestamp":"not-a-date","type":"response_item","payload":{"type":"function_call","name":"exec_command"}}"# + "\n")
        try fixture.append(.token(
            input: 100, cached: 40, output: 20, reasoning: 5, plan: "plus"
        ))
        let store = try UsageStore(databaseURL: fixture.databaseURL)

        let result = await CodexImporter(rootURL: fixture.codexRoot, store: store).refresh(scope: .history)

        XCTAssertTrue(result.isSuccessful)
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(try store.totalUsage(), 120)
        XCTAssertEqual(try store.activityEventCount(), 0)
        let fileID = try XCTUnwrap(try store.sessions().first?.sourceFileID)
        let checkpoint = try XCTUnwrap(try store.fileCheckpoint(fileID: fileID))
        XCTAssertEqual(checkpoint.committedOffset, try fixture.rolloutSize())
        XCTAssertEqual(checkpoint.activityCommittedOffset, try fixture.rolloutSize())
    }

    func testAppendAddsOnlyPositiveDeltaAndArchiveMoveDoesNotDuplicate() async throws {
        let fixture = try CodexFixture.make(events: [
            .sessionCLI,
            .turn(model: "gpt-synthetic"),
            .token(input: 1_000, cached: 500, output: 100, reasoning: 20, plan: nil)
        ])
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let importer = CodexImporter(rootURL: fixture.codexRoot, store: store)
        _ = await importer.refresh(scope: .history)

        try fixture.append(.token(
            input: 1_500,
            cached: 700,
            output: 160,
            reasoning: 30,
            plan: nil,
            second: 6
        ))
        _ = await importer.refresh(scope: .history)
        try fixture.archiveRollout()
        _ = await importer.refresh(scope: .history)

        XCTAssertEqual(try store.totalUsage(), 1_660)
        XCTAssertEqual(try store.sessions().first?.archive, .archived)
        XCTAssertEqual(try store.usageEventCount(), 2)
    }

    func testMalformedKnownEventStopsAtBadLineAndReportsOnlyControlledDetail() async throws {
        let fixture = try CodexFixture.make(events: [
            .sessionCLI,
            .turn(model: "gpt-synthetic"),
            .token(input: 100, cached: 40, output: 20, reasoning: 5, plan: "plus")
        ])
        let goodOffset = try fixture.rolloutSize()
        let secret = "SENSITIVE-SENTINEL"
        try fixture.appendRaw("{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"secret\":\"\(secret)\"}\n")
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let importer = CodexImporter(rootURL: fixture.codexRoot, store: store)

        let result = await importer.refresh(scope: .history)
        let checkpoint = try XCTUnwrap(try store.sessions().first?.sourceFileID)
        let file = try XCTUnwrap(try store.fileCheckpoint(fileID: checkpoint))

        XCTAssertEqual(result.issues.map(\.kind), [.decode])
        XCTAssertFalse(result.issues[0].detail.contains(secret))
        XCTAssertFalse(result.issues[0].detail.contains(fixture.codexRoot.path))
        XCTAssertEqual(file.committedOffset, goodOffset)
        XCTAssertEqual(file.formatStatus, "error")
        XCTAssertEqual(file.lastError, "malformed-event")
        XCTAssertEqual(try store.totalUsage(), 120)

        let retry = await importer.refresh(scope: .history)
        XCTAssertEqual(retry.issues.map(\.kind), [.decode])
        XCTAssertEqual(try store.fileCheckpoint(fileID: checkpoint)?.committedOffset, goodOffset)
        XCTAssertEqual(try store.usageEventCount(), 1)
    }

    func testTruncationRebuildsDerivedUsageFromReplacement() async throws {
        let fixture = try CodexFixture.make(events: [
            .sessionCLI,
            .turn(model: "gpt-synthetic"),
            .token(input: 1_000, cached: 500, output: 100, reasoning: 20, plan: "plus")
        ])
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let importer = CodexImporter(rootURL: fixture.codexRoot, store: store)
        _ = await importer.refresh(scope: .history)
        let fileID = try XCTUnwrap(try store.sessions().first?.sourceFileID)

        try fixture.replace(events: [
            .sessionCLI,
            .turn(model: "gpt-synthetic"),
            .token(input: 10, cached: 4, output: 2, reasoning: 1, plan: nil, second: 8)
        ])
        _ = await importer.refresh(scope: .history)

        let reset = try XCTUnwrap(try store.fileCheckpoint(fileID: fileID))
        XCTAssertEqual(reset.generation, 0)
        XCTAssertEqual(reset.committedOffset, try fixture.rolloutSize())
        XCTAssertEqual(reset.counters?.input, 10)
        XCTAssertEqual(try store.totalUsage(), 12)

        _ = await importer.refresh(scope: .history)
        XCTAssertEqual(try store.totalUsage(), 12)
        XCTAssertEqual(try store.fileCheckpoint(fileID: fileID)?.generation, 0)
    }

    func testExplicitPlanSurvivesImporterRestartWhenLaterSnapshotOmitsPlan() async throws {
        let fixture = try CodexFixture.make(events: [
            .sessionCLI,
            .turn(model: "gpt-synthetic"),
            .token(input: 100, cached: 40, output: 20, reasoning: 5, plan: "plus")
        ])
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        _ = await CodexImporter(rootURL: fixture.codexRoot, store: store).refresh(scope: .history)

        try fixture.append(.token(
            input: 200,
            cached: 80,
            output: 40,
            reasoning: 10,
            plan: nil,
            second: 7
        ))
        _ = await CodexImporter(rootURL: fixture.codexRoot, store: store).refresh(scope: .history)

        XCTAssertEqual(try store.hourlyUsage().map(\.plan), [.plus])
        XCTAssertEqual(try store.threadCheckpoint(threadID: CodexFixture.threadID)?.currentPlan?.kind, .plus)
    }

    func testForegroundSelectsNewestOldCandidateAndHistoryDeduplicatesOtherSource() async throws {
        let fixture = try CodexFixture.make(events: [
            .sessionCLI,
            .turn(model: "gpt-synthetic"),
            .token(input: 100, cached: 40, output: 20, reasoning: 5, plan: "plus")
        ])
        try fixture.setRolloutModificationDate(Date(timeIntervalSince1970: 1_000))
        _ = try fixture.duplicateRollout(
            named: "newer-old.jsonl",
            modificationDate: Date(timeIntervalSince1970: 2_000)
        )
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let importer = CodexImporter(rootURL: fixture.codexRoot, store: store)

        let foreground = await importer.refresh(scope: .foreground)
        let history = await importer.refresh(scope: .history)

        XCTAssertEqual(foreground.processedFileCount, 1)
        XCTAssertEqual(foreground.skippedFileCount, 1)
        XCTAssertEqual(history.processedFileCount, 1)
        XCTAssertEqual(history.skippedFileCount, 1)
        XCTAssertEqual(try store.totalUsage(), 120)
        XCTAssertEqual(try store.usageEventCount(), 1)
    }

    func testCopiedParentHistoryWithRewrittenTimestampsIsDeduplicated() async throws {
        let fixture = try CodexFixture.make(events: [
            .sessionCLI,
            .turn(model: "gpt-synthetic"),
            .token(input: 100, cached: 40, output: 20, reasoning: 5, plan: "plus"),
            .token(input: 200, cached: 80, output: 40, reasoning: 10, plan: "plus", second: 7)
        ])
        try fixture.setRolloutModificationDate(Date(timeIntervalSince1970: 1_000))
        let child = try fixture.duplicateRollout(
            named: "child-with-copied-history.jsonl",
            modificationDate: Date(timeIntervalSince1970: 2_000)
        )
        let childThreadID = "00000000-0000-0000-0000-000000000002"
        let copiedHistory = """
        {"timestamp":"2026-07-15T02:00:00.000Z","type":"session_meta","payload":{"id":"\(childThreadID)","source":{"subagent":{"thread_spawn":{"parent_thread_id":"\(CodexFixture.threadID)"}}},"cli_version":"1.0.0","cwd":"/synthetic/CodexVistaFixture"}}
        {"timestamp":"2026-07-15T02:00:00.001Z","type":"session_meta","payload":{"id":"\(CodexFixture.threadID)","source":"vscode","cli_version":"1.0.0","cwd":"/synthetic/CodexVistaFixture"}}
        {"type":"turn_context","payload":{"turn_id":"copied-turn","model":"gpt-synthetic"}}
        {"timestamp":"2026-07-15T02:00:00.002Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":20,"reasoning_output_tokens":5}}}}
        {"timestamp":"2026-07-15T02:00:00.003Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":200,"cached_input_tokens":80,"output_tokens":40,"reasoning_output_tokens":10}}}}
        {"timestamp":"2026-07-15T02:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":50,"cached_input_tokens":20,"output_tokens":10,"reasoning_output_tokens":2}}}}
        {"timestamp":"2026-07-15T02:00:02.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":20,"reasoning_output_tokens":5}}}}
        """ + "\n"
        try Data(copiedHistory.utf8).write(to: child)

        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let result = await CodexImporter(rootURL: fixture.codexRoot, store: store).refresh(scope: .history)

        XCTAssertTrue(result.isSuccessful, "copied history import issues: \(result.issues)")
        XCTAssertEqual(try store.totalUsage(), 360)
        XCTAssertEqual(try store.usageEventCount(), 4)
    }

    func testCounterRollbackKeepsLegitimateRepeatedCounterSnapshot() async throws {
        let fixture = try CodexFixture.make(events: [
            .sessionCLI,
            .turn(model: "gpt-synthetic"),
            .token(input: 100, cached: 40, output: 20, reasoning: 5, plan: "plus"),
            .token(input: 200, cached: 80, output: 40, reasoning: 10, plan: "plus", second: 7),
            .token(input: 100, cached: 40, output: 20, reasoning: 5, plan: "plus", second: 8)
        ])
        let store = try UsageStore(databaseURL: fixture.databaseURL)

        _ = await CodexImporter(rootURL: fixture.codexRoot, store: store).refresh(scope: .history)

        XCTAssertEqual(try store.totalUsage(), 360)
        XCTAssertEqual(try store.usageEventCount(), 3)
    }

    func testExactFileThreadMappingSurvivesOtherRolloutWinningSessionThenRestart() async throws {
        let fixture = try CodexFixture.make(events: [
            .sessionCLI,
            .turn(model: "gpt-synthetic"),
            .started,
            .token(input: 100, cached: 40, output: 20, reasoning: 5, plan: "plus")
        ])
        try fixture.setRolloutModificationDate(Date(timeIntervalSince1970: 3_000))
        let second = try fixture.duplicateRollout(
            named: "second.jsonl",
            modificationDate: Date(timeIntervalSince1970: 2_000)
        )
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        _ = await CodexImporter(rootURL: fixture.codexRoot, store: store).refresh(scope: .history)
        let secondFileID = try XCTUnwrap(
            CodexSourceDiscovery().discover(rootURL: fixture.codexRoot).rollouts
                .first { $0.url.lastPathComponent == second.lastPathComponent }?.fileID
        )
        XCTAssertEqual(try store.sessions().first?.sourceFileID, secondFileID)

        try fixture.append(.token(
            input: 200,
            cached: 80,
            output: 40,
            reasoning: 10,
            plan: nil,
            second: 7
        ))
        try fixture.append(.completed)
        let result = await CodexImporter(rootURL: fixture.codexRoot, store: store).refresh(scope: .history)
        let firstRollout = try XCTUnwrap(
            CodexSourceDiscovery().discover(rootURL: fixture.codexRoot).rollouts
                .first { $0.url.lastPathComponent == fixture.rolloutURL.lastPathComponent }
        )

        XCTAssertTrue(result.isSuccessful)
        XCTAssertEqual(try store.fileCheckpoint(fileID: firstRollout.fileID)?.threadID, CodexFixture.threadID)
        XCTAssertEqual(try store.totalUsage(), 240)
        XCTAssertEqual(try store.usageEventCount(), 2)
        XCTAssertEqual(try store.sessions().first?.activity, .completed)
    }

    func testTokenCheckpointsRemainIsolatedAcrossFilesForSameThread() async throws {
        let fixture = try CodexFixture.make(events: [
            .sessionCLI,
            .turn(model: "gpt-synthetic"),
            .token(input: 100, cached: 40, output: 20, reasoning: 5, plan: "plus")
        ])
        let second = try fixture.duplicateRollout(
            named: "second.jsonl",
            modificationDate: Date(timeIntervalSince1970: 2_000)
        )
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let importer = CodexImporter(rootURL: fixture.codexRoot, store: store)
        _ = await importer.refresh(scope: .history)

        try fixture.append(.token(
            input: 200,
            cached: 80,
            output: 40,
            reasoning: 10,
            plan: nil,
            second: 7
        ))
        _ = await importer.refresh(scope: .history)

        try fixture.append(.token(
            input: 150,
            cached: 60,
            output: 30,
            reasoning: 8,
            plan: nil,
            second: 8
        ), to: second)
        _ = await importer.refresh(scope: .history)

        XCTAssertEqual(try store.totalUsage(), 300)
        let checkpoints = try CodexSourceDiscovery().discover(rootURL: fixture.codexRoot).rollouts
            .compactMap { try store.fileCheckpoint(fileID: $0.fileID) }
        XCTAssertEqual(Set(checkpoints.compactMap { $0.counters?.input }), [150, 200])
    }

    func testEmbeddedSessionMetadataOverridesStaleIndexThreadWithoutDroppingUsage() async throws {
        let fixture = try CodexFixture.make(events: [
            .sessionCLI,
            .turn(model: "gpt-synthetic"),
            .token(input: 100, cached: 40, output: 20, reasoning: 5, plan: "plus")
        ])
        try fixture.installIndex(
            archived: false,
            childEdgeStatus: "closed",
            updatedAtMilliseconds: 9_000,
            threadID: "stale-index-thread"
        )
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let importer = CodexImporter(rootURL: fixture.codexRoot, store: store)

        let first = await importer.refresh(scope: .history)
        let second = await importer.refresh(scope: .history)

        XCTAssertTrue(first.isSuccessful)
        XCTAssertEqual(second.skippedFileCount, 1)
        XCTAssertEqual(try store.totalUsage(), 120)
        XCTAssertEqual(try store.sessions().map(\.threadID), [CodexFixture.threadID])
        let fileID = try XCTUnwrap(store.sessions().first?.sourceFileID)
        XCTAssertEqual(try store.fileCheckpoint(fileID: fileID)?.threadID, CodexFixture.threadID)
    }

    func testArchiveFactAggregatesAcrossSameThreadFilesInEitherOrderAndRestart() async throws {
        for archivedIsNewer in [false, true] {
            let fixture = try CodexFixture.make(events: [.sessionCLI, .turn(model: "gpt-synthetic")])
            try fixture.setRolloutModificationDate(Date(timeIntervalSince1970: archivedIsNewer ? 1_000 : 3_000))
            _ = try fixture.duplicateRolloutToArchive(
                named: "archived.jsonl",
                modificationDate: Date(timeIntervalSince1970: archivedIsNewer ? 3_000 : 1_000)
            )
            let store = try UsageStore(databaseURL: fixture.databaseURL)

            _ = await CodexImporter(rootURL: fixture.codexRoot, store: store).refresh(scope: .history)
            XCTAssertEqual(try store.sessions().first?.archive, .archived)
            let observedAt = try XCTUnwrap(store.sessions().first?.state.archiveObservedAtMilliseconds)
            XCTAssertEqual(observedAt, 3_000_000)

            _ = await CodexImporter(rootURL: fixture.codexRoot, store: store).refresh(scope: .history)
            XCTAssertEqual(try store.sessions().first?.archive, .archived)
            XCTAssertEqual(try store.sessions().first?.state.archiveObservedAtMilliseconds, observedAt)
        }
    }

    func testIndexArchiveAndChildFactsUpdateWithoutNewJSONLLines() async throws {
        let fixture = try CodexFixture.make(events: [.sessionCLI, .turn(model: "gpt-synthetic")])
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let importer = CodexImporter(rootURL: fixture.codexRoot, store: store)
        _ = await importer.refresh(scope: .history)
        let checkpointBefore = try XCTUnwrap(
            try store.fileCheckpoint(fileID: XCTUnwrap(store.sessions().first?.sourceFileID))
        )
        let rolloutModifiedAt = try XCTUnwrap(
            CodexSourceDiscovery().discover(rootURL: fixture.codexRoot).rollouts.first
        ).modificationTimeMilliseconds

        try fixture.installIndex(archived: true, childEdgeStatus: "open", updatedAtMilliseconds: 9_000)
        _ = await importer.refresh(scope: .history)

        let session = try XCTUnwrap(store.sessions().first)
        XCTAssertEqual(session.archive, .archived)
        XCTAssertEqual(session.childEdgeStatus, "open")
        XCTAssertEqual(session.state.archiveObservedAtMilliseconds, max(9_000, rolloutModifiedAt))
        XCTAssertEqual(
            try store.fileCheckpoint(fileID: checkpointBefore.fileID)?.committedOffset,
            checkpointBefore.committedOffset
        )
    }

    func testNewerExplicitActiveIndexRestoresThreadAfterArchivedFileDisappears() async throws {
        let fixture = try CodexFixture.make(events: [.sessionCLI, .turn(model: "gpt-synthetic")])
        try fixture.setRolloutModificationDate(Date(timeIntervalSince1970: 3_000))
        let archived = try fixture.duplicateRolloutToArchive(
            named: "archived.jsonl",
            modificationDate: Date(timeIntervalSince1970: 2_000)
        )
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let importer = CodexImporter(rootURL: fixture.codexRoot, store: store)
        _ = await importer.refresh(scope: .history)
        XCTAssertEqual(try store.sessions().first?.archive, .archived)
        XCTAssertEqual(try store.sessions().first?.state.archiveObservedAtMilliseconds, 3_000_000)

        try FileManager.default.removeItem(at: archived)
        try fixture.installIndex(
            archived: false,
            childEdgeStatus: "closed",
            updatedAtMilliseconds: 4_000_000
        )
        _ = await importer.refresh(scope: .history)

        XCTAssertEqual(try store.sessions().first?.archive, .active)
        XCTAssertEqual(try store.sessions().first?.state.archiveObservedAtMilliseconds, 4_000_000)
    }

    func testFilesystemArchiveOverridesNewerActiveWhenIndexBecomesUnavailable() async throws {
        for degraded in [false, true] {
            let fixture = try CodexFixture.make(events: [.sessionCLI, .turn(model: "gpt-synthetic")])
            try fixture.setRolloutModificationDate(Date(timeIntervalSince1970: 3_000))
            try fixture.installIndex(
                archived: false,
                childEdgeStatus: "open",
                updatedAtMilliseconds: 4_000_000
            )
            let store = try UsageStore(databaseURL: fixture.databaseURL)
            _ = await CodexImporter(rootURL: fixture.codexRoot, store: store).refresh(scope: .history)
            XCTAssertEqual(try store.sessions().first?.archive, .active)
            XCTAssertEqual(try store.sessions().first?.childEdgeStatus, "open")
            XCTAssertEqual(try store.sessions().first?.state.archiveObservedAtMilliseconds, 4_000_000)

            try fixture.makeIndexUnavailable(degraded: degraded)
            try fixture.archiveRollout()
            let inventory = try CodexSourceDiscovery().discover(rootURL: fixture.codexRoot)
            if degraded {
                guard case .degraded = inventory.indexHealth else {
                    return XCTFail("expected degraded index")
                }
            } else {
                XCTAssertEqual(inventory.indexHealth, .missing)
            }
            _ = await CodexImporter(rootURL: fixture.codexRoot, store: store).refresh(scope: .history)

            XCTAssertEqual(try store.sessions().first?.archive, .archived)
            XCTAssertEqual(try store.sessions().first?.childEdgeStatus, "open")
            XCTAssertEqual(try store.sessions().first?.state.archiveObservedAtMilliseconds, 4_000_000)
        }
    }
}

private actor ImportProgressRecorder {
    private(set) var updates: [CodexImportProgress] = []

    func record(_ progress: CodexImportProgress) {
        updates.append(progress)
    }
}

private struct FixedRepositoryIdentityResolver: RepositoryIdentityResolving {
    let repositoryID: String?

    func repositoryID(forWorkingDirectory workingDirectory: String) -> String? {
        repositoryID
    }
}

private struct MappingRepositoryIdentityResolver: RepositoryIdentityResolving {
    let repositoryIDs: [String: String]

    func repositoryID(forWorkingDirectory workingDirectory: String) -> String? {
        repositoryIDs[workingDirectory]
    }
}

private final class CodexFixture: @unchecked Sendable {
    static let threadID = "00000000-0000-0000-0000-000000000001"

    let codexRoot: URL
    let databaseURL: URL
    private(set) var rolloutURL: URL

    private init(codexRoot: URL, databaseURL: URL, rolloutURL: URL) {
        self.codexRoot = codexRoot
        self.databaseURL = databaseURL
        self.rolloutURL = rolloutURL
    }

    static func make(events: [Event]) throws -> CodexFixture {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CodexVista-CodexImporterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let rollout = root.appending(path: "sessions/2026/07/14/rollout.jsonl")
        try FileManager.default.createDirectory(
            at: rollout.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let fixture = CodexFixture(
            codexRoot: root,
            databaseURL: root.appending(path: "usage.sqlite3"),
            rolloutURL: rollout
        )
        try fixture.replace(events: events)
        return fixture
    }

    func append(_ event: Event) throws {
        try appendRaw(event.line + "\n")
    }

    func append(_ event: Event, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((event.line + "\n").utf8))
    }

    func appendRaw(_ value: String) throws {
        let handle = try FileHandle(forWritingTo: rolloutURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(value.utf8))
    }

    func replace(events: [Event]) throws {
        let data = Data((events.map(\.line).joined(separator: "\n") + "\n").utf8)
        try data.write(to: rolloutURL)
    }

    func archiveRollout() throws {
        let archived = codexRoot.appending(path: "archived_sessions/rollout.jsonl")
        try FileManager.default.createDirectory(
            at: archived.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: rolloutURL, to: archived)
        rolloutURL = archived
    }

    func setRolloutModificationDate(_ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: rolloutURL.path)
    }

    func duplicateRollout(named name: String, modificationDate: Date) throws -> URL {
        let duplicate = rolloutURL.deletingLastPathComponent().appending(path: name)
        try FileManager.default.copyItem(at: rolloutURL, to: duplicate)
        try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: duplicate.path)
        return duplicate
    }

    func duplicateRolloutToArchive(named name: String, modificationDate: Date) throws -> URL {
        let duplicate = codexRoot.appending(path: "archived_sessions/\(name)")
        try FileManager.default.createDirectory(
            at: duplicate.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: rolloutURL, to: duplicate)
        try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: duplicate.path)
        return duplicate
    }

    func installIndex(
        archived: Bool,
        childEdgeStatus: String,
        updatedAtMilliseconds: Int64,
        threadID: String = CodexFixture.threadID
    ) throws {
        let database = try SQLiteDatabase(url: codexRoot.appending(path: "state_1.sqlite"))
        try database.execute(sql: """
            CREATE TABLE threads(
              id TEXT NOT NULL, rollout_path TEXT NOT NULL, source TEXT NOT NULL, model TEXT,
              created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL, archived INTEGER NOT NULL
            )
            """)
        try database.execute(
            sql: "INSERT INTO threads VALUES (?, ?, ?, ?, ?, ?, ?)",
            bindings: [
                .text(threadID), .text(rolloutURL.path), .text("cli"), .text("gpt-index"),
                .integer(1_000), .integer(updatedAtMilliseconds), .integer(archived ? 1 : 0)
            ]
        )
        try database.execute(sql: "CREATE TABLE thread_spawn_edges(child_thread_id TEXT, status TEXT)")
        try database.execute(
            sql: "INSERT INTO thread_spawn_edges VALUES (?, ?)",
            bindings: [.text(threadID), .text(childEdgeStatus)]
        )
    }

    func makeIndexUnavailable(degraded: Bool) throws {
        let fileManager = FileManager.default
        for name in ["state_1.sqlite", "state_1.sqlite-wal", "state_1.sqlite-shm"] {
            let url = codexRoot.appending(path: name)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
        if degraded {
            let database = try SQLiteDatabase(url: codexRoot.appending(path: "state_2.sqlite"))
            try database.execute(sql: "CREATE TABLE unrelated(value TEXT)")
        }
    }

    func rolloutSize() throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: rolloutURL.path)
        return try XCTUnwrap((attributes[.size] as? NSNumber)?.int64Value)
    }

    enum Event {
        case sessionDesktop
        case sessionCLI
        case sessionCLIWithRepository
        case turn(model: String)
        case turnInWorkspace(model: String, roots: [String])
        case started
        case completed
        case activity
        case unknown
        case token(
            input: Int64,
            cached: Int64,
            output: Int64,
            reasoning: Int64,
            plan: String?,
            second: Int = 4
        )

        var line: String {
            switch self {
            case .sessionDesktop:
                return """
                {"type":"session_meta","payload":{"id":"\(CodexFixture.threadID)","originator":"Codex Desktop","cli_version":"1.0.0","cwd":"/synthetic/CodexVistaFixture"}}
                """
            case .sessionCLI:
                return """
                {"type":"session_meta","payload":{"id":"\(CodexFixture.threadID)","source":"cli","cli_version":"1.0.0","cwd":"/synthetic/CodexVistaFixture"}}
                """
            case .sessionCLIWithRepository:
                return """
                {"type":"session_meta","payload":{"id":"\(CodexFixture.threadID)","source":"cli","cli_version":"1.0.0","cwd":"/synthetic/CodexVistaFixture","git":{"commit_hash":"abc123","repository_url":"git@github.com:ychp-ai/CodexVista.git"}}}
                """
            case let .turn(model):
                return """
                {"type":"turn_context","payload":{"turn_id":"turn-1","model":"\(model)"}}
                """
            case let .turnInWorkspace(model, roots):
                let rootsJSON = roots.map { "\"\($0)\"" }.joined(separator: ",")
                return """
                {"type":"turn_context","payload":{"turn_id":"turn-1","model":"\(model)","workspace_roots":[\(rootsJSON)]}}
                """
            case .started:
                return """
                {"timestamp":"2026-07-14T01:02:03.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
                """
            case .completed:
                return """
                {"timestamp":"2026-07-14T01:02:05.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1"}}
                """
            case .activity:
                return #"""
                {"timestamp":"2026-07-14T01:02:04.000Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","call_id":"call-activity","arguments":"{\"cmd\":\"sed -n '1,200p' /Users/example/.agents/skills/ai-code-review/SKILL.md\"}"}}
                """#
            case .unknown:
                return """
                {"type":"future_event","payload":{"synthetic":true}}
                """
            case let .token(input, cached, output, reasoning, plan, second):
                let planField = plan.map { ",\"plan_type\":\"\($0)\"" } ?? ""
                return """
                {"timestamp":"2026-07-14T01:02:\(String(format: "%02d", second)).000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),"output_tokens":\(output),"reasoning_output_tokens":\(reasoning)}},"rate_limits":{"primary":{"used_percent":25,"window_minutes":300,"resets_at":2000000000},"secondary":{"used_percent":50,"window_minutes":10080,"resets_at":2000100000}\(planField)}}}
                """
            }
        }
    }
}
