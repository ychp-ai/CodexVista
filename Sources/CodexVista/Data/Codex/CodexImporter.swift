import CryptoKit
import Foundation

enum ImportScope: Sendable, Equatable {
    case foreground
    case history
}

enum ImportIssueKind: String, Sendable {
    case discovery
    case index
    case read
    case decode
    case store
    case unsupportedFormat
}

struct ImportIssue: Sendable, Equatable {
    let kind: ImportIssueKind
    let fileID: String?
    let detail: String
}

struct ImportResult: Sendable {
    let scope: ImportScope
    let processedFileCount: Int
    let skippedFileCount: Int
    let issues: [ImportIssue]
    let indexHealth: CodexIndexHealth
    let discoveredFileIDs: [String]?

    var isSuccessful: Bool { issues.isEmpty }
}

struct CodexImportProgress: Sendable, Equatable {
    enum Stage: Sendable, Equatable {
        case resetting
        case discovering
        case importing
        case finalizing
    }

    let stage: Stage
    let completedFileCount: Int
    let totalFileCount: Int?

    static let resetting = CodexImportProgress(
        stage: .resetting,
        completedFileCount: 0,
        totalFileCount: nil
    )

    static let discovering = CodexImportProgress(
        stage: .discovering,
        completedFileCount: 0,
        totalFileCount: nil
    )

    static func importing(completed: Int, total: Int) -> CodexImportProgress {
        CodexImportProgress(
            stage: .importing,
            completedFileCount: completed,
            totalFileCount: total
        )
    }

    static func finalizing(total: Int) -> CodexImportProgress {
        CodexImportProgress(
            stage: .finalizing,
            completedFileCount: total,
            totalFileCount: total
        )
    }

    var fractionCompleted: Double? {
        guard let totalFileCount else { return nil }
        guard totalFileCount > 0 else { return 1 }
        return min(max(Double(completedFileCount) / Double(totalFileCount), 0), 1)
    }
}

typealias CodexImportProgressHandler = @Sendable (CodexImportProgress) async -> Void

