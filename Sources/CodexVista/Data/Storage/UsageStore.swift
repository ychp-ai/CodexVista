import Foundation

struct StoredUsageEvent: Sendable {
    let fingerprint: String
    let observedAtMilliseconds: Int64
    let threadID: String
    let turnID: String?
    let sourceKind: CodexSourceKind
    let model: String
    let plan: PlanResolution
    let usage: TokenUsageDelta
    let sourceFileID: String
    let sourceOffset: Int64
    let project: ProjectIdentity
    let workspace: WorkspaceIdentity

    init(
        fingerprint: String,
        observedAtMilliseconds: Int64,
        threadID: String,
        turnID: String? = nil,
        sourceKind: CodexSourceKind,
        model: String,
        plan: PlanResolution,
        usage: TokenUsageDelta,
        sourceFileID: String,
        sourceOffset: Int64,
        project: ProjectIdentity = .unknown,
        workspace: WorkspaceIdentity = .unknown
    ) {
        self.fingerprint = fingerprint
        self.observedAtMilliseconds = observedAtMilliseconds
        self.threadID = threadID
        self.turnID = turnID
        self.sourceKind = sourceKind
        self.model = model
        self.plan = plan
        self.usage = usage
        self.sourceFileID = sourceFileID
        self.sourceOffset = sourceOffset
        self.project = project
        self.workspace = workspace
    }
}

struct StoredWorkspaceBindingUsage: Sendable {
    let workspaceID: String
    let threadID: String
    let turnID: String
    let sourceFileID: String
    let sourceOffset: Int64
}

struct StoredQuotaEvent: Sendable {
    let fingerprint: String
    let threadID: String
    let observation: QuotaObservation
    let sourceKind: CodexSourceKind
}

struct StoredSessionStateEvent: Sendable {
    let fingerprint: String
    let threadID: String
    let turnID: String?
    let observedAtMilliseconds: Int64
    let kind: SessionLifecycleKind
    let sourceFileID: String
    let sourceOffset: Int64
}

struct StoredActivityEvent: Sendable {
    let fingerprint: String
    let observedAtMilliseconds: Int64
    let threadID: String
    let turnID: String?
    let kind: ActivityKind
    let name: String
    let sourceKind: CodexSourceKind
    let sourceFileID: String
    let sourceOffset: Int64
}

struct StoredActivityCount: Equatable, Sendable {
    let name: String
    let count: Int64
}

struct StoredSession: Sendable {
    let threadID: String
    let sourceKind: CodexSourceKind
    let createdAtMilliseconds: Int64?
    let updatedAtMilliseconds: Int64?
    let state: SessionStateSnapshot
    let lastModel: String?
    let lastPlan: PlanKind?
    let sourceFileID: String?

    var activity: SessionActivityState { state.activity }
    var archive: SessionArchiveState { state.archive }
    var childEdgeStatus: String? { state.childEdgeStatus }
    var activeTurnID: String? { state.activeTurnID }
}

struct FileCheckpoint: Sendable {
    let fileID: String
    let deviceID: Int64
    let inode: Int64
    let path: String
    let fileSize: Int64
    let committedOffset: Int64
    let generation: Int64
    let threadID: String?
    let lastRecordAtMilliseconds: Int64?
    let lastSuccessAtMilliseconds: Int64?
    let formatStatus: String
    let lastError: String?

    let currentModel: String?
    let currentTurnID: String?
    let currentPlan: PlanResolution?
    let counters: TokenCounters?
    let counterSegment: Int64
    let lastTokenAtMilliseconds: Int64?
    let activityCommittedOffset: Int64
    let project: ProjectIdentity?
    let workspace: WorkspaceIdentity?

    init(
        fileID: String,
        deviceID: Int64,
        inode: Int64,
        path: String,
        fileSize: Int64,
        committedOffset: Int64,
        generation: Int64,
        threadID: String?,
        lastRecordAtMilliseconds: Int64?,
        lastSuccessAtMilliseconds: Int64?,
        formatStatus: String,
        lastError: String?,
        currentModel: String? = nil,
        currentTurnID: String? = nil,
        currentPlan: PlanResolution? = nil,
        counters: TokenCounters? = nil,
        counterSegment: Int64 = 0,
        lastTokenAtMilliseconds: Int64? = nil,
        activityCommittedOffset: Int64 = 0,
        project: ProjectIdentity? = nil,
        workspace: WorkspaceIdentity? = nil
    ) {
        self.fileID = fileID
        self.deviceID = deviceID
        self.inode = inode
        self.path = path
        self.fileSize = fileSize
        self.committedOffset = committedOffset
        self.generation = generation
        self.threadID = threadID
        self.lastRecordAtMilliseconds = lastRecordAtMilliseconds
        self.lastSuccessAtMilliseconds = lastSuccessAtMilliseconds
        self.formatStatus = formatStatus
        self.lastError = lastError
        self.currentModel = currentModel
        self.currentTurnID = currentTurnID
        self.currentPlan = currentPlan
        self.counters = counters
        self.counterSegment = counterSegment
        self.lastTokenAtMilliseconds = lastTokenAtMilliseconds
        self.activityCommittedOffset = activityCommittedOffset
        self.project = project
        self.workspace = workspace
    }
}

struct ThreadCheckpoint: Sendable {
    let threadID: String
    let currentModel: String?
    let currentTurnID: String?
    let currentPlan: PlanResolution?
    let counters: TokenCounters?
    let counterSegment: Int64
    let lastTokenAtMilliseconds: Int64?
    let currentWorkspace: WorkspaceIdentity?

    init(
        threadID: String,
        currentModel: String?,
        currentTurnID: String? = nil,
        currentPlan: PlanResolution?,
        counters: TokenCounters?,
        counterSegment: Int64,
        lastTokenAtMilliseconds: Int64?,
        currentWorkspace: WorkspaceIdentity? = nil
    ) {
        self.threadID = threadID
        self.currentModel = currentModel
        self.currentTurnID = currentTurnID
        self.currentPlan = currentPlan
        self.counters = counters
        self.counterSegment = counterSegment
        self.lastTokenAtMilliseconds = lastTokenAtMilliseconds
        self.currentWorkspace = currentWorkspace
    }
}

struct ImportBatch: Sendable {
    let file: FileCheckpoint
    let usageEvents: [StoredUsageEvent]
    let quotaEvents: [StoredQuotaEvent]
    let stateEvents: [StoredSessionStateEvent]
    let activityEvents: [StoredActivityEvent]
    let sessions: [StoredSession]
    let threadCheckpoints: [ThreadCheckpoint]

    init(
        file: FileCheckpoint,
        usageEvents: [StoredUsageEvent],
        quotaEvents: [StoredQuotaEvent],
        stateEvents: [StoredSessionStateEvent],
        activityEvents: [StoredActivityEvent] = [],
        sessions: [StoredSession],
        threadCheckpoints: [ThreadCheckpoint]
    ) {
        self.file = file
        self.usageEvents = usageEvents
        self.quotaEvents = quotaEvents
        self.stateEvents = stateEvents
        self.activityEvents = activityEvents
        self.sessions = sessions
        self.threadCheckpoints = threadCheckpoints
    }
}

struct StoredHourlyUsage: Equatable, Sendable {
    let hourStartMilliseconds: Int64
    let model: String
    let plan: PlanKind
    let uncachedInputTokens: Int64
    let cachedInputTokens: Int64
    let visibleOutputTokens: Int64
    let reasoningTokens: Int64
    let totalTokens: Int64
}

struct StoredUsageQueryRow: Sendable {
    let fingerprint: String
    let observedAtMilliseconds: Int64
    let threadID: String
    let turnID: String?
    let model: String
    let plan: PlanResolution
    let uncachedInputTokens: Int64
    let cachedInputTokens: Int64
    let visibleOutputTokens: Int64
    let reasoningTokens: Int64
    let totalTokens: Int64
    let project: ProjectIdentity
    let workspace: WorkspaceIdentity
}

struct StoredTurnLifecycleQueryRow: Sendable {
    let threadID: String
    let turnID: String
    let observedAtMilliseconds: Int64
    let kind: SessionLifecycleKind
}

struct StoredSessionQueryRow: Sendable {
    let session: StoredSession
    let sourceLastRecordAtMilliseconds: Int64?
    let totalTokens: Int64
}

struct StoredSourceFacts: Sendable {
    let hasCLIData: Bool
    let hasDesktopData: Bool
    let indexHealth: CodexIndexHealth
    let lastSuccessfulRefreshMilliseconds: Int64?
    let hasDegradedFiles: Bool
    let hasUnsupportedFiles: Bool
}

final class UsageStore: @unchecked Sendable {
    private let database: SQLiteDatabase

    init(databaseURL: URL) throws {
        database = try SQLiteDatabase(url: databaseURL)
        try migrate()
    }

    func commit(_ batch: ImportBatch) throws {
        try database.inTransaction {
            for event in batch.usageEvents {
                let total = try validatedTotal(for: event.usage)
                let inserted = try insertUsageEvent(event, total: total)
                if inserted == 1 {
                    try addToHourlyUsage(event, total: total)
                }
            }

            for event in batch.quotaEvents {
                try insertQuotaEvent(event)
            }
            for event in batch.stateEvents {
                try insertSessionStateEvent(event)
            }
            for event in batch.activityEvents {
                try insertActivityEvent(event)
            }
            for session in batch.sessions {
                try upsertSession(session)
            }
            for checkpoint in batch.threadCheckpoints {
                try upsertThreadCheckpoint(checkpoint)
            }

            try upsertFileCheckpoint(batch.file)
        }
    }

    func totalUsage() throws -> Int64 {
        let rows = try database.query(sql: "SELECT total_tokens FROM usage_events ORDER BY fingerprint")
        var total: Int64 = 0
        for values in rows {
            let row = SQLiteRow(table: "usage_events", values: values)
            total = try checkedAdd(
                total,
                row.requiredInt64("total_tokens"),
                context: "usage_events.total_tokens"
            )
        }
        return total
    }

    func usageEventCount() throws -> Int64 {
        try count(table: "usage_events")
    }

    func quotaEventCount() throws -> Int64 {
        try count(table: "quota_snapshots")
    }

    func sessionStateEventCount() throws -> Int64 {
        try count(table: "session_state_events")
    }

    func activityEventCount() throws -> Int64 {
        try count(table: "activity_events")
    }

    func fileCheckpoint(fileID: String) throws -> FileCheckpoint? {
        let rows = try database.query(
            sql: "SELECT * FROM source_files WHERE file_id = ?",
            bindings: [.text(fileID)]
        )
        guard let values = rows.first else { return nil }
        let row = SQLiteRow(table: "source_files", values: values)
        let counters: TokenCounters?
        if let input = try row.optionalInt64("input_tokens"),
           let cached = try row.optionalInt64("cached_input_tokens"),
           let output = try row.optionalInt64("output_tokens"),
           let reasoning = try row.optionalInt64("reasoning_tokens") {
            counters = TokenCounters(
                input: input,
                cachedInput: cached,
                output: output,
                reasoning: reasoning
            )
        } else {
            counters = nil
        }
        return FileCheckpoint(
            fileID: try row.requiredString("file_id"),
            deviceID: try row.requiredInt64("device_id"),
            inode: try row.requiredInt64("inode"),
            path: try row.requiredString("path"),
            fileSize: try row.requiredInt64("file_size"),
            committedOffset: try row.requiredInt64("committed_offset"),
            generation: try row.requiredInt64("generation"),
            threadID: try row.optionalString("thread_id"),
            lastRecordAtMilliseconds: try row.optionalInt64("last_record_at_ms"),
            lastSuccessAtMilliseconds: try row.optionalInt64("last_success_at_ms"),
            formatStatus: try row.requiredString("format_status"),
            lastError: try row.optionalString("last_error"),
            currentModel: try row.optionalString("current_model"),
            currentTurnID: try row.optionalString("current_turn_id"),
            currentPlan: try planResolution(from: row),
            counters: counters,
            counterSegment: try row.requiredInt64("counter_segment"),
            lastTokenAtMilliseconds: try row.optionalInt64("last_token_at_ms"),
            activityCommittedOffset: try row.requiredInt64("activity_committed_offset"),
            project: try projectIdentity(from: row),
            workspace: try workspaceIdentity(from: row)
        )
    }

    func activityCounts(
        kind: ActivityKind,
        fromMilliseconds: Int64? = nil,
        toMilliseconds: Int64? = nil,
        limit: Int? = 20
    ) throws -> [StoredActivityCount] {
        if let limit, limit <= 0 { return [] }
        var predicates = ["kind = ?"]
        var bindings: [SQLiteValue] = [.text(kind.rawValue)]
        if let fromMilliseconds {
            predicates.append("observed_at_ms >= ?")
            bindings.append(.integer(fromMilliseconds))
        }
        if let toMilliseconds {
            predicates.append("observed_at_ms < ?")
            bindings.append(.integer(toMilliseconds))
        }
        let limitClause: String
        if let limit {
            bindings.append(.integer(Int64(limit)))
            limitClause = "LIMIT ?"
        } else {
            limitClause = ""
        }
        let rows = try database.query(
            sql: """
            SELECT name, COUNT(*) AS count
            FROM activity_events
            WHERE \(predicates.joined(separator: " AND "))
            GROUP BY name
            ORDER BY count DESC, name ASC
            \(limitClause)
            """,
            bindings: bindings
        )
        return try rows.map { values in
            let row = SQLiteRow(table: "activity_events", values: values)
            return StoredActivityCount(
                name: try row.requiredString("name"),
                count: try row.requiredInt64("count")
            )
        }
    }

    func activityEvents(
        fromMilliseconds: Int64? = nil,
        toMilliseconds: Int64? = nil
    ) throws -> [StoredActivityEvent] {
        var predicates: [String] = []
        var bindings: [SQLiteValue] = []
        if let fromMilliseconds {
            predicates.append("observed_at_ms >= ?")
            bindings.append(.integer(fromMilliseconds))
        }
        if let toMilliseconds {
            predicates.append("observed_at_ms < ?")
            bindings.append(.integer(toMilliseconds))
        }
        let whereClause = predicates.isEmpty
            ? ""
            : " WHERE \(predicates.joined(separator: " AND "))"
        let rows = try database.query(
            sql: """
            SELECT fingerprint, observed_at_ms, thread_id, turn_id, kind, name,
                   source_kind, source_file_id, source_offset
            FROM activity_events\(whereClause)
            ORDER BY observed_at_ms, fingerprint
            """,
            bindings: bindings
        )
        return try rows.map { values in
            let row = SQLiteRow(table: "activity_events", values: values)
            return StoredActivityEvent(
                fingerprint: try row.requiredString("fingerprint"),
                observedAtMilliseconds: try row.requiredInt64("observed_at_ms"),
                threadID: try row.requiredString("thread_id"),
                turnID: try row.optionalString("turn_id"),
                kind: try row.requiredEnum("kind", as: ActivityKind.self),
                name: try row.requiredString("name"),
                sourceKind: try row.requiredEnum("source_kind", as: CodexSourceKind.self),
                sourceFileID: try row.requiredString("source_file_id"),
                sourceOffset: try row.requiredInt64("source_offset")
            )
        }
    }

    func resetImportedData() throws {
        try database.inTransaction {
            try resetImportedDataInCurrentTransaction()
        }
    }

    func upsertWorkspaceCatalog(_ workspaces: [WorkspaceIdentity]) throws {
        try database.inTransaction {
            for workspace in workspaces where workspace != .unknown && !workspace.isInferred {
                try database.execute(
                    sql: """
                        INSERT INTO workspace_catalog(workspace_id, workspace_name, root_count)
                        VALUES (?, ?, ?)
                        ON CONFLICT(workspace_id) DO UPDATE SET
                          workspace_name = excluded.workspace_name,
                          root_count = excluded.root_count
                        """,
                    bindings: [
                        .text(workspace.id), .text(workspace.name),
                        .integer(Int64(workspace.rootCount))
                    ]
                )
            }
        }
    }

    func workspaceCatalog() throws -> [String: WorkspaceIdentity] {
        let rows = try database.query(
            sql: """
                SELECT workspace_id, workspace_name, root_count
                FROM workspace_catalog ORDER BY workspace_id
                """
        )
        return try Dictionary(uniqueKeysWithValues: rows.map { values in
            let row = SQLiteRow(table: "workspace_catalog", values: values)
            let identity = WorkspaceIdentity(
                id: try row.requiredString("workspace_id"),
                name: try row.requiredString("workspace_name"),
                rootCount: Int(clamping: try row.requiredInt64("root_count")),
                isInferred: false
            )
            return (identity.id, identity)
        })
    }

    func upsertWorkspaceConfiguration(
        _ configuration: StoredWorkspaceConfiguration,
        matchingWorkspaceIDs: Set<String>,
        isCurrent: Bool
    ) throws {
        let directoriesJSON = String(decoding: try JSONEncoder().encode(configuration.directories), as: UTF8.self)
        try database.inTransaction {
            try database.execute(
                sql: """
                    INSERT INTO workspace_configurations(configuration_id, name, directories_json, updated_at_ms)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(configuration_id) DO UPDATE SET
                      name = excluded.name,
                      directories_json = excluded.directories_json,
                      updated_at_ms = excluded.updated_at_ms
                    WHERE ? = 1 OR excluded.updated_at_ms >= workspace_configurations.updated_at_ms
                    """,
                bindings: [
                    .text(configuration.id), .text(configuration.name), .text(directoriesJSON),
                    .integer(configuration.updatedAtMilliseconds), .integer(isCurrent ? 1 : 0)
                ]
            )
            for workspaceID in matchingWorkspaceIDs.sorted() {
                try database.execute(
                    sql: """
                        INSERT OR IGNORE INTO workspace_configuration_bindings(workspace_id, configuration_id)
                        VALUES (?, ?)
                        """,
                    bindings: [.text(workspaceID), .text(configuration.id)]
                )
            }
        }
    }

    func workspaceConfigurations() throws -> [String: StoredWorkspaceConfiguration] {
        let rows = try database.query(sql: """
            SELECT configuration_id, name, directories_json, updated_at_ms FROM workspace_configurations
            """)
        return try Dictionary(uniqueKeysWithValues: rows.map { values in
            let row = SQLiteRow(table: "workspace_configurations", values: values)
            let configuration = StoredWorkspaceConfiguration(
                id: try row.requiredString("configuration_id"),
                name: try row.requiredString("name"),
                directories: try JSONDecoder().decode(
                    [WorkspaceDirectory].self,
                    from: Data(try row.requiredString("directories_json").utf8)
                ),
                updatedAtMilliseconds: try row.requiredInt64("updated_at_ms")
            )
            return (configuration.id, configuration)
        })
    }

    func unboundWorkspaceUsage() throws -> [StoredWorkspaceBindingUsage] {
        let rows = try database.query(sql: """
            SELECT DISTINCT workspace_id, thread_id, turn_id, source_file_id, source_offset
            FROM usage_events AS usage
            WHERE workspace_id <> 'unknown' AND workspace_is_inferred = 0 AND turn_id IS NOT NULL
              AND NOT EXISTS (
                SELECT 1 FROM workspace_configuration_bindings AS binding
                WHERE binding.workspace_id = usage.workspace_id
              )
            """)
        return try rows.map { values in
            let row = SQLiteRow(table: "usage_events", values: values)
            return StoredWorkspaceBindingUsage(
                workspaceID: try row.requiredString("workspace_id"),
                threadID: try row.requiredString("thread_id"),
                turnID: try row.requiredString("turn_id"),
                sourceFileID: try row.requiredString("source_file_id"),
                sourceOffset: try row.requiredInt64("source_offset")
            )
        }
    }

    func addWorkspaceConfigurationBindings(_ workspaceIDs: Set<String>, configurationID: String) throws {
        try database.inTransaction {
            for workspaceID in workspaceIDs.sorted() {
                try database.execute(
                    sql: """
                        INSERT OR IGNORE INTO workspace_configuration_bindings(workspace_id, configuration_id)
                        VALUES (?, ?)
                        """,
                    bindings: [.text(workspaceID), .text(configurationID)]
                )
            }
        }
    }

    func workspaceConfigurationBindings() throws -> [String: String] {
        // Rollouts do not include the Codex project ID. Ambiguous root sets stay independent.
        let rows = try database.query(sql: """
            SELECT workspace_id, MIN(configuration_id) AS configuration_id
            FROM workspace_configuration_bindings
            GROUP BY workspace_id HAVING COUNT(*) = 1
            """)
        return try Dictionary(uniqueKeysWithValues: rows.map { values in
            let row = SQLiteRow(table: "workspace_configuration_bindings", values: values)
            return (
                try row.requiredString("workspace_id"),
                try row.requiredString("configuration_id")
            )
        })
    }

    func setWorkspaceAlias(sourceWorkspaceID: String, targetWorkspaceID: String) throws {
        guard !sourceWorkspaceID.isEmpty,
              !targetWorkspaceID.isEmpty,
              sourceWorkspaceID != WorkspaceIdentity.unknown.id,
              targetWorkspaceID != WorkspaceIdentity.unknown.id,
              sourceWorkspaceID != targetWorkspaceID else {
            throw UsageStoreError.invalidWorkspaceAlias
        }
        try database.execute(
            sql: """
                INSERT INTO workspace_aliases(source_workspace_id, target_workspace_id)
                VALUES (?, ?)
                ON CONFLICT(source_workspace_id) DO UPDATE SET
                  target_workspace_id = excluded.target_workspace_id
                """,
            bindings: [.text(sourceWorkspaceID), .text(targetWorkspaceID)]
        )
    }