actor CodexImporter {
    private let rootURL: URL
    private let store: UsageStore
    private let discovery: CodexSourceDiscovery
    private let reader: IncrementalJSONLReader
    private let decoder: CodexEventDecoder
    private let repositoryResolver: any RepositoryIdentityResolving
    private let calendar: Calendar
    private var resolvedProjects: [String: ProjectIdentity] = [:]
    private var workspaceCatalogByID: [String: WorkspaceIdentity] = [:]
    private var workspaceRootRepositoryIDs: [String: String] = [:]
    private var attemptedWorkspaceRootRepositories: Set<String> = []
    private var workspaceBindingRepairSignatures: [String: String] = [:]

    init(
        rootURL: URL,
        store: UsageStore,
        discovery: CodexSourceDiscovery = CodexSourceDiscovery(),
        reader: IncrementalJSONLReader = IncrementalJSONLReader(),
        decoder: CodexEventDecoder = CodexEventDecoder(),
        repositoryResolver: any RepositoryIdentityResolving = GitRepositoryIdentityResolver(),
        calendar: Calendar = .current
    ) {
        self.rootURL = rootURL
        self.store = store
        self.discovery = discovery
        self.reader = reader
        self.decoder = decoder
        self.repositoryResolver = repositoryResolver
        self.calendar = calendar
    }

    func rebuildFromLocalData(
        progress: CodexImportProgressHandler? = nil
    ) async -> ImportResult {
        await progress?(.resetting)
        resolvedProjects = [:]
        workspaceRootRepositoryIDs = [:]
        attemptedWorkspaceRootRepositories = []
        workspaceBindingRepairSignatures = [:]
        do {
            try store.resetImportedData()
        } catch {
            return ImportResult(
                scope: .history,
                processedFileCount: 0,
                skippedFileCount: 0,
                issues: [.init(kind: .store, fileID: nil, detail: "data-reset-failed")],
                indexHealth: .degraded("data reset failed"),
                discoveredFileIDs: nil
            )
        }
        return await refresh(scope: .history, progress: progress)
    }

    func refresh(
        scope: ImportScope,
        progress: CodexImportProgressHandler? = nil
    ) async -> ImportResult {
        await progress?(.discovering)
        let inventory: CodexSourceInventory
        do {
            inventory = try discovery.discover(rootURL: rootURL)
        } catch {
            return ImportResult(
                scope: scope,
                processedFileCount: 0,
                skippedFileCount: 0,
                issues: [.init(kind: .discovery, fileID: nil, detail: "discovery-failed")],
                indexHealth: .degraded("discovery failed"),
                discoveredFileIDs: nil
            )
        }

        do {
            var discoveredWorkspaces: [WorkspaceIdentity] = []
            for metadata in inventory.workspaceMetadata {
                var matchingWorkspaceIDs: Set<String> = []
                for roots in metadata.historicalRootPaths {
                    if let identity = resolvedWorkspace(
                        rootPaths: roots, project: nil, preferredName: metadata.name
                    ) {
                        discoveredWorkspaces.append(identity)
                        matchingWorkspaceIDs.insert(identity.id)
                    }
                    if let pathIdentity = WorkspaceIdentity.resolve(rootPaths: projectRootPaths(roots)) {
                        matchingWorkspaceIDs.insert(pathIdentity.id)
                    }
                }
                let paths = Set(projectRootPaths(metadata.rootPaths).compactMap { path -> String? in
                    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return nil }
                    return URL(fileURLWithPath: trimmed).standardizedFileURL.path
                })
                let directories = paths.sorted().compactMap { path -> WorkspaceDirectory? in
                    guard let project = ProjectIdentity.resolve(cwd: path) else { return nil }
                    return WorkspaceDirectory(id: project.id, name: project.name)
                }
                try store.upsertWorkspaceConfiguration(
                    StoredWorkspaceConfiguration(
                        id: metadata.configurationID,
                        name: metadata.name,
                        directories: directories,
                        updatedAtMilliseconds: metadata.updatedAtMilliseconds
                    ),
                    matchingWorkspaceIDs: matchingWorkspaceIDs,
                    isCurrent: metadata.isCurrent
                )
            }
            try store.upsertWorkspaceCatalog(discoveredWorkspaces)
            workspaceCatalogByID = try store.workspaceCatalog()
            try repairHistoricalWorkspaceBindings(inventory: inventory)
        } catch {
            return ImportResult(
                scope: scope,
                processedFileCount: 0,
                skippedFileCount: 0,
                issues: [.init(kind: .store, fileID: nil, detail: "workspace-catalog-failed")],
                indexHealth: inventory.indexHealth,
                discoveredFileIDs: inventory.rollouts.map(\.fileID)
            )
        }

        var issues: [ImportIssue] = []
        if case .degraded = inventory.indexHealth {
            issues.append(.init(kind: .index, fileID: nil, detail: "index-degraded"))
        }

        let selected: [RolloutFile]
        do {
            if try importedDataRequiresRebuild(for: inventory.rollouts) {
                try store.resetImportedData()
                selected = selectedRollouts(from: inventory.rollouts, scope: .history)
            } else {
                selected = selectedRollouts(from: inventory.rollouts, scope: scope)
            }
        } catch {
            return ImportResult(
                scope: scope,
                processedFileCount: 0,
                skippedFileCount: 0,
                issues: [.init(kind: .store, fileID: nil, detail: "checkpoint-reset-failed")],
                indexHealth: inventory.indexHealth,
                discoveredFileIDs: inventory.rollouts.map(\.fileID)
            )
        }
        var processed = 0
        var skipped = inventory.rollouts.count - selected.count
        var completed = 0
        await progress?(.importing(completed: completed, total: selected.count))
        var archiveFacts = seedArchiveFacts(inventory: inventory, issues: &issues)
        for rollout in selected {
            switch importRollout(
                rollout,
                inventory: inventory,
                archiveFacts: &archiveFacts
            ) {
            case .processed(let issue):
                processed += 1
                if let issue { issues.append(issue) }
            case .skipped:
                skipped += 1
            case .failed(let issue):
                issues.append(issue)
            }
            completed += 1
            await progress?(.importing(completed: completed, total: selected.count))
        }

        return ImportResult(
            scope: scope,
            processedFileCount: processed,
            skippedFileCount: skipped,
            issues: issues,
            indexHealth: inventory.indexHealth,
            discoveredFileIDs: inventory.rollouts.map(\.fileID)
        )
    }

    private func selectedRollouts(from rollouts: [RolloutFile], scope: ImportScope) -> [RolloutFile] {
        let sorted = rollouts.sorted {
            if $0.modificationTimeMilliseconds != $1.modificationTimeMilliseconds {
                return $0.modificationTimeMilliseconds > $1.modificationTimeMilliseconds
            }
            return $0.fileID < $1.fileID
        }
        guard scope == .foreground, !sorted.isEmpty else { return sorted }

        let startOfDay = calendar.startOfDay(for: Date())
        let startMilliseconds = Int64((startOfDay.timeIntervalSince1970 * 1_000).rounded())
        let newestFileID = sorted[0].fileID
        return sorted.filter {
            $0.modificationTimeMilliseconds >= startMilliseconds || $0.fileID == newestFileID
        }
    }

    private func importedDataRequiresRebuild(for rollouts: [RolloutFile]) throws -> Bool {
        for rollout in rollouts {
            guard let checkpoint = try store.fileCheckpoint(fileID: rollout.fileID) else { continue }
            if checkpoint.path != rollout.url.path
                || UInt64(bitPattern: checkpoint.deviceID) != rollout.deviceID
                || UInt64(bitPattern: checkpoint.inode) != rollout.inode
                || checkpoint.committedOffset > rollout.fileSize {
                return true
            }
        }
        return false
    }

    private func seedArchiveFacts(
        inventory: CodexSourceInventory,
        issues: inout [ImportIssue]
    ) -> [String: ThreadArchiveFact] {
        var facts: [String: ThreadArchiveFact] = [:]
        for record in inventory.threadIndex {
            facts[record.threadID] = ThreadArchiveFact(
                archived: record.archived,
                observedAtMilliseconds: record.updatedAtMilliseconds,
                hasFilesystemArchive: false
            )
        }
        for rollout in inventory.rollouts {
            let threadID: String?
            do {
                threadID = try store.fileCheckpoint(fileID: rollout.fileID)?.threadID
                    ?? rollout.thread?.threadID
            } catch {
                issues.append(.init(
                    kind: .store,
                    fileID: rollout.fileID,
                    detail: "checkpoint-read-failed"
                ))
                continue
            }
            guard let threadID else { continue }
            mergeArchiveFact(
                threadID: threadID,
                rollout: rollout,
                index: indexRecord(for: threadID, rollout: rollout, inventory: inventory),
                into: &facts
            )
        }
        return facts
    }

    private func mergeArchiveFact(
        threadID: String,
        rollout: RolloutFile,
        index: ThreadIndexRecord?,
        into facts: inout [String: ThreadArchiveFact]
    ) {
        let archived = rollout.isArchived || index?.archived == true
        let observedAt = max(
            rollout.modificationTimeMilliseconds,
            index?.updatedAtMilliseconds ?? rollout.modificationTimeMilliseconds
        )
        if let existing = facts[threadID] {
            facts[threadID] = ThreadArchiveFact(
                archived: existing.archived || archived,
                observedAtMilliseconds: max(existing.observedAtMilliseconds, observedAt),
                hasFilesystemArchive: existing.hasFilesystemArchive || rollout.isArchived
            )
        } else {
            facts[threadID] = ThreadArchiveFact(
                archived: archived,
                observedAtMilliseconds: observedAt,
                hasFilesystemArchive: rollout.isArchived
            )
        }
    }

    private func indexRecord(
        for threadID: String,
        rollout: RolloutFile,
        inventory: CodexSourceInventory
    ) -> ThreadIndexRecord? {
        if rollout.thread?.threadID == threadID { return rollout.thread }
        return inventory.threadIndex.first { $0.threadID == threadID }
    }

    private func importRollout(
        _ rollout: RolloutFile,
        inventory: CodexSourceInventory,
        archiveFacts: inout [String: ThreadArchiveFact]
    ) -> FileImportOutcome {
        let previousFile: FileCheckpoint?
        let storedSessions: [StoredSession]
        do {
            previousFile = try store.fileCheckpoint(fileID: rollout.fileID)
            storedSessions = try store.sessions()
        } catch {
            return .failed(.init(kind: .store, fileID: rollout.fileID, detail: "checkpoint-read-failed"))
        }

        let storedByThread = Dictionary(uniqueKeysWithValues: storedSessions.map { ($0.threadID, $0) })
        let recoveredThreadID = previousFile?.threadID ?? rollout.thread?.threadID
        let storedForThread = recoveredThreadID.flatMap { storedByThread[$0] }
        let archiveFact = recoveredThreadID.flatMap { archiveFacts[$0] }
        if canSkip(
            rollout,
            previousFile: previousFile,
            storedSession: storedForThread,
            inventory: inventory,
            archiveFact: archiveFact
        ) {
            return .skipped
        }

        let readBatch: JSONLReadBatch
        do {
            readBatch = try reader.read(
                file: rollout.url,
                fromOffset: previousFile?.committedOffset ?? 0
            )
        } catch {
            return .failed(.init(kind: .read, fileID: rollout.fileID, detail: "read-failed"))
        }

        let now = currentMilliseconds()
        if readBatch.wasTruncated {
            let threadID = recoveredThreadID
            var checkpoints: [ThreadCheckpoint] = []
            if let threadID {
                do {
                    let previousThread = try store.threadCheckpoint(threadID: threadID)
                    checkpoints = [ThreadCheckpoint(
                        threadID: threadID,
                        currentModel: previousThread?.currentModel,
                        currentTurnID: previousThread?.currentTurnID,
                        currentPlan: previousThread?.currentPlan,
                        counters: nil,
                        counterSegment: (previousThread?.counterSegment ?? 0) + 1,
                        lastTokenAtMilliseconds: previousThread?.lastTokenAtMilliseconds,
                        currentWorkspace: previousThread?.currentWorkspace
                    )]
                } catch {
                    return .failed(.init(
                        kind: .store,
                        fileID: rollout.fileID,
                        detail: "checkpoint-read-failed"
                    ))
                }
            }
            let file = makeFileCheckpoint(
                rollout: rollout,
                threadID: threadID,
                committedOffset: 0,
                generation: (previousFile?.generation ?? 0) + 1,
                lastRecordAtMilliseconds: previousFile?.lastRecordAtMilliseconds,
                lastSuccessAtMilliseconds: now,
                formatStatus: "supported",
                lastError: nil,
                activityCommittedOffset: 0
            )
            do {
                try store.commit(ImportBatch(
                    file: file,
                    usageEvents: [],
                    quotaEvents: [],
                    stateEvents: [],
                    sessions: [],
                    threadCheckpoints: checkpoints
                ))
                return .processed(issue: nil)
            } catch {
                return .failed(.init(kind: .store, fileID: rollout.fileID, detail: "transaction-failed"))
            }
        }

        var context: ImportContext
        do {
            context = try makeContext(
                rollout: rollout,
                previousFile: previousFile,
                recoveredThreadID: recoveredThreadID,
                storedSession: storedForThread,
                storedByThread: storedByThread
            )
        } catch {
            return .failed(.init(
                kind: .store,
                fileID: rollout.fileID,
                detail: "checkpoint-read-failed"
            ))
        }
        var usageEvents: [StoredUsageEvent] = []
        var quotaEvents: [StoredQuotaEvent] = []
        var stateEvents: [StoredSessionStateEvent] = []
        var activityEvents: [StoredActivityEvent] = []
        var committedOffset = previousFile?.committedOffset ?? 0
        var activityCommittedOffset = previousFile?.activityCommittedOffset ?? 0
        var lineIssue: ImportIssue?

        let activityReadBatch: JSONLReadBatch?
        do {
            let initial = try reader.read(file: rollout.url, fromOffset: activityCommittedOffset)
            activityReadBatch = initial.wasTruncated
                ? try reader.read(file: rollout.url, fromOffset: 0)
                : initial
        } catch {
            activityReadBatch = nil
        }

        if let activityReadBatch {
            var activityContext = ActivityImportContext(
                threadID: recoveredThreadID,
                source: storedForThread?.sourceKind ?? sourceKind(from: rollout.thread?.sourceRaw),
                turnID: storedForThread?.activeTurnID
            )
            for line in activityReadBatch.lines {
                if let event = try? decoder.decode(line: line.data) {
                    consumeActivity(
                        event,
                        lineOffset: line.endOffset,
                        rollout: rollout,
                        context: &activityContext,
                        activityEvents: &activityEvents
                    )
                }
            }
            activityCommittedOffset = activityReadBatch.committedOffset
        }

        for line in readBatch.lines {
            // Activity records have their own best-effort scanner and checkpoint. Keeping them
            // out of the usage decoder path ensures a future or malformed activity payload can
            // never prevent token, quota, or session history from advancing.
            if decoder.isResponseItem(line: line.data) {
                committedOffset = line.endOffset
                continue
            }
            let event: CodexDecodedEvent?
            do {
                event = try decoder.decode(line: line.data)
            } catch {
                lineIssue = .init(kind: .decode, fileID: rollout.fileID, detail: "malformed-event")
                break
            }

            guard let event else {
                committedOffset = line.endOffset
                continue
            }

            do {
                try consume(
                    event,
                    lineOffset: line.endOffset,
                    rollout: rollout,
                    storedByThread: storedByThread,
                    context: &context,
                    usageEvents: &usageEvents,
                    quotaEvents: &quotaEvents,
                    stateEvents: &stateEvents
                )
                committedOffset = line.endOffset
            } catch let issue as ImportContextIssue {
                lineIssue = .init(
                    kind: .unsupportedFormat,
                    fileID: rollout.fileID,
                    detail: issue.detail
                )
                break
            } catch {
                lineIssue = .init(kind: .store, fileID: rollout.fileID, detail: "checkpoint-read-failed")
                break
            }
        }

        if let threadID = context.threadID {
            mergeArchiveFact(
                threadID: threadID,
                rollout: rollout,
                index: indexRecord(for: threadID, rollout: rollout, inventory: inventory),
                into: &archiveFacts
            )
        }
        applyInventoryFacts(
            rollout: rollout,
            inventory: inventory,
            storedSession: context.threadID.flatMap { storedByThread[$0] },
            archiveFact: context.threadID.flatMap { archiveFacts[$0] },
            context: &context
        )

        var sessions: [StoredSession] = []
        var threadCheckpoints: [ThreadCheckpoint] = []
        if let threadID = context.threadID {
            sessions = [StoredSession(
                threadID: threadID,
                sourceKind: context.source,
                createdAtMilliseconds: context.createdAtMilliseconds,
                updatedAtMilliseconds: context.updatedAtMilliseconds,
                state: context.state ?? .empty(threadID: threadID),
                lastModel: context.model,
                lastPlan: context.lastPlan,
                sourceFileID: rollout.fileID
            )]
            threadCheckpoints = [ThreadCheckpoint(
                threadID: threadID,
                currentModel: context.model,
                currentTurnID: context.currentTurnID,
                currentPlan: context.currentPlan,
                counters: context.counters,
                counterSegment: context.counterSegment,
                lastTokenAtMilliseconds: context.lastTokenAtMilliseconds,
                currentWorkspace: context.workspace
            )]
        }

        let hadCompleteLine = !readBatch.lines.isEmpty
        let file = makeFileCheckpoint(
            rollout: rollout,
            threadID: context.threadID ?? recoveredThreadID,
            committedOffset: committedOffset,
            generation: previousFile?.generation ?? 0,
            lastRecordAtMilliseconds: hadCompleteLine
                ? rollout.modificationTimeMilliseconds
                : previousFile?.lastRecordAtMilliseconds,
            lastSuccessAtMilliseconds: lineIssue == nil ? now : previousFile?.lastSuccessAtMilliseconds,
            formatStatus: lineIssue == nil ? "supported" : "error",
            lastError: lineIssue?.detail,
            activityCommittedOffset: activityCommittedOffset,
            context: context
        )

        do {
            try store.commit(ImportBatch(
                file: file,
                usageEvents: usageEvents,
                quotaEvents: quotaEvents,
                stateEvents: stateEvents,
                activityEvents: activityEvents,
                sessions: sessions,
                threadCheckpoints: threadCheckpoints
            ))
            return .processed(issue: lineIssue)
        } catch {
            return .failed(.init(kind: .store, fileID: rollout.fileID, detail: "transaction-failed"))
        }
    }

    private func consume(
        _ event: CodexDecodedEvent,
        lineOffset: Int64,
        rollout: RolloutFile,
        storedByThread: [String: StoredSession],
        context: inout ImportContext,
        usageEvents: inout [StoredUsageEvent],
        quotaEvents: inout [StoredQuotaEvent],
        stateEvents: inout [StoredSessionStateEvent]
    ) throws {
        switch event {
        case .session(let metadata):
            if context.threadID != metadata.threadID {
                context = contextForSession(
                    metadata,
                    rollout: rollout,
                    storedSession: storedByThread[metadata.threadID]
                )
            }
            context.threadID = metadata.threadID
            context.source = metadata.source
            if let project = resolvedProject(from: metadata) { context.project = project }

        case .turn(let turn):
            guard context.threadID != nil else { throw ImportContextIssue.missingThread }
            context.currentTurnID = turn.turnID
            context.model = turn.model
            context.workspace = resolvedWorkspace(
                rootPaths: turn.workspaceRootPaths,
                project: context.project
            ) ?? turn.workspace.flatMap { workspaceCatalogByID[$0.id] ?? $0 }
                ?? WorkspaceIdentity.inferFromProject(context.project)
                ?? .unknown

        case .token(let snapshot):
            guard let threadID = context.threadID else { throw ImportContextIssue.missingThread }
            let counters = snapshot.counters
            let effectivePlan: PlanResolution
            if let raw = snapshot.planRaw {
                let resolved = PlanResolver.resolve(rawValue: raw)
                if !resolved.isInferred { context.currentPlan = resolved }
                effectivePlan = resolved.isInferred ? (context.currentPlan ?? resolved) : resolved
            } else {
                effectivePlan = context.currentPlan ?? PlanResolver.resolve(rawValue: nil)
            }
            context.lastPlan = effectivePlan.kind

            if let counters {
                let previous = context.counters ?? TokenCounters(
                    input: 0,
                    cachedInput: 0,
                    output: 0,
                    reasoning: 0
                )
                if context.counters != nil, countersRolledBack(from: previous, to: counters) {
                    context.counterSegment += 1
                }
                if let delta = UsageAccumulator.delta(previous: previous, current: counters) {
                    usageEvents.append(StoredUsageEvent(
                        fingerprint: fingerprint(canonicalUsage(
                            threadID: threadID,
                            counterSegment: context.counterSegment,
                            counters: counters
                        )),
                        observedAtMilliseconds: snapshot.observedAtMilliseconds,
                        threadID: threadID,
                        turnID: context.currentTurnID,
                        sourceKind: context.source,
                        model: context.model ?? rollout.thread?.model ?? "Unknown Model",
                        plan: effectivePlan,
                        usage: delta,
                        sourceFileID: rollout.fileID,
                        sourceOffset: lineOffset,
                        project: context.project ?? .unknown,
                        workspace: context.workspace
                            ?? WorkspaceIdentity.inferFromProject(context.project)
                            ?? .unknown
                    ))
                }
                context.counters = counters
                context.lastTokenAtMilliseconds = snapshot.observedAtMilliseconds
            }

            for raw in snapshot.quotas {
                guard let observation = QuotaNormalizer.normalize(
                    [raw],
                    plan: effectivePlan,
                    observedAtMilliseconds: snapshot.observedAtMilliseconds
                ).first else { continue }
                quotaEvents.append(StoredQuotaEvent(
                    fingerprint: fingerprint(canonicalQuota(
                        threadID: threadID,
                        observedAtMilliseconds: snapshot.observedAtMilliseconds,
                        window: raw
                    )),
                    threadID: threadID,
                    observation: observation,
                    sourceKind: context.source
                ))
            }

        case .lifecycle(let lifecycle):
            guard let threadID = context.threadID else { throw ImportContextIssue.missingThread }
            if let turnID = lifecycle.turnID {
                context.currentTurnID = turnID
            }
            let canonical = canonicalState(threadID: threadID, event: lifecycle)
            let eventKey = fingerprint(canonical)
            context.state = SessionStateReducer.reduce(
                current: context.state ?? .empty(threadID: threadID),
                event: lifecycle,
                eventKey: eventKey
            )
            stateEvents.append(StoredSessionStateEvent(
                fingerprint: eventKey,
                threadID: threadID,
                turnID: lifecycle.turnID,
                observedAtMilliseconds: lifecycle.observedAtMilliseconds,
                kind: lifecycle.kind,
                sourceFileID: rollout.fileID,
                sourceOffset: lineOffset
            ))

        case .activity:
            break
        }
    }

    private func consumeActivity(
        _ event: CodexDecodedEvent,
        lineOffset: Int64,
        rollout: RolloutFile,
        context: inout ActivityImportContext,
        activityEvents: inout [StoredActivityEvent]
    ) {
        switch event {
        case .session(let metadata):
            context.threadID = metadata.threadID
            context.source = metadata.source

        case .turn(let turn):
            context.turnID = turn.turnID

        case .lifecycle(let lifecycle):
            switch lifecycle.kind {
            case .started:
                context.turnID = lifecycle.turnID ?? context.turnID
            case .completed, .interrupted:
                if lifecycle.turnID == nil || lifecycle.turnID == context.turnID {
                    context.turnID = nil
                }
            case .rolledBack:
                break
            }

        case .activity(let snapshot):
            guard let threadID = context.threadID else { return }
            let callKey = snapshot.callID ?? "offset-\(lineOffset)"
            for (index, name) in snapshot.toolNames.enumerated() where !name.isEmpty {
                let canonical = "activity|tool|\(threadID)|\(snapshot.observedAtMilliseconds)|\(callKey)|\(name)|\(index)"
                activityEvents.append(StoredActivityEvent(
                    fingerprint: fingerprint(canonical),
                    observedAtMilliseconds: snapshot.observedAtMilliseconds,
                    threadID: threadID,
                    turnID: context.turnID,
                    kind: .tool,
                    name: name,
                    sourceKind: context.source,
                    sourceFileID: rollout.fileID,
                    sourceOffset: lineOffset
                ))
            }

            let turnKey = context.turnID ?? "offset-\(lineOffset)"
            for name in snapshot.skillNames where !name.isEmpty {
                let canonical = "activity|skill|\(threadID)|\(turnKey)|\(name)"
                activityEvents.append(StoredActivityEvent(
                    fingerprint: fingerprint(canonical),
                    observedAtMilliseconds: snapshot.observedAtMilliseconds,
                    threadID: threadID,
                    turnID: context.turnID,
                    kind: .skill,
                    name: name,
                    sourceKind: context.source,
                    sourceFileID: rollout.fileID,
                    sourceOffset: lineOffset
                ))
            }

        case .token:
            break
        }
    }

    private func contextForSession(
        _ metadata: SessionMetadata,
        rollout: RolloutFile,
        storedSession: StoredSession?
    ) -> ImportContext {
        let matchingIndex = rollout.thread?.threadID == metadata.threadID ? rollout.thread : nil
        return ImportContext(
            threadID: metadata.threadID,
            source: metadata.source,
            model: matchingIndex?.model ?? storedSession?.lastModel,
            currentTurnID: storedSession?.activeTurnID,
            currentPlan: nil,
            lastPlan: storedSession?.lastPlan,
            counters: nil,
            counterSegment: 0,
            lastTokenAtMilliseconds: nil,
            project: metadata.project,
            workspace: nil,
            state: storedSession?.state ?? .empty(threadID: metadata.threadID),
            createdAtMilliseconds: matchingIndex?.createdAtMilliseconds ?? storedSession?.createdAtMilliseconds,
            updatedAtMilliseconds: matchingIndex?.updatedAtMilliseconds ?? storedSession?.updatedAtMilliseconds
        )
    }

    private func resolvedProject(from metadata: SessionMetadata) -> ProjectIdentity? {
        guard let project = metadata.project else { return nil }
        if project.repositoryID != nil {
            resolvedProjects[project.id] = project
            return project
        }
        if let cached = resolvedProjects[project.id] { return cached }
        let repositoryID = metadata.workingDirectory.flatMap {
            repositoryResolver.repositoryID(forWorkingDirectory: $0)
        }
        let resolved = project.associating(repositoryID: repositoryID)
        resolvedProjects[project.id] = resolved
        return resolved
    }

    private func makeContext(
        rollout: RolloutFile,
        previousFile: FileCheckpoint?,
        recoveredThreadID: String?,
        storedSession: StoredSession?,
        storedByThread: [String: StoredSession]
    ) throws -> ImportContext {
        let threadID = recoveredThreadID ?? rollout.thread?.threadID
        let session = threadID.flatMap { storedByThread[$0] } ?? storedSession
        return ImportContext(
            threadID: threadID,
            source: session?.sourceKind ?? sourceKind(from: rollout.thread?.sourceRaw),
            model: previousFile?.currentModel ?? session?.lastModel ?? rollout.thread?.model,
            currentTurnID: previousFile?.currentTurnID ?? session?.activeTurnID,
            currentPlan: previousFile?.currentPlan,
            lastPlan: previousFile?.currentPlan?.kind ?? session?.lastPlan,
            counters: previousFile?.counters,
            counterSegment: previousFile?.counterSegment ?? 0,
            lastTokenAtMilliseconds: previousFile?.lastTokenAtMilliseconds,
            project: previousFile?.project,
            workspace: previousFile?.workspace,
            state: session?.state ?? threadID.map(SessionStateSnapshot.empty(threadID:)),
            createdAtMilliseconds: rollout.thread?.createdAtMilliseconds ?? session?.createdAtMilliseconds,
            updatedAtMilliseconds: rollout.thread?.updatedAtMilliseconds ?? session?.updatedAtMilliseconds
        )
    }

    private func applyInventoryFacts(
        rollout: RolloutFile,
        inventory: CodexSourceInventory,
        storedSession: StoredSession?,
        archiveFact: ThreadArchiveFact?,
        context: inout ImportContext
    ) {
        guard let threadID = context.threadID else { return }
        let index = indexRecord(for: threadID, rollout: rollout, inventory: inventory)
        var state = context.state ?? storedSession?.state ?? .empty(threadID: threadID)
        if let archiveFact {
            let observedAt = archiveFact.hasFilesystemArchive
                ? max(
                    archiveFact.observedAtMilliseconds,
                    state.archiveObservedAtMilliseconds ?? archiveFact.observedAtMilliseconds
                )
                : archiveFact.observedAtMilliseconds
            state = SessionStateReducer.setArchived(
                current: state,
                archived: archiveFact.archived,
                observedAtMilliseconds: observedAt
            )
        }
        if let childEdgeStatus = index?.childEdgeStatus {
            state = SessionStateReducer.setChildEdgeStatus(current: state, status: childEdgeStatus)
        }
        context.state = state
        context.createdAtMilliseconds = index?.createdAtMilliseconds ?? context.createdAtMilliseconds
        context.updatedAtMilliseconds = index?.updatedAtMilliseconds ?? context.updatedAtMilliseconds
        if context.model == nil { context.model = index?.model }
    }

    private func canSkip(
        _ rollout: RolloutFile,
        previousFile: FileCheckpoint?,
        storedSession: StoredSession?,
        inventory: CodexSourceInventory,
        archiveFact: ThreadArchiveFact?
    ) -> Bool {
        guard let previousFile,
              previousFile.fileSize == rollout.fileSize,
              previousFile.committedOffset == rollout.fileSize,
              previousFile.activityCommittedOffset == rollout.fileSize,
              previousFile.path == rollout.url.path,
              previousFile.formatStatus == "supported",
              let storedSession else {
            return false
        }
        let index = indexRecord(for: storedSession.threadID, rollout: rollout, inventory: inventory)
        if let archiveFact {
            let desiredArchive: SessionArchiveState = archiveFact.archived ? .archived : .active
            guard storedSession.archive == desiredArchive,
                  let observed = storedSession.state.archiveObservedAtMilliseconds,
                  observed >= archiveFact.observedAtMilliseconds else {
                return false
            }
        }
        if let explicitStatus = index?.childEdgeStatus {
            return storedSession.childEdgeStatus == explicitStatus
        }
        return true
    }

    private func makeFileCheckpoint(
        rollout: RolloutFile,
        threadID: String?,
        committedOffset: Int64,
        generation: Int64,
        lastRecordAtMilliseconds: Int64?,
        lastSuccessAtMilliseconds: Int64?,
        formatStatus: String,
        lastError: String?,
        activityCommittedOffset: Int64 = 0,
        context: ImportContext? = nil
    ) -> FileCheckpoint {
        FileCheckpoint(
            fileID: rollout.fileID,
            deviceID: Int64(bitPattern: rollout.deviceID),
            inode: Int64(bitPattern: rollout.inode),
            path: rollout.url.path,
            fileSize: rollout.fileSize,
            committedOffset: committedOffset,
            generation: generation,
            threadID: threadID,
            lastRecordAtMilliseconds: lastRecordAtMilliseconds,
            lastSuccessAtMilliseconds: lastSuccessAtMilliseconds,
            formatStatus: formatStatus,
            lastError: lastError,
            currentModel: context?.model,
            currentTurnID: context?.currentTurnID,
            currentPlan: context?.currentPlan,
            counters: context?.counters,
            counterSegment: context?.counterSegment ?? 0,
            lastTokenAtMilliseconds: context?.lastTokenAtMilliseconds,
            activityCommittedOffset: activityCommittedOffset,
            project: context?.project,
            workspace: context?.workspace
        )
    }

    private func sourceKind(from raw: String?) -> CodexSourceKind {
        raw == "cli" ? .cli : .unknown
    }

    // Only Codex's dated, per-task visualization output roots are auxiliary.
    // UUID-named business directories and real multi-root projects remain intact.
    private func projectRootPaths(_ paths: [String]) -> [String] {
        let base = rootURL.appending(path: "visualizations").standardizedFileURL.path + "/"
        return paths.filter { rawPath in
            let path = URL(fileURLWithPath: rawPath.trimmingCharacters(in: .whitespacesAndNewlines))
                .standardizedFileURL.path
            guard path.hasPrefix(base) else { return true }
            let parts = path.dropFirst(base.count).split(separator: "/")
            guard parts.count == 4,
                  parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
                  parts.prefix(3).allSatisfy({ $0.allSatisfy(\.isNumber) }),
                  UUID(uuidString: String(parts[3])) != nil else { return true }
            return false
        }
    }

    private func resolvedWorkspace(
        rootPaths: [String]?,
        project: ProjectIdentity?,
        preferredName: String? = nil
    ) -> WorkspaceIdentity? {
        let normalizedRoots = Array(Set(projectRootPaths(rootPaths ?? []).compactMap { rawPath -> String? in
            let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return URL(fileURLWithPath: trimmed).standardizedFileURL.path
        })).sorted()
        guard !normalizedRoots.isEmpty else { return nil }

        var repositoryIDsByRootPath: [String: String] = [:]
        for rootPath in normalizedRoots {
            if let repositoryID = workspaceRepositoryID(for: rootPath) {
                repositoryIDsByRootPath[rootPath] = repositoryID
            }
        }
        let rootName = normalizedRoots.count == 1
            ? URL(fileURLWithPath: normalizedRoots[0]).lastPathComponent : nil
        let fallbackRepositoryID: String?
        if normalizedRoots.count == 1, rootName == project?.name {
            fallbackRepositoryID = project?.repositoryID
        } else {
            fallbackRepositoryID = nil
        }
        guard let identity = WorkspaceIdentity.resolve(
            rootPaths: normalizedRoots,
            repositoryIDsByRootPath: repositoryIDsByRootPath,
            fallbackSingletonRepositoryID: fallbackRepositoryID,
            displayName: preferredName
        ) else {
            return nil
        }
        if preferredName != nil { return identity }
        guard let catalogIdentity = workspaceCatalogByID[identity.id] else { return identity }
        return WorkspaceIdentity(
            id: identity.id,
            name: catalogIdentity.name,
            rootCount: identity.rootCount,
            isInferred: false
        )
    }

    private func repairHistoricalWorkspaceBindings(inventory: CodexSourceInventory) throws {
        var configurationIDsByPathIdentity: [String: Set<String>] = [:]
        for metadata in inventory.workspaceMetadata {
            for roots in metadata.historicalRootPaths {
                guard let identity = WorkspaceIdentity.resolve(rootPaths: projectRootPaths(roots)) else { continue }
                configurationIDsByPathIdentity[identity.id, default: []].insert(metadata.configurationID)
            }
        }
        let existingAliases = try store.workspaceAliases()
        let metadataSignature = fingerprint(configurationIDsByPathIdentity.map { key, values in
            key + ":" + values.sorted().joined(separator: ",")
        }.sorted().joined(separator: "|"))
        let usageByFile = Dictionary(grouping: try store.unboundWorkspaceUsage(), by: \.sourceFileID)
        for rollout in inventory.rollouts.sorted(by: { $0.fileSize < $1.fileSize }) {
            guard let pending = usageByFile[rollout.fileID], !pending.isEmpty else { continue }
            let pendingIDs = Set(pending.map(\.workspaceID)).sorted().joined(separator: ",")
            let signature = "\(metadataSignature)|\(rollout.fileSize)|\(rollout.modificationTimeMilliseconds)|\(pendingIDs)"
            guard workspaceBindingRepairSignatures[rollout.fileID] != signature else { continue }
            guard let batch = try? reader.read(file: rollout.url, fromOffset: 0) else { continue }
            let usageByOffset = Dictionary(grouping: pending, by: \.sourceOffset)
            var threadID: String?
            var turnID: String?
            var pathIdentity: String?
            var cleanedWorkspace: WorkspaceIdentity?
            var recoveredByConfiguration: [String: Set<String>] = [:]
            for line in batch.lines {
                guard let envelope = try? JSONDecoder().decode(WorkspaceBindingEnvelope.self, from: line.data) else {
                    continue
                }
                switch envelope.type {
                case "session_meta":
                    threadID = envelope.payload.id
                    turnID = nil
                    pathIdentity = nil
                    cleanedWorkspace = nil
                case "turn_context":
                    turnID = envelope.payload.turnID
                    let roots = envelope.payload.workspaceRoots ?? []
                    let cleanedRoots = projectRootPaths(roots)
                    pathIdentity = WorkspaceIdentity.resolve(rootPaths: cleanedRoots)?.id
                    cleanedWorkspace = cleanedRoots.count < roots.count
                        ? resolvedWorkspace(rootPaths: cleanedRoots, project: nil) : nil
                case "event_msg" where envelope.payload.type == "token_count":
                    for usage in usageByOffset[line.endOffset] ?? []
                    where usage.threadID == threadID && usage.turnID == turnID {
                        if let cleanedWorkspace, cleanedWorkspace.id != usage.workspaceID,
                           existingAliases[usage.workspaceID] == nil {
                            try store.upsertWorkspaceCatalog([cleanedWorkspace])
                            try store.setWorkspaceAlias(
                                sourceWorkspaceID: usage.workspaceID,
                                targetWorkspaceID: cleanedWorkspace.id
                            )
                        }
                        if let pathIdentity,
                           let configurationIDs = configurationIDsByPathIdentity[pathIdentity],
                           configurationIDs.count == 1, let configurationID = configurationIDs.first {
                            recoveredByConfiguration[configurationID, default: []].insert(usage.workspaceID)
                        }
                    }
                default:
                    break
                }
            }
            // Bind only with the original token offset, thread, turn and root-set evidence.
            // This repairs old Git fingerprints without changing usage or import checkpoints.
            for (configurationID, workspaceIDs) in recoveredByConfiguration {
                try store.addWorkspaceConfigurationBindings(workspaceIDs, configurationID: configurationID)
            }
            workspaceBindingRepairSignatures[rollout.fileID] = signature
        }
    }

    private func workspaceRepositoryID(for rootPath: String) -> String? {
        if let cached = workspaceRootRepositoryIDs[rootPath] { return cached }
        guard attemptedWorkspaceRootRepositories.insert(rootPath).inserted else { return nil }
        guard let resolved = repositoryResolver.repositoryID(forWorkingDirectory: rootPath) else {
            return nil
        }
        workspaceRootRepositoryIDs[rootPath] = resolved
        return resolved
    }

    private func countersRolledBack(from previous: TokenCounters, to current: TokenCounters) -> Bool {
        current.input < previous.input
            || current.cachedInput < previous.cachedInput
            || current.output < previous.output
            || current.reasoning < previous.reasoning
    }

    private func canonicalUsage(
        threadID: String,
        counterSegment: Int64,
        counters: TokenCounters
    ) -> String {
        "usage-v2|\(threadID)|\(counterSegment)|\(counters.input)|\(counters.cachedInput)|\(counters.output)|\(counters.reasoning)"
    }

    private func canonicalQuota(
        threadID: String,
        observedAtMilliseconds: Int64,
        window: RawQuotaWindow
    ) -> String {
        "quota|\(threadID)|\(observedAtMilliseconds)|\(window.windowMinutes)|\(window.usedPercent)|\(window.resetsAtSeconds.map(String.init) ?? "nil")"
    }

    private func canonicalState(threadID: String, event: SessionLifecycleEvent) -> String {
        "state|\(threadID)|\(event.observedAtMilliseconds)|\(event.kind.rawValue)|\(event.turnID ?? "")"
    }

    private func fingerprint(_ canonical: String) -> String {
        SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func currentMilliseconds() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }
}