    func workspaceAliases() throws -> [String: String] {
        let rows = try database.query(
            sql: """
                SELECT source_workspace_id, target_workspace_id
                FROM workspace_aliases ORDER BY source_workspace_id
                """
        )
        return try Dictionary(uniqueKeysWithValues: rows.map { values in
            let row = SQLiteRow(table: "workspace_aliases", values: values)
            return (
                try row.requiredString("source_workspace_id"),
                try row.requiredString("target_workspace_id")
            )
        })
    }

    func threadCheckpoint(threadID: String) throws -> ThreadCheckpoint? {
        let rows = try database.query(
            sql: "SELECT * FROM thread_checkpoints WHERE thread_id = ?",
            bindings: [.text(threadID)]
        )
        guard let values = rows.first else { return nil }
        let row = SQLiteRow(table: "thread_checkpoints", values: values)
        let counters: TokenCounters?
        if let input = try row.optionalInt64("input_tokens"),
           let cached = try row.optionalInt64("cached_input_tokens"),
           let output = try row.optionalInt64("output_tokens"),
           let reasoning = try row.optionalInt64("reasoning_tokens") {
            counters = TokenCounters(input: input, cachedInput: cached, output: output, reasoning: reasoning)
        } else {
            counters = nil
        }
        return ThreadCheckpoint(
            threadID: try row.requiredString("thread_id"),
            currentModel: try row.optionalString("current_model"),
            currentTurnID: try row.optionalString("current_turn_id"),
            currentPlan: try planResolution(from: row),
            counters: counters,
            counterSegment: try row.requiredInt64("counter_segment"),
            lastTokenAtMilliseconds: try row.optionalInt64("last_token_at_ms"),
            currentWorkspace: try workspaceIdentity(from: row)
        )
    }

    func latestQuotas() throws -> [StoredQuotaEvent] {
        var seenKinds: Set<QuotaKind> = []
        return try quotaHistory().filter { seenKinds.insert($0.observation.kind).inserted }
    }

    func quotaHistory() throws -> [StoredQuotaEvent] {
        let rows = try database.query(
            sql: """
            SELECT fingerprint, observed_at_ms, thread_id, kind, window_minutes, remaining,
                   resets_at_ms, plan, plan_raw, plan_is_inferred, source_kind
            FROM quota_snapshots
            ORDER BY kind, observed_at_ms DESC, fingerprint DESC
            """
        )
        var result: [StoredQuotaEvent] = []
        for values in rows {
            let row = SQLiteRow(table: "quota_snapshots", values: values)
            let kind = try row.requiredEnum("kind", as: QuotaKind.self)
            let plan = try SQLitePlanResolution.from(row: row)
            result.append(StoredQuotaEvent(
                fingerprint: try row.requiredString("fingerprint"),
                threadID: try row.requiredString("thread_id"),
                observation: QuotaObservation(
                    kind: kind,
                    observedAtMilliseconds: try row.requiredInt64("observed_at_ms"),
                    windowMinutes: Int(try row.requiredInt64("window_minutes")),
                    remaining: try row.requiredDouble("remaining"),
                    resetsAtMilliseconds: try row.optionalInt64("resets_at_ms"),
                    plan: plan
                ),
                sourceKind: try row.requiredEnum("source_kind", as: CodexSourceKind.self)
            ))
        }
        return result
    }

    func hourlyUsage() throws -> [StoredHourlyUsage] {
        let rows = try database.query(
            sql: "SELECT * FROM hourly_usage ORDER BY hour_start_ms, model, plan"
        )
        return try rows.map { values in
            let row = SQLiteRow(table: "hourly_usage", values: values)
            return StoredHourlyUsage(
                hourStartMilliseconds: try row.requiredInt64("hour_start_ms"),
                model: try row.requiredString("model"),
                plan: try row.requiredEnum("plan", as: PlanKind.self),
                uncachedInputTokens: try row.requiredInt64("uncached_input_tokens"),
                cachedInputTokens: try row.requiredInt64("cached_input_tokens"),
                visibleOutputTokens: try row.requiredInt64("visible_output_tokens"),
                reasoningTokens: try row.requiredInt64("reasoning_tokens"),
                totalTokens: try row.requiredInt64("total_tokens")
            )
        }
    }

    func usageEvents(
        fromMilliseconds: Int64? = nil,
        toMilliseconds: Int64? = nil
    ) throws -> [StoredUsageQueryRow] {
        var predicates: [String] = []
        var bindings: [SQLiteValue] = []
        if let fromMilliseconds {
            predicates.append("observed_at_ms >= ?")
            bindings.append(.integer(fromMilliseconds))
        }
        if let toMilliseconds {
            predicates.append("observed_at_ms < ?")
            bindings.append(.integer(toMilliseconds))
        }
        let whereClause = predicates.isEmpty ? "" : " WHERE \(predicates.joined(separator: " AND "))"
        let rows = try database.query(
            sql: """
            SELECT fingerprint, observed_at_ms, thread_id, turn_id, model, plan, plan_raw, plan_is_inferred,
                   uncached_input_tokens, cached_input_tokens, visible_output_tokens,
                   reasoning_tokens, total_tokens, project_id, project_name, repository_id,
                   workspace_id, workspace_name, workspace_root_count, workspace_is_inferred
            FROM usage_events\(whereClause)
            ORDER BY observed_at_ms, fingerprint
            """,
            bindings: bindings
        )
        return try rows.map { values in
            let row = SQLiteRow(table: "usage_events", values: values)
            return StoredUsageQueryRow(
                fingerprint: try row.requiredString("fingerprint"),
                observedAtMilliseconds: try row.requiredInt64("observed_at_ms"),
                threadID: try row.requiredString("thread_id"),
                turnID: try row.optionalString("turn_id"),
                model: try row.requiredString("model"),
                plan: try SQLitePlanResolution.from(row: row),
                uncachedInputTokens: try row.requiredInt64("uncached_input_tokens"),
                cachedInputTokens: try row.requiredInt64("cached_input_tokens"),
                visibleOutputTokens: try row.requiredInt64("visible_output_tokens"),
                reasoningTokens: try row.requiredInt64("reasoning_tokens"),
                totalTokens: try row.requiredInt64("total_tokens"),
                project: try projectIdentity(from: row) ?? .unknown,
                workspace: try workspaceIdentity(from: row) ?? .unknown
            )
        }
    }

    func turnLifecycleEvents() throws -> [StoredTurnLifecycleQueryRow] {
        let rows = try database.query(sql: """
            SELECT thread_id, turn_id, observed_at_ms, kind
            FROM session_state_events
            WHERE turn_id IS NOT NULL AND turn_id <> ''
            ORDER BY observed_at_ms, fingerprint
            """)
        return try rows.map { values in
            let row = SQLiteRow(table: "session_state_events", values: values)
            return StoredTurnLifecycleQueryRow(
                threadID: try row.requiredString("thread_id"),
                turnID: try row.requiredString("turn_id"),
                observedAtMilliseconds: try row.requiredInt64("observed_at_ms"),
                kind: try row.requiredEnum("kind", as: SessionLifecycleKind.self)
            )
        }
    }

    func sessions() throws -> [StoredSession] {
        let rows = try database.query(sql: "SELECT * FROM sessions ORDER BY thread_id")
        return try rows.map { try storedSession(from: SQLiteRow(table: "sessions", values: $0)) }
    }

    func sessionQueryRows() throws -> [StoredSessionQueryRow] {
        let sessionRows = try database.query(sql: """
            SELECT s.*, sf.last_record_at_ms AS source_last_record_at_ms
            FROM sessions AS s
            LEFT JOIN source_files AS sf ON sf.file_id = s.source_file_id
            ORDER BY s.thread_id
            """)
        let tokenRows = try database.query(
            sql: "SELECT thread_id, total_tokens FROM usage_events ORDER BY thread_id, fingerprint"
        )
        var totals: [String: Int64] = [:]
        for values in tokenRows {
            let row = SQLiteRow(table: "usage_events", values: values)
            let threadID = try row.requiredString("thread_id")
            totals[threadID] = try checkedAdd(
                totals[threadID, default: 0],
                row.requiredInt64("total_tokens"),
                context: "usage_events.thread_total_tokens"
            )
        }
        return try sessionRows.map { values in
            let row = SQLiteRow(table: "sessions", values: values)
            let session = try storedSession(from: row)
            return StoredSessionQueryRow(
                session: session,
                sourceLastRecordAtMilliseconds: try row.optionalInt64("source_last_record_at_ms"),
                totalTokens: totals[session.threadID, default: 0]
            )
        }
    }

    func recordIndexHealth(_ health: CodexIndexHealth, processedFileCount: Int) throws {
        try persistSourceStatus(
            indexHealth: health,
            discoveredFileIDs: nil,
            issues: [],
            processedFileCount: processedFileCount
        )
    }

    func persistSourceStatus(
        indexHealth: CodexIndexHealth,
        discoveredFileIDs: [String]?,
        issues: [ImportIssue],
        processedFileCount: Int
    ) throws {
        try database.inTransaction {
            let indexState: String
            let indexDetail: String?
            switch indexHealth {
            case .available:
                indexState = "available"
                indexDetail = nil
            case .missing:
                indexState = "missing"
                indexDetail = nil
            case .degraded:
                indexState = "degraded"
                indexDetail = "index-degraded"
            }
            try upsertSourceStatus(
                sourceKind: "index",
                state: indexState,
                detail: indexDetail,
                lastSuccessAtMilliseconds: nil,
                processedFileCount: processedFileCount
            )

            guard let discoveredFileIDs else { return }
            let currentIDs = Set(discoveredFileIDs)
            let previousAggregateRows = try database.query(
                sql: "SELECT last_success_at_ms FROM source_status WHERE source_kind = 'files'"
            )
            let previousLastSuccess = try previousAggregateRows.first.map {
                try SQLiteRow(table: "source_status", values: $0)
                    .optionalInt64("last_success_at_ms")
            } ?? nil
            let checkpointRows = try database.query(sql: """
                SELECT file_id, last_success_at_ms, format_status, last_error
                FROM source_files
                """)
            var checkpoints: [String: (formatStatus: String, lastError: String?)] = [:]
            var historicalLastSuccess: Int64?
            for values in checkpointRows {
                let row = SQLiteRow(table: "source_files", values: values)
                let fileID = try row.requiredString("file_id")
                checkpoints[fileID] = (
                    formatStatus: try row.requiredString("format_status"),
                    lastError: try row.optionalString("last_error")
                )
                if let value = try row.optionalInt64("last_success_at_ms") {
                    historicalLastSuccess = max(historicalLastSuccess ?? value, value)
                }
            }

            let existingFileStatusRows = try database.query(sql: """
                SELECT source_kind, state FROM source_status
                WHERE source_kind LIKE 'file:%'
                """)
            for values in existingFileStatusRows {
                let row = SQLiteRow(table: "source_status", values: values)
                let sourceKind = try row.requiredString("source_kind")
                let fileID = String(sourceKind.dropFirst("file:".count))
                if !currentIDs.contains(fileID) {
                    try deleteSourceStatus(sourceKind: sourceKind)
                }
            }

            var issueStates: [String: String] = [:]
            for issue in issues {
                guard let fileID = issue.fileID, currentIDs.contains(fileID) else { continue }
                switch issue.kind {
                case .unsupportedFormat:
                    issueStates[fileID] = "unsupported"
                case .read, .decode, .store:
                    if issueStates[fileID] != "unsupported" {
                        issueStates[fileID] = "degraded"
                    }
                case .discovery, .index:
                    break
                }
            }

            for fileID in currentIDs.sorted() {
                let sourceKind = "file:\(fileID)"
                if let issueState = issueStates[fileID] {
                    try upsertSourceStatus(
                        sourceKind: sourceKind,
                        state: issueState,
                        detail: issueState == "unsupported" ? "file-unsupported" : "file-degraded",
                        lastSuccessAtMilliseconds: nil,
                        processedFileCount: 0
                    )
                    continue
                }
                guard let checkpoint = checkpoints[fileID] else {
                    continue
                }
                if checkpoint.lastError == "missing-thread-context" {
                    try upsertSourceStatus(
                        sourceKind: sourceKind,
                        state: "unsupported",
                        detail: "file-unsupported",
                        lastSuccessAtMilliseconds: nil,
                        processedFileCount: 0
                    )
                } else if checkpoint.formatStatus != "supported" || checkpoint.lastError != nil {
                    try upsertSourceStatus(
                        sourceKind: sourceKind,
                        state: "degraded",
                        detail: "file-degraded",
                        lastSuccessAtMilliseconds: nil,
                        processedFileCount: 0
                    )
                } else {
                    try deleteSourceStatus(sourceKind: sourceKind)
                }
            }

            let currentStatusRows = try database.query(sql: """
                SELECT source_kind, state FROM source_status
                WHERE source_kind LIKE 'file:%'
                """)
            var hasDegraded = false
            var hasUnsupported = false
            for values in currentStatusRows {
                let row = SQLiteRow(table: "source_status", values: values)
                let sourceKind = try row.requiredString("source_kind")
                let fileID = String(sourceKind.dropFirst("file:".count))
                guard currentIDs.contains(fileID) else { continue }
                switch try row.requiredString("state") {
                case "unsupported": hasUnsupported = true
                case "degraded": hasDegraded = true
                default: break
                }
            }
            let fileState: String
            let fileDetail: String?
            if hasUnsupported {
                fileState = "unsupported"
                fileDetail = hasDegraded ? "also-degraded" : nil
            } else if hasDegraded {
                fileState = "degraded"
                fileDetail = nil
            } else {
                fileState = "clean"
                fileDetail = nil
            }
            try upsertSourceStatus(
                sourceKind: "files",
                state: fileState,
                detail: fileDetail,
                lastSuccessAtMilliseconds: historicalLastSuccess ?? previousLastSuccess,
                processedFileCount: processedFileCount
            )
        }
    }

    func sourceFacts() throws -> StoredSourceFacts {
        let sourceRows = try database.query(sql: """
            SELECT source_kind FROM usage_events
            UNION
            SELECT source_kind FROM sessions
            """)
        let sources = try Set(sourceRows.map {
            try SQLiteRow(table: "stored_sources", values: $0).requiredString("source_kind")
        })
        let statusRows = try database.query(
            sql: "SELECT source_kind, state, detail, last_success_at_ms FROM source_status"
        )
        let statuses = try Dictionary(uniqueKeysWithValues: statusRows.map { values in
            let row = SQLiteRow(table: "source_status", values: values)
            return (try row.requiredString("source_kind"), row)
        })
        let indexHealth: CodexIndexHealth
        if let indexRow = statuses["index"] {
            switch try indexRow.requiredString("state") {
            case "available": indexHealth = .available
            case "missing": indexHealth = .missing
            default: indexHealth = .degraded("index-degraded")
            }
        } else {
            indexHealth = .missing
        }
        let lastSuccessfulRefreshMilliseconds: Int64?
        let hasDegradedFiles: Bool
        let hasUnsupportedFiles: Bool
        if let filesRow = statuses["files"] {
            let state = try filesRow.requiredString("state")
            let detail = try filesRow.optionalString("detail")
            lastSuccessfulRefreshMilliseconds = try filesRow.optionalInt64("last_success_at_ms")
            hasDegradedFiles = state == "degraded"
                || (state == "unsupported" && detail == "also-degraded")
            hasUnsupportedFiles = state == "unsupported"
        } else {
            let fileRows = try database.query(sql: """
                SELECT MAX(last_success_at_ms) AS last_success_at_ms,
                       COALESCE(SUM(CASE WHEN format_status = 'supported' THEN 0 ELSE 1 END), 0)
                         AS degraded_count,
                       COALESCE(SUM(CASE WHEN last_error = 'missing-thread-context' THEN 1 ELSE 0 END), 0)
                         AS unsupported_count
                FROM source_files
                """)
            let fileRow = SQLiteRow(table: "source_files", values: fileRows[0])
            lastSuccessfulRefreshMilliseconds = try fileRow.optionalInt64("last_success_at_ms")
            hasDegradedFiles = try fileRow.requiredInt64("degraded_count") > 0
            hasUnsupportedFiles = try fileRow.requiredInt64("unsupported_count") > 0
        }
        return StoredSourceFacts(
            hasCLIData: sources.contains(CodexSourceKind.cli.rawValue),
            hasDesktopData: sources.contains(CodexSourceKind.desktop.rawValue),
            indexHealth: indexHealth,
            lastSuccessfulRefreshMilliseconds: lastSuccessfulRefreshMilliseconds,
            hasDegradedFiles: hasDegradedFiles,
            hasUnsupportedFiles: hasUnsupportedFiles
        )
    }

    func schemaVersions() throws -> [Int64] {
        try database.query(sql: "SELECT version FROM schema_migrations ORDER BY version")
            .map { try SQLiteRow(table: "schema_migrations", values: $0).requiredInt64("version") }
    }

    func schemaTables() throws -> [String] {
        try database.query(
            sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
        ).map { try SQLiteRow(table: "sqlite_master", values: $0).requiredString("name") }
    }