private struct ImportContext {
    var threadID: String?
    var source: CodexSourceKind
    var model: String?
    var currentTurnID: String?
    var currentPlan: PlanResolution?
    var lastPlan: PlanKind?
    var counters: TokenCounters?
    var counterSegment: Int64
    var lastTokenAtMilliseconds: Int64?
    var project: ProjectIdentity?
    var workspace: WorkspaceIdentity?
    var state: SessionStateSnapshot?
    var createdAtMilliseconds: Int64?
    var updatedAtMilliseconds: Int64?
}

private struct WorkspaceBindingEnvelope: Decodable {
    let type: String
    let payload: Payload

    struct Payload: Decodable {
        let type: String?
        let id: String?
        let turnID: String?
        let workspaceRoots: [String]?

        enum CodingKeys: String, CodingKey {
            case type, id
            case turnID = "turn_id"
            case workspaceRoots = "workspace_roots"
        }
    }
}

private struct ActivityImportContext {
    var threadID: String?
    var source: CodexSourceKind
    var turnID: String?
}

private struct ThreadArchiveFact {
    let archived: Bool
    let observedAtMilliseconds: Int64
    let hasFilesystemArchive: Bool
}

private enum FileImportOutcome {
    case processed(issue: ImportIssue?)
    case skipped
    case failed(ImportIssue)
}

private enum ImportContextIssue: Error {
    case missingThread

    var detail: String { "missing-thread-context" }
}