    func schemaColumns(table: String) throws -> [String] {
        guard table.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return [] }
        return try database.query(sql: "PRAGMA table_info(\(table))")
            .map { try SQLiteRow(table: "pragma_table_info", values: $0).requiredString("name") }
    }

    private func migrate() throws {
        try database.inTransaction {
            try database.execute(sql: "CREATE TABLE IF NOT EXISTS schema_migrations(version INTEGER PRIMARY KEY)")
            let versions = try database.query(sql: "SELECT version FROM schema_migrations ORDER BY version")
                .map { try SQLiteRow(table: "schema_migrations", values: $0).requiredInt64("version") }

            guard versions.last ?? 0 <= 17 else {
                throw UsageStoreError.unsupportedSchemaVersion(versions.last ?? 0)
            }
            if versions.contains(17) {
                try validateVersionTwoSchema()
                try validateVersionThreeSchema()
                try validateVersionFiveSchema()
                try validateVersionSevenSchema()
                try validateVersionTenSchema()
                try validateVersionElevenSchema()
                try validateVersionTwelveSchema()
                try validateVersionThirteenSchema()
                try validateVersionFifteenSchema()
                try validateVersionSeventeenSchema()
                return
            }

            if !versions.contains(2) {
                if versions.contains(1) {
                    try dropVersionOneStorage()
                }
                for statement in Self.versionTwoStatements {
                    try database.execute(sql: statement)
                }
                try database.execute(sql: "INSERT OR IGNORE INTO schema_migrations(version) VALUES (1)")
                try database.execute(sql: "INSERT INTO schema_migrations(version) VALUES (2)")
            }
            if !versions.contains(3) {
                for statement in Self.versionThreeStatements {
                    try database.execute(sql: statement)
                }
                try database.execute(sql: "INSERT INTO schema_migrations(version) VALUES (3)")
            }

            if !versions.contains(4) {
                // v4 changes quota semantics: only the default Codex pool contributes
                // to the dashboard. v3 did not persist pool identity, so mixed legacy
                // snapshots cannot be repaired in place.
                try resetImportedDataInCurrentTransaction()
                try database.execute(sql: "INSERT INTO schema_migrations(version) VALUES (4)")
            }

            if !versions.contains(5) {
                for statement in Self.versionFiveStatements {
                    try database.execute(sql: statement)
                }
                // v5 adds project identity to usage events. Rebuild from untouched
                // rollouts so historical events receive the correct project as well.
                try resetImportedDataInCurrentTransaction()
                try database.execute(sql: "INSERT INTO schema_migrations(version) VALUES (5)")
            }

            if !versions.contains(6) {
                // v6 identifies cumulative usage snapshots by thread, counter segment,
                // and counters instead of their rewritten timestamp. Existing derived
                // rows must be rebuilt so copied parent history receives the new stable
                // fingerprints and collapses across rollout files.
                try resetImportedDataInCurrentTransaction()
                try database.execute(sql: "INSERT INTO schema_migrations(version) VALUES (6)")
            }

            if !versions.contains(7) {
                for statement in Self.versionSevenStatements {
                    try database.execute(sql: statement)
                }
                // v7 enriches path-based project identity with a Git repository fingerprint.
                // Rebuild from local rollouts so all available working directories are inspected.
                try resetImportedDataInCurrentTransaction()
                try database.execute(sql: "INSERT INTO schema_migrations(version) VALUES (7)")
            }

            if !versions.contains(8) {
                // v8 reads the repository URL embedded in session metadata. Rebuild so deleted
                // worktrees can recover their repository identity without filesystem access.
                try resetImportedDataInCurrentTransaction()
                try database.execute(sql: "INSERT INTO schema_migrations(version) VALUES (8)")
            }

            if !versions.contains(9) {
                try database.execute(sql: "INSERT INTO schema_migrations(version) VALUES (9)")
            }

            if !versions.contains(10) {
                for statement in Self.versionTenStatements {
                    try database.execute(sql: statement)
                }
                // v10 attributes each cumulative usage delta to its active turn. Rebuild
                // from untouched rollouts so the complete reply history is available.
                try resetImportedDataInCurrentTransaction()
                try database.execute(sql: "INSERT INTO schema_migrations(version) VALUES (10)")
            }
            if !versions.contains(11) {
                for statement in Self.versionElevenStatements {
                    try database.execute(sql: statement)
                }
                // v11 attributes every usage delta to the workspace root set active for its turn.
                // Rebuild from untouched rollouts so historical workspace detail is complete.
                try resetImportedDataInCurrentTransaction()
                try database.execute(sql: "INSERT INTO schema_migrations(version) VALUES (11)")
            }
            if !versions.contains(12) {
                for statement in Self.versionTwelveStatements {
                    try database.execute(sql: statement)
                }
                // v12 distinguishes explicit root sets from safe working-directory inference.
                // Rebuild so old turns without workspace_roots receive an honest inferred identity.
                try resetImportedDataInCurrentTransaction()
                try database.execute(sql: "INSERT INTO schema_migrations(version) VALUES (12)")
            }
            if !versions.contains(13) {
                for statement in Self.versionThirteenStatements {
                    try database.execute(sql: statement)
                }
                try database.execute(sql: "INSERT INTO schema_migrations(version) VALUES (13)")
            }
            if !versions.contains(14) {
                // v14 uses Codex project metadata for display names and Git repository
                // identity for roots. Rebuild so archived labels and linked worktrees
                // use the same semantics as current workspaces.
                try resetImportedDataInCurrentTransaction()
                try database.execute(sql: "INSERT INTO schema_migrations(version) VALUES (14)")
            }
            if !versions.contains(15) {
                for statement in Self.versionFifteenStatements {
                    try database.execute(sql: statement)
                }
                try database.execute(sql: "INSERT INTO schema_migrations(version) VALUES (15)")
            }
            if !versions.contains(16) {
                try database.execute(sql: "DROP TABLE IF EXISTS account_rate_limit_cache")
                try database.execute(sql: "INSERT INTO schema_migrations(version) VALUES (16)")
            }
            if !versions.contains(17) {
                for statement in Self.versionSeventeenStatements {
                    try database.execute(sql: statement)
                }
                try database.execute(sql: "INSERT INTO schema_migrations(version) VALUES (17)")
            }
            try validateVersionTwoSchema()
            try validateVersionThreeSchema()
            try validateVersionFiveSchema()
            try validateVersionSevenSchema()
            try validateVersionTenSchema()
            try validateVersionElevenSchema()
            try validateVersionTwelveSchema()
            try validateVersionThirteenSchema()
            try validateVersionFifteenSchema()
            try validateVersionSeventeenSchema()
        }
    }

    private func dropVersionOneStorage() throws {
        for table in [
            "source_status", "sessions", "session_state_events", "quota_snapshots",
            "activity_events", "hourly_usage", "usage_events", "thread_checkpoints", "source_files"
        ] {
            try database.execute(sql: "DROP TABLE IF EXISTS \(table)")
        }
    }

    private func resetImportedDataInCurrentTransaction() throws {
        for table in [
            "source_status", "sessions", "session_state_events", "quota_snapshots",
            "activity_events", "hourly_usage", "usage_events", "thread_checkpoints", "source_files"
        ] {
            try database.execute(sql: "DELETE FROM \(table)")
        }
    }

    @discardableResult
    private func insertUsageEvent(_ event: StoredUsageEvent, total: Int64) throws -> Int32 {
        let alreadyExists = !(try database.query(
            sql: "SELECT 1 AS present FROM usage_events WHERE fingerprint = ? LIMIT 1",
            bindings: [.text(event.fingerprint)]
        )).isEmpty
        try database.execute(
            sql: """
            INSERT INTO usage_events(
              fingerprint, observed_at_ms, thread_id, turn_id, source_kind, model, plan, plan_raw,
              plan_is_inferred, uncached_input_tokens, cached_input_tokens,
              visible_output_tokens, reasoning_tokens, total_tokens, source_file_id, source_offset,
              project_id, project_name, repository_id,
              workspace_id, workspace_name, workspace_root_count, workspace_is_inferred
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(fingerprint) DO UPDATE SET
              workspace_id = excluded.workspace_id,
              workspace_name = excluded.workspace_name,
              workspace_root_count = excluded.workspace_root_count,
              workspace_is_inferred = excluded.workspace_is_inferred
            WHERE
              (usage_events.workspace_id = 'unknown' AND excluded.workspace_id <> 'unknown')
              OR (
                usage_events.workspace_is_inferred = 1
                AND excluded.workspace_is_inferred = 0
                AND excluded.workspace_id <> 'unknown'
              )
            """,
            bindings: [
                .text(event.fingerprint), .integer(event.observedAtMilliseconds), .text(event.threadID),
                event.turnID.sqliteValue, .text(event.sourceKind.rawValue),
                .text(event.model), .text(event.plan.kind.rawValue),
                event.plan.rawValue.sqliteValue, .integer(event.plan.isInferred ? 1 : 0),
                .integer(event.usage.uncachedInput), .integer(event.usage.cachedInput),
                .integer(event.usage.visibleOutput), .integer(event.usage.reasoning),
                .integer(total), .text(event.sourceFileID), .integer(event.sourceOffset),
                .text(event.project.id), .text(event.project.name),
                event.project.repositoryID.sqliteValue,
                .text(event.workspace.id), .text(event.workspace.name),
                .integer(Int64(event.workspace.rootCount)),
                .integer(event.workspace.isInferred ? 1 : 0)
            ]
        )
        return alreadyExists ? 0 : 1
    }

    private func addToHourlyUsage(_ event: StoredUsageEvent, total: Int64) throws {
        let hourStart = event.observedAtMilliseconds - event.observedAtMilliseconds % 3_600_000
        let keyBindings: [SQLiteValue] = [
            .integer(hourStart), .text(event.model), .text(event.plan.kind.rawValue)
        ]
        let rows = try database.query(
            sql: """
            SELECT uncached_input_tokens, cached_input_tokens, visible_output_tokens,
                   reasoning_tokens, total_tokens
            FROM hourly_usage
            WHERE hour_start_ms = ? AND model = ? AND plan = ?
            """,
            bindings: keyBindings
        )

        guard let values = rows.first else {
            try database.execute(
                sql: """
                INSERT INTO hourly_usage(
                  hour_start_ms, model, plan, uncached_input_tokens, cached_input_tokens,
                  visible_output_tokens, reasoning_tokens, total_tokens
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: keyBindings + [
                    .integer(event.usage.uncachedInput), .integer(event.usage.cachedInput),
                    .integer(event.usage.visibleOutput), .integer(event.usage.reasoning), .integer(total)
                ]
            )
            return
        }

        let row = SQLiteRow(table: "hourly_usage", values: values)
        let uncachedInput = try checkedAdd(
            row.requiredInt64("uncached_input_tokens"),
            event.usage.uncachedInput,
            context: "hourly_usage.uncached_input_tokens"
        )
        let cachedInput = try checkedAdd(
            row.requiredInt64("cached_input_tokens"),
            event.usage.cachedInput,
            context: "hourly_usage.cached_input_tokens"
        )
        let visibleOutput = try checkedAdd(
            row.requiredInt64("visible_output_tokens"),
            event.usage.visibleOutput,
            context: "hourly_usage.visible_output_tokens"
        )
        let reasoning = try checkedAdd(
            row.requiredInt64("reasoning_tokens"),
            event.usage.reasoning,
            context: "hourly_usage.reasoning_tokens"
        )
        let updatedTotal = try checkedAdd(
            row.requiredInt64("total_tokens"),
            total,
            context: "hourly_usage.total_tokens"
        )

        try database.execute(
            sql: """
            UPDATE hourly_usage SET
              uncached_input_tokens = ?, cached_input_tokens = ?, visible_output_tokens = ?,
              reasoning_tokens = ?, total_tokens = ?
            WHERE hour_start_ms = ? AND model = ? AND plan = ?
            """,
            bindings: [
                .integer(uncachedInput), .integer(cachedInput), .integer(visibleOutput),
                .integer(reasoning), .integer(updatedTotal)
            ] + keyBindings
        )
    }

    private func insertQuotaEvent(_ event: StoredQuotaEvent) throws {
        let observation = event.observation
        guard observation.remaining.isFinite, (0...1).contains(observation.remaining) else {
            throw UsageStoreError.invalidQuotaRemaining
        }
        try database.execute(
            sql: """
            INSERT INTO quota_snapshots(
              fingerprint, observed_at_ms, thread_id, kind, window_minutes, remaining,
              resets_at_ms, plan, plan_raw, plan_is_inferred, source_kind
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(fingerprint) DO NOTHING
            """,
            bindings: [
                .text(event.fingerprint), .integer(observation.observedAtMilliseconds),
                .text(event.threadID), .text(observation.kind.rawValue),
                .integer(Int64(observation.windowMinutes)), .real(observation.remaining),
                observation.resetsAtMilliseconds.sqliteValue, .text(observation.plan.kind.rawValue),
                observation.plan.rawValue.sqliteValue, .integer(observation.plan.isInferred ? 1 : 0),
                .text(event.sourceKind.rawValue)
            ]
        )
    }

    private func insertSessionStateEvent(_ event: StoredSessionStateEvent) throws {
        try database.execute(
            sql: """
            INSERT INTO session_state_events(
              fingerprint, thread_id, turn_id, observed_at_ms, kind, source_file_id, source_offset
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(fingerprint) DO NOTHING
            """,
            bindings: [
                .text(event.fingerprint), .text(event.threadID), event.turnID.sqliteValue,
                .integer(event.observedAtMilliseconds), .text(event.kind.rawValue),
                .text(event.sourceFileID), .integer(event.sourceOffset)
            ]
        )
    }

    private func insertActivityEvent(_ event: StoredActivityEvent) throws {
        try database.execute(
            sql: """
            INSERT INTO activity_events(
              fingerprint, observed_at_ms, thread_id, turn_id, kind, name,
              source_kind, source_file_id, source_offset
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(fingerprint) DO NOTHING
            """,
            bindings: [
                .text(event.fingerprint), .integer(event.observedAtMilliseconds),
                .text(event.threadID), event.turnID.sqliteValue, .text(event.kind.rawValue),
                .text(event.name), .text(event.sourceKind.rawValue),
                .text(event.sourceFileID), .integer(event.sourceOffset)
            ]
        )
    }

    private func upsertSession(_ session: StoredSession) throws {
        try database.execute(
            sql: """
            INSERT INTO sessions(
              thread_id, source_kind, created_at_ms, updated_at_ms, activity_state, archive_state,
              child_edge_status, active_turn_id, last_activity_at_ms, last_event_key,
              archive_observed_at_ms, last_model, last_plan, source_file_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(thread_id) DO UPDATE SET
              source_kind = excluded.source_kind, created_at_ms = excluded.created_at_ms,
              updated_at_ms = excluded.updated_at_ms, activity_state = excluded.activity_state,
              archive_state = excluded.archive_state, child_edge_status = excluded.child_edge_status,
              active_turn_id = excluded.active_turn_id, last_activity_at_ms = excluded.last_activity_at_ms,
              last_event_key = excluded.last_event_key,
              archive_observed_at_ms = excluded.archive_observed_at_ms,
              last_model = excluded.last_model,
              last_plan = excluded.last_plan, source_file_id = excluded.source_file_id
            """,
            bindings: [
                .text(session.threadID), .text(session.sourceKind.rawValue),
                session.createdAtMilliseconds.sqliteValue, session.updatedAtMilliseconds.sqliteValue,
                .text(session.activity.rawValue), .text(session.archive.rawValue),
                session.childEdgeStatus.sqliteValue, session.activeTurnID.sqliteValue,
                session.state.lastActivityAtMilliseconds.sqliteValue,
                session.state.lastActivityEventKey.sqliteValue,
                session.state.archiveObservedAtMilliseconds.sqliteValue,
                session.lastModel.sqliteValue,
                (session.lastPlan?.rawValue).sqliteValue, session.sourceFileID.sqliteValue
            ]
        )
    }

    private func upsertThreadCheckpoint(_ checkpoint: ThreadCheckpoint) throws {
        try database.execute(
            sql: """
            INSERT INTO thread_checkpoints(
              thread_id, current_model, current_turn_id, plan, plan_raw, plan_is_inferred,
              input_tokens, cached_input_tokens, output_tokens,
              reasoning_tokens, counter_segment, last_token_at_ms,
              workspace_id, workspace_name, workspace_root_count, workspace_is_inferred
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(thread_id) DO UPDATE SET
              current_model = excluded.current_model, current_turn_id = excluded.current_turn_id,
              plan = excluded.plan,
              plan_raw = excluded.plan_raw, plan_is_inferred = excluded.plan_is_inferred,
              input_tokens = excluded.input_tokens,
              cached_input_tokens = excluded.cached_input_tokens, output_tokens = excluded.output_tokens,
              reasoning_tokens = excluded.reasoning_tokens, counter_segment = excluded.counter_segment,
              last_token_at_ms = excluded.last_token_at_ms,
              workspace_id = excluded.workspace_id, workspace_name = excluded.workspace_name,
              workspace_root_count = excluded.workspace_root_count,
              workspace_is_inferred = excluded.workspace_is_inferred
            """,
            bindings: [
                .text(checkpoint.threadID), checkpoint.currentModel.sqliteValue,
                checkpoint.currentTurnID.sqliteValue,
                (checkpoint.currentPlan?.kind.rawValue).sqliteValue,
                checkpoint.currentPlan.flatMap(\.rawValue).sqliteValue,
                checkpoint.currentPlan.map { $0.isInferred ? Int64(1) : Int64(0) }.sqliteValue,
                (checkpoint.counters?.input).sqliteValue, (checkpoint.counters?.cachedInput).sqliteValue,
                (checkpoint.counters?.output).sqliteValue, (checkpoint.counters?.reasoning).sqliteValue,
                .integer(checkpoint.counterSegment), checkpoint.lastTokenAtMilliseconds.sqliteValue,
                checkpoint.currentWorkspace.map(\.id).sqliteValue,
                checkpoint.currentWorkspace.map(\.name).sqliteValue,
                checkpoint.currentWorkspace.map { Int64($0.rootCount) }.sqliteValue,
                checkpoint.currentWorkspace.map { $0.isInferred ? Int64(1) : Int64(0) }.sqliteValue
            ]
        )
    }

    private func upsertFileCheckpoint(_ checkpoint: FileCheckpoint) throws {
        guard checkpoint.fileSize >= 0,
              checkpoint.committedOffset >= 0,
              checkpoint.committedOffset <= checkpoint.fileSize,
              checkpoint.activityCommittedOffset >= 0,
              checkpoint.activityCommittedOffset <= checkpoint.fileSize else {
            throw UsageStoreError.invalidFileCheckpoint(
                fileSize: checkpoint.fileSize,
                committedOffset: checkpoint.committedOffset
            )
        }
        try database.execute(
            sql: """
            INSERT INTO source_files(
              file_id, device_id, inode, path, file_size, committed_offset, generation,
              thread_id, last_record_at_ms, last_success_at_ms, format_status, last_error,
              current_model, current_turn_id, plan, plan_raw, plan_is_inferred,
              input_tokens, cached_input_tokens, output_tokens, reasoning_tokens,
              counter_segment, last_token_at_ms, activity_committed_offset,
              project_id, project_name, repository_id,
              workspace_id, workspace_name, workspace_root_count, workspace_is_inferred
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(file_id) DO UPDATE SET
              device_id = excluded.device_id, inode = excluded.inode, path = excluded.path,
              file_size = excluded.file_size, committed_offset = excluded.committed_offset,
              generation = excluded.generation, thread_id = excluded.thread_id,
              last_record_at_ms = excluded.last_record_at_ms,
              last_success_at_ms = excluded.last_success_at_ms, format_status = excluded.format_status,
              last_error = excluded.last_error, current_model = excluded.current_model,
              current_turn_id = excluded.current_turn_id,
              plan = excluded.plan, plan_raw = excluded.plan_raw,
              plan_is_inferred = excluded.plan_is_inferred,
              input_tokens = excluded.input_tokens,
              cached_input_tokens = excluded.cached_input_tokens,
              output_tokens = excluded.output_tokens,
              reasoning_tokens = excluded.reasoning_tokens,
              counter_segment = excluded.counter_segment,
              last_token_at_ms = excluded.last_token_at_ms,
              activity_committed_offset = excluded.activity_committed_offset,
              project_id = excluded.project_id,
              project_name = excluded.project_name,
              repository_id = excluded.repository_id,
              workspace_id = excluded.workspace_id,
              workspace_name = excluded.workspace_name,
              workspace_root_count = excluded.workspace_root_count,
              workspace_is_inferred = excluded.workspace_is_inferred
            """,
            bindings: [
                .text(checkpoint.fileID), .integer(checkpoint.deviceID), .integer(checkpoint.inode),
                .text(checkpoint.path), .integer(checkpoint.fileSize), .integer(checkpoint.committedOffset),
                .integer(checkpoint.generation), checkpoint.threadID.sqliteValue,
                checkpoint.lastRecordAtMilliseconds.sqliteValue,
                checkpoint.lastSuccessAtMilliseconds.sqliteValue, .text(checkpoint.formatStatus),
                checkpoint.lastError.sqliteValue, checkpoint.currentModel.sqliteValue,
                checkpoint.currentTurnID.sqliteValue,
                (checkpoint.currentPlan?.kind.rawValue).sqliteValue,
                checkpoint.currentPlan.flatMap(\.rawValue).sqliteValue,
                checkpoint.currentPlan.map { $0.isInferred ? Int64(1) : Int64(0) }.sqliteValue,
                (checkpoint.counters?.input).sqliteValue,
                (checkpoint.counters?.cachedInput).sqliteValue,
                (checkpoint.counters?.output).sqliteValue,
                (checkpoint.counters?.reasoning).sqliteValue,
                .integer(checkpoint.counterSegment),
                checkpoint.lastTokenAtMilliseconds.sqliteValue,
                .integer(checkpoint.activityCommittedOffset),
                checkpoint.project.map(\.id).sqliteValue,
                checkpoint.project.map(\.name).sqliteValue,
                checkpoint.project.flatMap(\.repositoryID).sqliteValue,
                checkpoint.workspace.map(\.id).sqliteValue,
                checkpoint.workspace.map(\.name).sqliteValue,
                checkpoint.workspace.map { Int64($0.rootCount) }.sqliteValue,
                checkpoint.workspace.map { $0.isInferred ? Int64(1) : Int64(0) }.sqliteValue
            ]
        )
    }

    private func upsertSourceStatus(
        sourceKind: String,
        state: String,
        detail: String?,
        lastSuccessAtMilliseconds: Int64?,
        processedFileCount: Int
    ) throws {
        try database.execute(
            sql: """
            INSERT INTO source_status(
              source_kind, state, detail, last_success_at_ms, processed_file_count
            ) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(source_kind) DO UPDATE SET
              state = excluded.state,
              detail = excluded.detail,
              last_success_at_ms = excluded.last_success_at_ms,
              processed_file_count = excluded.processed_file_count
            """,
            bindings: [
                .text(sourceKind), .text(state), detail.sqliteValue,
                lastSuccessAtMilliseconds.sqliteValue,
                .integer(Int64(processedFileCount))
            ]
        )
    }

    private func deleteSourceStatus(sourceKind: String) throws {
        try database.execute(
            sql: "DELETE FROM source_status WHERE source_kind = ?",
            bindings: [.text(sourceKind)]
        )
    }

    private func validatedTotal(for usage: TokenUsageDelta) throws -> Int64 {
        let components = [
            ("uncached_input_tokens", usage.uncachedInput),
            ("cached_input_tokens", usage.cachedInput),
            ("visible_output_tokens", usage.visibleOutput),
            ("reasoning_tokens", usage.reasoning)
        ]
        var total: Int64 = 0
        for (name, value) in components {
            guard value >= 0 else {
                throw UsageStoreError.invalidUsageComponent(name: name, value: value)
            }
            total = try checkedAdd(total, value, context: "usage_events.total_tokens")
        }
        return total
    }

    private func checkedAdd(_ left: Int64, _ right: Int64, context: String) throws -> Int64 {
        let (sum, overflow) = left.addingReportingOverflow(right)
        guard !overflow else {
            throw UsageStoreError.tokenOverflow(context: context)
        }
        return sum
    }

    private func count(table: String) throws -> Int64 {
        let rows = try database.query(sql: "SELECT COUNT(*) AS count FROM \(table)")
        guard let values = rows.first else {
            throw UsageStoreError.corruptColumn(
                table: table,
                column: "count",
                expected: "INTEGER",
                actual: nil
            )
        }
        return try SQLiteRow(table: table, values: values).requiredInt64("count")
    }

    private static let versionTwoStatements = [
        """
        CREATE TABLE source_files(
          file_id TEXT PRIMARY KEY, device_id INTEGER NOT NULL, inode INTEGER NOT NULL,
          path TEXT NOT NULL, file_size INTEGER NOT NULL DEFAULT 0,
          committed_offset INTEGER NOT NULL DEFAULT 0,
          generation INTEGER NOT NULL DEFAULT 0, thread_id TEXT, last_record_at_ms INTEGER,
          last_success_at_ms INTEGER, format_status TEXT NOT NULL DEFAULT 'supported', last_error TEXT,
          current_model TEXT, plan TEXT, plan_raw TEXT, plan_is_inferred INTEGER,
          input_tokens INTEGER, cached_input_tokens INTEGER, output_tokens INTEGER,
          reasoning_tokens INTEGER, counter_segment INTEGER NOT NULL DEFAULT 0,
          last_token_at_ms INTEGER
        )
        """,
        """
        CREATE TABLE thread_checkpoints(
          thread_id TEXT PRIMARY KEY, current_model TEXT,
          plan TEXT, plan_raw TEXT, plan_is_inferred INTEGER,
          input_tokens INTEGER, cached_input_tokens INTEGER, output_tokens INTEGER, reasoning_tokens INTEGER,
          counter_segment INTEGER NOT NULL DEFAULT 0, last_token_at_ms INTEGER
        )
        """,
        """
        CREATE TABLE usage_events(
          fingerprint TEXT PRIMARY KEY, observed_at_ms INTEGER NOT NULL, thread_id TEXT NOT NULL,
          source_kind TEXT NOT NULL, model TEXT NOT NULL, plan TEXT NOT NULL, plan_raw TEXT,
          plan_is_inferred INTEGER NOT NULL, uncached_input_tokens INTEGER NOT NULL,
          cached_input_tokens INTEGER NOT NULL, visible_output_tokens INTEGER NOT NULL,
          reasoning_tokens INTEGER NOT NULL, total_tokens INTEGER NOT NULL,
          source_file_id TEXT NOT NULL, source_offset INTEGER NOT NULL
        )
        """,
        "CREATE INDEX usage_events_time_idx ON usage_events(observed_at_ms)",
        "CREATE INDEX usage_events_thread_idx ON usage_events(thread_id)",
        """
        CREATE TABLE hourly_usage(
          hour_start_ms INTEGER NOT NULL, model TEXT NOT NULL, plan TEXT NOT NULL,
          uncached_input_tokens INTEGER NOT NULL, cached_input_tokens INTEGER NOT NULL,
          visible_output_tokens INTEGER NOT NULL, reasoning_tokens INTEGER NOT NULL,
          total_tokens INTEGER NOT NULL, PRIMARY KEY(hour_start_ms, model, plan)
        )
        """,
        """
        CREATE TABLE quota_snapshots(
          fingerprint TEXT PRIMARY KEY, observed_at_ms INTEGER NOT NULL, thread_id TEXT NOT NULL,
          kind TEXT NOT NULL, window_minutes INTEGER NOT NULL, remaining REAL NOT NULL,
          resets_at_ms INTEGER, plan TEXT NOT NULL, plan_raw TEXT, plan_is_inferred INTEGER NOT NULL,
          source_kind TEXT NOT NULL
        )
        """,
        "CREATE INDEX quota_latest_idx ON quota_snapshots(kind, observed_at_ms DESC)",
        """
        CREATE TABLE session_state_events(
          fingerprint TEXT PRIMARY KEY, thread_id TEXT NOT NULL, turn_id TEXT,
          observed_at_ms INTEGER NOT NULL, kind TEXT NOT NULL,
          source_file_id TEXT NOT NULL, source_offset INTEGER NOT NULL
        )
        """,
        """
        CREATE TABLE sessions(
          thread_id TEXT PRIMARY KEY, source_kind TEXT NOT NULL, created_at_ms INTEGER,
          updated_at_ms INTEGER, activity_state TEXT NOT NULL, archive_state TEXT NOT NULL,
          child_edge_status TEXT, active_turn_id TEXT, last_activity_at_ms INTEGER,
          last_event_key TEXT, archive_observed_at_ms INTEGER,
          last_model TEXT, last_plan TEXT, source_file_id TEXT
        )
        """,
        """
        CREATE TABLE source_status(
          source_kind TEXT PRIMARY KEY, state TEXT NOT NULL, detail TEXT,
          last_success_at_ms INTEGER, processed_file_count INTEGER NOT NULL DEFAULT 0
        )
        """
    ]

    private static let versionThreeStatements = [
        "ALTER TABLE source_files ADD COLUMN activity_committed_offset INTEGER NOT NULL DEFAULT 0",
        """
        CREATE TABLE activity_events(
          fingerprint TEXT PRIMARY KEY, observed_at_ms INTEGER NOT NULL,
          thread_id TEXT NOT NULL, turn_id TEXT, kind TEXT NOT NULL, name TEXT NOT NULL,
          source_kind TEXT NOT NULL, source_file_id TEXT NOT NULL, source_offset INTEGER NOT NULL
        )
        """,
        "CREATE INDEX activity_events_time_idx ON activity_events(observed_at_ms)",
        "CREATE INDEX activity_events_ranking_idx ON activity_events(kind, observed_at_ms, name)"
    ]

    private static let versionFiveStatements = [
        "ALTER TABLE source_files ADD COLUMN project_id TEXT",
        "ALTER TABLE source_files ADD COLUMN project_name TEXT",
        "ALTER TABLE usage_events ADD COLUMN project_id TEXT NOT NULL DEFAULT 'unknown'",
        "ALTER TABLE usage_events ADD COLUMN project_name TEXT NOT NULL DEFAULT '未识别项目'",
        "CREATE INDEX usage_events_project_time_idx ON usage_events(project_id, observed_at_ms)"
    ]

    private static let versionSevenStatements = [
        "ALTER TABLE source_files ADD COLUMN repository_id TEXT",
        "ALTER TABLE usage_events ADD COLUMN repository_id TEXT"
    ]

    private static let versionTenStatements = [
        "ALTER TABLE source_files ADD COLUMN current_turn_id TEXT",
        "ALTER TABLE thread_checkpoints ADD COLUMN current_turn_id TEXT",
        "ALTER TABLE usage_events ADD COLUMN turn_id TEXT",
        "CREATE INDEX usage_events_turn_idx ON usage_events(thread_id, turn_id, observed_at_ms)"
    ]

    private static let versionElevenStatements = [
        "ALTER TABLE source_files ADD COLUMN workspace_id TEXT",
        "ALTER TABLE source_files ADD COLUMN workspace_name TEXT",
        "ALTER TABLE source_files ADD COLUMN workspace_root_count INTEGER",
        "ALTER TABLE thread_checkpoints ADD COLUMN workspace_id TEXT",
        "ALTER TABLE thread_checkpoints ADD COLUMN workspace_name TEXT",
        "ALTER TABLE thread_checkpoints ADD COLUMN workspace_root_count INTEGER",
        "ALTER TABLE usage_events ADD COLUMN workspace_id TEXT NOT NULL DEFAULT 'unknown'",
        "ALTER TABLE usage_events ADD COLUMN workspace_name TEXT NOT NULL DEFAULT '未识别项目'",
        "ALTER TABLE usage_events ADD COLUMN workspace_root_count INTEGER NOT NULL DEFAULT 0",
        "CREATE INDEX usage_events_workspace_time_idx ON usage_events(workspace_id, observed_at_ms)"
    ]

    private static let versionTwelveStatements = [
        "ALTER TABLE source_files ADD COLUMN workspace_is_inferred INTEGER",
        "ALTER TABLE thread_checkpoints ADD COLUMN workspace_is_inferred INTEGER",
        "ALTER TABLE usage_events ADD COLUMN workspace_is_inferred INTEGER NOT NULL DEFAULT 0"
    ]

    private static let versionThirteenStatements = [
        """
        CREATE TABLE IF NOT EXISTS workspace_catalog(
          workspace_id TEXT PRIMARY KEY,
          workspace_name TEXT NOT NULL,
          root_count INTEGER NOT NULL
        )
        """
    ]

    private static let versionSeventeenStatements = [
        """
        CREATE TABLE IF NOT EXISTS workspace_configurations(
          configuration_id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          directories_json TEXT NOT NULL,
          updated_at_ms INTEGER NOT NULL
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS workspace_configuration_bindings(
          workspace_id TEXT NOT NULL,
          configuration_id TEXT NOT NULL,
          PRIMARY KEY(workspace_id, configuration_id)
        )
        """
    ]

    private static let versionFifteenStatements = [
        """
        CREATE TABLE IF NOT EXISTS workspace_aliases(
          source_workspace_id TEXT PRIMARY KEY,
          target_workspace_id TEXT NOT NULL,
          CHECK(source_workspace_id <> target_workspace_id)
        )
        """
    ]

    private func planResolution(from row: SQLiteRow) throws -> PlanResolution? {
        try SQLitePlanResolution.optional(from: row)
    }

    private func projectIdentity(from row: SQLiteRow) throws -> ProjectIdentity? {
        guard let id = try row.optionalString("project_id"),
              let name = try row.optionalString("project_name"),
              !id.isEmpty, !name.isEmpty else { return nil }
        return ProjectIdentity(
            id: id,
            name: name,
            repositoryID: try row.optionalString("repository_id")
        )
    }

    private func workspaceIdentity(from row: SQLiteRow) throws -> WorkspaceIdentity? {
        guard let id = try row.optionalString("workspace_id"),
              let name = try row.optionalString("workspace_name"),
              let rootCount = try row.optionalInt64("workspace_root_count"),
              !id.isEmpty, !name.isEmpty, rootCount >= 0 else { return nil }
        let inferredValue = try row.optionalInt64("workspace_is_inferred") ?? 0
        guard inferredValue == 0 || inferredValue == 1 else { return nil }
        return WorkspaceIdentity(
            id: id,
            name: name,
            rootCount: Int(clamping: rootCount),
            isInferred: inferredValue == 1
        )
    }

    private func storedSession(from row: SQLiteRow) throws -> StoredSession {
        let threadID = try row.requiredString("thread_id")
        return StoredSession(
            threadID: threadID,
            sourceKind: try row.requiredEnum("source_kind", as: CodexSourceKind.self),
            createdAtMilliseconds: try row.optionalInt64("created_at_ms"),
            updatedAtMilliseconds: try row.optionalInt64("updated_at_ms"),
            state: SessionStateSnapshot(
                threadID: threadID,
                activity: try row.requiredEnum("activity_state", as: SessionActivityState.self),
                archive: try row.requiredEnum("archive_state", as: SessionArchiveState.self),
                childEdgeStatus: try row.optionalString("child_edge_status"),
                activeTurnID: try row.optionalString("active_turn_id"),
                lastActivityAtMilliseconds: try row.optionalInt64("last_activity_at_ms"),
                lastActivityEventKey: try row.optionalString("last_event_key"),
                archiveObservedAtMilliseconds: try row.optionalInt64("archive_observed_at_ms")
            ),
            lastModel: try row.optionalString("last_model"),
            lastPlan: try row.optionalEnum("last_plan", as: PlanKind.self),
            sourceFileID: try row.optionalString("source_file_id")
        )
    }

    private func validateVersionTwoSchema() throws {
        let requiredColumns: [(table: String, columns: [String])] = [
            (
                "source_files",
                [
                    "thread_id", "current_model", "plan", "plan_raw", "plan_is_inferred",
                    "input_tokens", "cached_input_tokens", "output_tokens", "reasoning_tokens",
                    "counter_segment", "last_token_at_ms"
                ]
            ),
            ("thread_checkpoints", ["plan", "plan_raw", "plan_is_inferred"]),
            ("sessions", ["archive_observed_at_ms"])
        ]
        for requirement in requiredColumns {
            let rows = try database.query(sql: "PRAGMA table_info(\(requirement.table))")
            let existing = try Set(rows.map {
                try SQLiteRow(table: "pragma_table_info", values: $0).requiredString("name")
            })
            let missing = requirement.columns.filter { !existing.contains($0) }
            if !missing.isEmpty {
                throw UsageStoreError.rebuildRequired(
                    table: requirement.table,
                    missingColumns: missing
                )
            }
        }
    }

    private func validateVersionThreeSchema() throws {
        let requiredColumns: [(table: String, columns: [String])] = [
            ("source_files", ["activity_committed_offset"]),
            (
                "activity_events",
                [
                    "fingerprint", "observed_at_ms", "thread_id", "turn_id", "kind", "name",
                    "source_kind", "source_file_id", "source_offset"
                ]
            )
        ]
        for requirement in requiredColumns {
            let rows = try database.query(sql: "PRAGMA table_info(\(requirement.table))")
            let existing = try Set(rows.map {
                try SQLiteRow(table: "pragma_table_info", values: $0).requiredString("name")
            })
            let missing = requirement.columns.filter { !existing.contains($0) }
            if !missing.isEmpty {
                throw UsageStoreError.rebuildRequired(
                    table: requirement.table,
                    missingColumns: missing
                )
            }
        }
    }

    private func validateVersionFiveSchema() throws {
        let requiredColumns: [(table: String, columns: [String])] = [
            ("source_files", ["project_id", "project_name"]),
            ("usage_events", ["project_id", "project_name"])
        ]
        for requirement in requiredColumns {
            let rows = try database.query(sql: "PRAGMA table_info(\(requirement.table))")
            let existing = try Set(rows.map {
                try SQLiteRow(table: "pragma_table_info", values: $0).requiredString("name")
            })
            let missing = requirement.columns.filter { !existing.contains($0) }
            if !missing.isEmpty {
                throw UsageStoreError.rebuildRequired(
                    table: requirement.table,
                    missingColumns: missing
                )
            }
        }
    }

    private func validateVersionSevenSchema() throws {
        let requiredColumns: [(table: String, columns: [String])] = [
            ("source_files", ["repository_id"]),
            ("usage_events", ["repository_id"])
        ]
        for requirement in requiredColumns {
            let rows = try database.query(sql: "PRAGMA table_info(\(requirement.table))")
            let existing = try Set(rows.map {
                try SQLiteRow(table: "pragma_table_info", values: $0).requiredString("name")
            })
            let missing = requirement.columns.filter { !existing.contains($0) }
            if !missing.isEmpty {
                throw UsageStoreError.rebuildRequired(
                    table: requirement.table,
                    missingColumns: missing
                )
            }
        }
    }

    private func validateVersionTenSchema() throws {
        let requiredColumns: [(table: String, columns: [String])] = [
            ("source_files", ["current_turn_id"]),
            ("thread_checkpoints", ["current_turn_id"]),
            ("usage_events", ["turn_id"])
        ]
        for requirement in requiredColumns {
            let rows = try database.query(sql: "PRAGMA table_info(\(requirement.table))")
            let existing = try Set(rows.map {
                try SQLiteRow(table: "pragma_table_info", values: $0).requiredString("name")
            })
            let missing = requirement.columns.filter { !existing.contains($0) }
            if !missing.isEmpty {
                throw UsageStoreError.rebuildRequired(
                    table: requirement.table,
                    missingColumns: missing
                )
            }
        }
    }

    private func validateVersionElevenSchema() throws {
        let requiredColumns: [(table: String, columns: [String])] = [
            ("source_files", ["workspace_id", "workspace_name", "workspace_root_count"]),
            ("thread_checkpoints", ["workspace_id", "workspace_name", "workspace_root_count"]),
            ("usage_events", ["workspace_id", "workspace_name", "workspace_root_count"])
        ]
        for requirement in requiredColumns {
            let rows = try database.query(sql: "PRAGMA table_info(\(requirement.table))")
            let existing = try Set(rows.map {
                try SQLiteRow(table: "pragma_table_info", values: $0).requiredString("name")
            })
            let missing = requirement.columns.filter { !existing.contains($0) }
            if !missing.isEmpty {
                throw UsageStoreError.rebuildRequired(
                    table: requirement.table,
                    missingColumns: missing
                )
            }
        }
    }

    private func validateVersionTwelveSchema() throws {
        let requiredColumns: [(table: String, columns: [String])] = [
            ("source_files", ["workspace_is_inferred"]),
            ("thread_checkpoints", ["workspace_is_inferred"]),
            ("usage_events", ["workspace_is_inferred"])
        ]
        for requirement in requiredColumns {
            let rows = try database.query(sql: "PRAGMA table_info(\(requirement.table))")
            let existing = try Set(rows.map {
                try SQLiteRow(table: "pragma_table_info", values: $0).requiredString("name")
            })
            let missing = requirement.columns.filter { !existing.contains($0) }
            if !missing.isEmpty {
                throw UsageStoreError.rebuildRequired(
                    table: requirement.table,
                    missingColumns: missing
                )
            }
        }
    }

    private func validateVersionThirteenSchema() throws {
        let rows = try database.query(sql: "PRAGMA table_info(workspace_catalog)")
        let existing = try Set(rows.map {
            try SQLiteRow(table: "pragma_table_info", values: $0).requiredString("name")
        })
        let required = Set(["workspace_id", "workspace_name", "root_count"])
        let missing = required.subtracting(existing).sorted()
        if !missing.isEmpty {
            throw UsageStoreError.rebuildRequired(
                table: "workspace_catalog",
                missingColumns: missing
            )
        }
    }

    private func validateVersionSeventeenSchema() throws {
        for (table, columns) in [
            ("workspace_configurations", ["configuration_id", "name", "directories_json", "updated_at_ms"]),
            ("workspace_configuration_bindings", ["workspace_id", "configuration_id"])
        ] {
            let existing = Set(try schemaColumns(table: table))
            let missing = Set(columns).subtracting(existing).sorted()
            if !missing.isEmpty {
                throw UsageStoreError.rebuildRequired(table: table, missingColumns: missing)
            }
        }
    }

    private func validateVersionFifteenSchema() throws {
        let rows = try database.query(sql: "PRAGMA table_info(workspace_aliases)")
        let existing = try Set(rows.map {
            try SQLiteRow(table: "pragma_table_info", values: $0).requiredString("name")
        })
        let required = Set(["source_workspace_id", "target_workspace_id"])
        let missing = required.subtracting(existing).sorted()
        if !missing.isEmpty {
            throw UsageStoreError.rebuildRequired(
                table: "workspace_aliases",
                missingColumns: missing
            )
        }
    }
}

enum UsageStoreError: Error, Equatable {
    case unsupportedSchemaVersion(Int64)
    case rebuildRequired(table: String, missingColumns: [String])
    case invalidFileCheckpoint(fileSize: Int64, committedOffset: Int64)
    case invalidUsageComponent(name: String, value: Int64)
    case invalidQuotaRemaining
    case invalidWorkspaceAlias
    case tokenOverflow(context: String)
    case corruptColumn(table: String, column: String, expected: String, actual: SQLiteValue?)
    case corruptEnum(table: String, column: String, value: String)
}

private extension Optional where Wrapped == String {
    var sqliteValue: SQLiteValue {
        map(SQLiteValue.text) ?? .null
    }
}

private extension Optional where Wrapped == Int64 {
    var sqliteValue: SQLiteValue {
        map(SQLiteValue.integer) ?? .null
    }
}

private extension Int64 {
    var sqliteValue: SQLiteValue { .integer(self) }
}

private struct SQLiteRow {
    let table: String
    let values: [String: SQLiteValue]

    func requiredInt64(_ column: String) throws -> Int64 {
        guard case let .integer(value)? = values[column] else {
            throw corruptColumn(column, expected: "INTEGER")
        }
        return value
    }

    func optionalInt64(_ column: String) throws -> Int64? {
        switch values[column] {
        case let .integer(value):
            return value
        case .null:
            return nil
        default:
            throw corruptColumn(column, expected: "INTEGER or NULL")
        }
    }

    func requiredDouble(_ column: String) throws -> Double {
        guard case let .real(value)? = values[column] else {
            throw corruptColumn(column, expected: "REAL")
        }
        return value
    }

    func requiredString(_ column: String) throws -> String {
        guard case let .text(value)? = values[column] else {
            throw corruptColumn(column, expected: "TEXT")
        }
        return value
    }

    func optionalString(_ column: String) throws -> String? {
        switch values[column] {
        case let .text(value):
            return value
        case .null:
            return nil
        default:
            throw corruptColumn(column, expected: "TEXT or NULL")
        }
    }

    func requiredEnum<T>(_ column: String, as type: T.Type) throws -> T
    where T: RawRepresentable, T.RawValue == String {
        let value = try requiredString(column)
        guard let result = T(rawValue: value) else {
            throw UsageStoreError.corruptEnum(table: table, column: column, value: value)
        }
        return result
    }

    func optionalEnum<T>(_ column: String, as type: T.Type) throws -> T?
    where T: RawRepresentable, T.RawValue == String {
        guard let value = try optionalString(column) else { return nil }
        guard let result = T(rawValue: value) else {
            throw UsageStoreError.corruptEnum(table: table, column: column, value: value)
        }
        return result
    }

    private func corruptColumn(_ column: String, expected: String) -> UsageStoreError {
        UsageStoreError.corruptColumn(
            table: table,
            column: column,
            expected: expected,
            actual: values[column]
        )
    }
}

private enum SQLitePlanResolution {
    static func from(row: SQLiteRow) throws -> PlanResolution {
        guard let result = try optional(from: row) else {
            throw UsageStoreError.corruptColumn(
                table: row.table,
                column: "plan",
                expected: "TEXT",
                actual: row.values["plan"]
            )
        }
        return result
    }

    static func optional(from row: SQLiteRow) throws -> PlanResolution? {
        guard let storedKind = try row.optionalEnum("plan", as: PlanKind.self) else { return nil }
        guard let inferred = try row.optionalInt64("plan_is_inferred"), inferred == 0 || inferred == 1 else {
            throw UsageStoreError.corruptColumn(
                table: row.table,
                column: "plan_is_inferred",
                expected: "INTEGER boolean",
                actual: row.values["plan_is_inferred"]
            )
        }
        let rawValue = try row.optionalString("plan_raw")
        let resolvedRaw = PlanResolver.resolve(rawValue: rawValue)
        let kind = resolvedRaw.isInferred ? storedKind : resolvedRaw.kind
        return PlanResolution(
            kind: kind,
            rawValue: rawValue,
            isInferred: inferred == 1
        )
    }
}
