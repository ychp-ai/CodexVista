import CryptoKit
import Foundation
import SQLite3

struct RolloutFile: Equatable, Sendable {
    let fileID: String
    let deviceID: UInt64
    let inode: UInt64
    let url: URL
    let fileSize: Int64
    let modificationTimeMilliseconds: Int64
    let isArchived: Bool
    let thread: ThreadIndexRecord?
}

struct ThreadIndexRecord: Equatable, Sendable {
    let threadID: String
    let rolloutPath: String
    let sourceRaw: String
    let model: String?
    let displayTitle: String?
    let createdAtMilliseconds: Int64
    let updatedAtMilliseconds: Int64
    let archived: Bool
    let parentThreadID: String?
    let childEdgeStatus: String?

    init(
        threadID: String,
        rolloutPath: String,
        sourceRaw: String,
        model: String?,
        displayTitle: String? = nil,
        createdAtMilliseconds: Int64,
        updatedAtMilliseconds: Int64,
        archived: Bool,
        parentThreadID: String? = nil,
        childEdgeStatus: String?
    ) {
        self.threadID = threadID
        self.rolloutPath = rolloutPath
        self.sourceRaw = sourceRaw
        self.model = model
        self.displayTitle = displayTitle
        self.createdAtMilliseconds = createdAtMilliseconds
        self.updatedAtMilliseconds = updatedAtMilliseconds
        self.archived = archived
        self.parentThreadID = parentThreadID
        self.childEdgeStatus = childEdgeStatus
    }
}

struct CodexThreadDashboardMetadata: Equatable, Sendable {
    let displayTitlesByThreadID: [String: String]
    let parentThreadIDsByChildThreadID: [String: String]
    let childThreadRelationsByChildThreadID: [String: CodexChildThreadRelation]
}

struct CodexChildThreadRelation: Equatable, Sendable {
    let parentThreadID: String
    let childCreatedAtMilliseconds: Int64
}

enum CodexIndexHealth: Equatable, Sendable {
    case available
    case missing
    case degraded(String)
}

struct CodexSourceInventory: Equatable, Sendable {
    let rollouts: [RolloutFile]
    let threadIndex: [ThreadIndexRecord]
    let workspaceMetadata: [CodexWorkspaceMetadata]
    let indexHealth: CodexIndexHealth
}

struct CodexWorkspaceMetadata: Equatable, Sendable {
    let configurationID: String
    let name: String
    let rootPaths: [String]
    let historicalRootPaths: [[String]]
    let updatedAtMilliseconds: Int64
    let isCurrent: Bool
}

struct CodexSourceDiscovery {
    private let fileManager: FileManager
    private let indexReader: CodexThreadIndexReader
    private let workspaceMetadataReader: CodexWorkspaceMetadataReader

    init(
        fileManager: FileManager = .default,
        indexReader: CodexThreadIndexReader = CodexThreadIndexReader(),
        workspaceMetadataReader: CodexWorkspaceMetadataReader = CodexWorkspaceMetadataReader()
    ) {
        self.fileManager = fileManager
        self.indexReader = indexReader
        self.workspaceMetadataReader = workspaceMetadataReader
    }

    func discover(rootURL: URL) throws -> CodexSourceInventory {
        let indexResult = readIndex(at: rootURL)
        var recordsByPath: [String: ThreadIndexRecord] = [:]
        for record in indexResult.records {
            recordsByPath[canonicalPath(record.rolloutPath)] = record
        }

        let sessionsURL = rootURL.appending(path: "sessions", directoryHint: .isDirectory)
        let archiveURL = rootURL.appending(path: "archived_sessions", directoryHint: .isDirectory)
        let activeURLs = try recursiveJSONLFiles(at: sessionsURL)
        let archivedURLs = try directJSONLFiles(at: archiveURL)

        var rollouts: [RolloutFile] = []
        rollouts.reserveCapacity(activeURLs.count + archivedURLs.count)
        for url in activeURLs {
            rollouts.append(try rollout(url: url, isArchived: false, recordsByPath: recordsByPath))
        }
        for url in archivedURLs {
            rollouts.append(try rollout(url: url, isArchived: true, recordsByPath: recordsByPath))
        }
        rollouts.sort { $0.url.path < $1.url.path }

        return CodexSourceInventory(
            rollouts: rollouts,
            threadIndex: indexResult.records,
            workspaceMetadata: workspaceMetadataReader.read(rootURL: rootURL),
            indexHealth: indexResult.health
        )
    }

    func threadDisplayTitles(rootURL: URL) -> [String: String] {
        threadDashboardMetadata(rootURL: rootURL).displayTitlesByThreadID
    }

    func threadDashboardMetadata(rootURL: URL) -> CodexThreadDashboardMetadata {
        let records = readIndex(at: rootURL).records
        let displayTitles = records.reduce(into: [String: String]()) { result, record in
            if let displayTitle = record.displayTitle {
                result[record.threadID] = displayTitle
            }
        }
        let relations = records.reduce(into: [String: CodexChildThreadRelation]()) {
            result, record in
            if let parentThreadID = record.parentThreadID {
                result[record.threadID] = CodexChildThreadRelation(
                    parentThreadID: parentThreadID,
                    childCreatedAtMilliseconds: record.createdAtMilliseconds
                )
            } else if record.sourceRaw.localizedCaseInsensitiveContains("subagent"),
                      let relation = sessionThreadRelation(for: record) {
                result[record.threadID] = relation
            }
        }
        return CodexThreadDashboardMetadata(
            displayTitlesByThreadID: displayTitles,
            parentThreadIDsByChildThreadID: relations.mapValues(\.parentThreadID),
            childThreadRelationsByChildThreadID: relations
        )
    }

    private func sessionThreadRelation(
        for record: ThreadIndexRecord
    ) -> CodexChildThreadRelation? {
        let url = URL(fileURLWithPath: record.rolloutPath)
        guard fileManager.fileExists(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        let maximumLineBytes = 2 * 1_024 * 1_024
        var data = Data()
        while data.count < maximumLineBytes {
            guard let chunk = try? handle.read(
                upToCount: min(64 * 1_024, maximumLineBytes - data.count)
            ), !chunk.isEmpty else {
                break
            }
            data.append(chunk)
            if let newline = data.firstIndex(of: 0x0A) {
                data = Data(data[..<newline])
                break
            }
        }
        guard !data.isEmpty,
              let envelope = try? JSONDecoder().decode(
                SafeSessionRelationshipEnvelope.self,
                from: data
              ),
              envelope.type == "session_meta",
              envelope.payload.id == record.threadID,
              let parentThreadID = envelope.payload.parentThreadID
                ?? envelope.payload.source?.subagent?.threadSpawn?.parentThreadID,
              !parentThreadID.isEmpty else {
            return nil
        }
        let timestamp = envelope.timestamp ?? envelope.payload.timestamp
        return CodexChildThreadRelation(
            parentThreadID: parentThreadID,
            childCreatedAtMilliseconds: timestamp.flatMap(sessionTimestampMilliseconds)
                ?? record.createdAtMilliseconds
        )
    }

    private func sessionTimestampMilliseconds(_ rawValue: String) -> Int64? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: rawValue) else { return nil }
        let milliseconds = date.timeIntervalSince1970 * 1_000
        guard milliseconds.isFinite,
              milliseconds >= Double(Int64.min),
              milliseconds <= Double(Int64.max) else {
            return nil
        }
        return Int64(milliseconds.rounded())
    }

    private func readIndex(at rootURL: URL) -> (records: [ThreadIndexRecord], health: CodexIndexHealth) {
        guard let databaseURL = newestStateDatabase(in: rootURL) else {
            return ([], .missing)
        }

        do {
            let records = try indexReader.read(databaseURL: databaseURL)
            return (records, .available)
        } catch let error as CodexThreadIndexError {
            return ([], .degraded(error.description))
        } catch {
            return ([], .degraded("index read failed"))
        }
    }

    private func newestStateDatabase(in rootURL: URL) -> URL? {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return entries.compactMap { url -> (url: URL, suffix: String)? in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return nil
            }
            let name = url.lastPathComponent
            guard name.hasPrefix("state_"), name.hasSuffix(".sqlite") else { return nil }
            let start = name.index(name.startIndex, offsetBy: "state_".count)
            let end = name.index(name.endIndex, offsetBy: -".sqlite".count)
            let suffix = String(name[start..<end])
            guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber) else { return nil }
            let normalized = String(suffix.drop(while: { $0 == "0" }))
            return (url, normalized.isEmpty ? "0" : normalized)
        }.max { lhs, rhs in
            if lhs.suffix.count != rhs.suffix.count {
                return lhs.suffix.count < rhs.suffix.count
            }
            return lhs.suffix < rhs.suffix
        }?.url
    }

    private func recursiveJSONLFiles(at directory: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        var traversalError: Error?
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, error in
                traversalError = error
                return false
            }
        ) else {
            throw CodexSourceDiscoveryError.unreadableDirectory
        }

        var result: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true { result.append(url) }
        }
        if let traversalError { throw traversalError }
        return result
    }

    private func directJSONLFiles(at directory: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            guard url.pathExtension == "jsonl" else { return false }
            return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    private func rollout(
        url: URL,
        isArchived: Bool,
        recordsByPath: [String: ThreadIndexRecord]
    ) throws -> RolloutFile {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber,
              let size = attributes[.size] as? NSNumber,
              let modificationDate = attributes[.modificationDate] as? Date else {
            throw CodexSourceDiscoveryError.missingFileAttributes
        }
        let milliseconds = modificationDate.timeIntervalSince1970 * 1_000
        guard milliseconds.isFinite,
              milliseconds >= Double(Int64.min),
              milliseconds <= Double(Int64.max) else {
            throw CodexSourceDiscoveryError.invalidModificationDate
        }

        let deviceID = device.uint64Value
        let inodeValue = inode.uint64Value
        let path = canonicalPath(url.path)
        let thread = recordsByPath[path]
        let identity = "\(path)|\(thread?.threadID ?? "unindexed")"
        let fileID = SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return RolloutFile(
            fileID: fileID,
            deviceID: deviceID,
            inode: inodeValue,
            url: url,
            fileSize: size.int64Value,
            modificationTimeMilliseconds: Int64(milliseconds.rounded()),
            isArchived: isArchived,
            thread: thread
        )
    }

    private func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}

struct CodexWorkspaceMetadataReader {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func read(rootURL: URL) -> [CodexWorkspaceMetadata] {
        let candidates = stateFiles(rootURL: rootURL).sorted { left, right in
            let leftIsCurrent = left.lastPathComponent == ".codex-global-state.json"
            let rightIsCurrent = right.lastPathComponent == ".codex-global-state.json"
            if leftIsCurrent != rightIsCurrent { return !leftIsCurrent }
            let leftDate = modificationDate(left)
            let rightDate = modificationDate(right)
            if leftDate != rightDate { return leftDate < rightDate }
            return left.lastPathComponent < right.lastPathComponent
        }
        var metadataByProjectID: [String: CodexWorkspaceMetadata] = [:]
        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let state = try? JSONDecoder().decode(CodexGlobalState.self, from: data) else {
                continue
            }
            for (projectID, project) in state.localProjects.sorted(by: { $0.key < $1.key }) {
                guard !projectID.isEmpty else { continue }
                let normalizedName = project.name
                    .split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
                guard !normalizedName.isEmpty else { continue }
                let previous = metadataByProjectID[projectID]
                var historicalRoots = previous?.historicalRootPaths ?? []
                if !historicalRoots.contains(project.rootPaths) {
                    historicalRoots.append(project.rootPaths)
                }
                let updatedAt = project.updatedAt
                    ?? Int64((modificationDate(url).timeIntervalSince1970 * 1_000).rounded())
                let isCurrent = url.lastPathComponent == ".codex-global-state.json"
                let preferredPrevious = previous.flatMap {
                    !isCurrent && $0.updatedAtMilliseconds > updatedAt ? $0 : nil
                }
                let configurationID = SHA256.hash(data: Data("codex-local-project-v1|\(projectID)".utf8))
                    .map { String(format: "%02x", $0) }.joined()
                metadataByProjectID[projectID] = CodexWorkspaceMetadata(
                    configurationID: configurationID,
                    name: preferredPrevious?.name ?? String(normalizedName.prefix(120)),
                    rootPaths: preferredPrevious?.rootPaths ?? project.rootPaths,
                    historicalRootPaths: historicalRoots,
                    updatedAtMilliseconds: preferredPrevious?.updatedAtMilliseconds ?? updatedAt,
                    isCurrent: isCurrent
                )
            }
        }
        return metadataByProjectID.values.sorted { left, right in
            left.configurationID < right.configurationID
        }
    }

    private func stateFiles(rootURL: URL) -> [URL] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey]
        ) else {
            return []
        }
        return entries.filter { url in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return false
            }
            let name = url.lastPathComponent
            return name == ".codex-global-state.json"
                || name == ".codex-global-state.json.bak"
                || name.hasPrefix("..codex-global-state.json.tmp-")
        }
    }

    private func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }
}

private struct CodexGlobalState: Decodable {
    let localProjects: [String: CodexLocalProject]

    enum CodingKeys: String, CodingKey {
        case localProjects = "local-projects"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        localProjects = try container.decodeIfPresent(
            [String: CodexLocalProject].self,
            forKey: .localProjects
        ) ?? [:]
    }
}

private struct CodexLocalProject: Decodable {
    let name: String
    let rootPaths: [String]
    let updatedAt: Int64?
}

enum CodexSourceDiscoveryError: Error {
    case unreadableDirectory
    case missingFileAttributes
    case invalidModificationDate
}

struct CodexThreadIndexReader {
    func read(databaseURL: URL) throws -> [ThreadIndexRecord] {
        var optionalDatabase: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &optionalDatabase,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let database = optionalDatabase else {
            if let optionalDatabase { sqlite3_close_v2(optionalDatabase) }
            throw CodexThreadIndexError.openFailed(openResult)
        }
        defer { sqlite3_close_v2(database) }

        let timeoutResult = sqlite3_busy_timeout(database, 100)
        guard timeoutResult == SQLITE_OK else {
            throw CodexThreadIndexError.busyTimeoutFailed(timeoutResult)
        }

        let threadColumns = try columns(in: "threads", database: database)
        guard !threadColumns.isEmpty else {
            throw CodexThreadIndexError.missingTable("threads")
        }
        let requiredThreadColumns: Set<String> = ["id", "rollout_path", "source", "archived"]
        var missingThreadColumns = requiredThreadColumns.subtracting(threadColumns).sorted()
        if threadColumns.isDisjoint(with: ["created_at_ms", "created_at"]) {
            missingThreadColumns.append("created_at_ms|created_at")
        }
        if threadColumns.isDisjoint(with: ["updated_at_ms", "updated_at"]) {
            missingThreadColumns.append("updated_at_ms|updated_at")
        }
        guard missingThreadColumns.isEmpty else {
            throw CodexThreadIndexError.missingColumns(table: "threads", columns: missingThreadColumns)
        }

        let edgeColumns = try columns(in: "thread_spawn_edges", database: database)
        if !edgeColumns.isEmpty {
            let requiredEdgeColumns: Set<String> = ["child_thread_id", "status"]
            let missingEdgeColumns = requiredEdgeColumns.subtracting(edgeColumns).sorted()
            guard missingEdgeColumns.isEmpty else {
                throw CodexThreadIndexError.missingColumns(
                    table: "thread_spawn_edges",
                    columns: missingEdgeColumns
                )
            }
        }

        let usesMillisecondCreatedAt = threadColumns.contains("created_at_ms")
        let usesMillisecondUpdatedAt = threadColumns.contains("updated_at_ms")
        let modelExpression = threadColumns.contains("model") ? "model" : "NULL"
        let nameExpression = threadColumns.contains("name") ? "name" : "NULL"
        let titleExpression = threadColumns.contains("title") ? "title" : "NULL"
        let agentNicknameExpression = threadColumns.contains("agent_nickname")
            ? "agent_nickname" : "NULL"
        let agentRoleExpression = threadColumns.contains("agent_role") ? "agent_role" : "NULL"
        let createdExpression = usesMillisecondCreatedAt ? "created_at_ms" : "created_at"
        let updatedExpression = usesMillisecondUpdatedAt ? "updated_at_ms" : "updated_at"
        let sql = """
            SELECT id, rollout_path, source, \(modelExpression) AS model,
                   \(nameExpression) AS display_name, \(titleExpression) AS title,
                   \(agentNicknameExpression) AS agent_nickname,
                   \(agentRoleExpression) AS agent_role,
                   \(createdExpression) AS created_value,
                   \(updatedExpression) AS updated_value, archived
            FROM threads ORDER BY id
            """
        var records = try readThreads(
            database: database,
            sql: sql,
            createdAtIsMilliseconds: usesMillisecondCreatedAt,
            updatedAtIsMilliseconds: usesMillisecondUpdatedAt
        )

        guard !edgeColumns.isEmpty, !records.isEmpty else { return records }
        let edges = try readEdges(
            database: database,
            knownThreadIDs: Set(records.map(\.threadID)),
            includesParentThreadID: edgeColumns.contains("parent_thread_id")
        )
        records = records.map { record in
            ThreadIndexRecord(
                threadID: record.threadID,
                rolloutPath: record.rolloutPath,
                sourceRaw: record.sourceRaw,
                model: record.model,
                displayTitle: record.displayTitle,
                createdAtMilliseconds: record.createdAtMilliseconds,
                updatedAtMilliseconds: record.updatedAtMilliseconds,
                archived: record.archived,
                parentThreadID: edges[record.threadID]?.parentThreadID,
                childEdgeStatus: edges[record.threadID]?.status
            )
        }
        return records
    }

    private func columns(in table: String, database: OpaquePointer) throws -> Set<String> {
        let sql = "PRAGMA table_info(\(table))"
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw CodexThreadIndexError.queryFailed(prepareResult, context: "inspect \(table)")
        }
        defer { sqlite3_finalize(statement) }

        var result: Set<String> = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let pointer = sqlite3_column_text(statement, 1) else {
                    throw CodexThreadIndexError.invalidValue("\(table).column")
                }
                result.insert(String(cString: pointer))
            case SQLITE_DONE:
                return result
            case let code:
                throw CodexThreadIndexError.queryFailed(code, context: "inspect \(table)")
            }
        }
    }

    private func readThreads(
        database: OpaquePointer,
        sql: String,
        createdAtIsMilliseconds: Bool,
        updatedAtIsMilliseconds: Bool
    ) throws -> [ThreadIndexRecord] {
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw CodexThreadIndexError.queryFailed(prepareResult, context: "read threads")
        }
        defer { sqlite3_finalize(statement) }

        var records: [ThreadIndexRecord] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                let created = try requiredInteger(statement, column: 8, name: "threads.created_at")
                let updated = try requiredInteger(statement, column: 9, name: "threads.updated_at")
                let displayName = try optionalText(statement, column: 4, name: "threads.name")
                let title = try optionalText(statement, column: 5, name: "threads.title")
                let agentNickname = try optionalText(
                    statement, column: 6, name: "threads.agent_nickname"
                )
                let agentRole = try optionalText(statement, column: 7, name: "threads.agent_role")
                let sourceRaw = try requiredText(statement, column: 2, name: "threads.source")
                records.append(ThreadIndexRecord(
                    threadID: try requiredText(statement, column: 0, name: "threads.id"),
                    rolloutPath: try requiredText(statement, column: 1, name: "threads.rollout_path"),
                    sourceRaw: sourceRaw,
                    model: try optionalText(statement, column: 3, name: "threads.model"),
                    displayTitle: resolvedDisplayTitle(
                        displayName: displayName,
                        title: title,
                        agentNickname: agentNickname,
                        agentRole: agentRole,
                        sourceRaw: sourceRaw
                    ),
                    createdAtMilliseconds: try milliseconds(created, alreadyMilliseconds: createdAtIsMilliseconds),
                    updatedAtMilliseconds: try milliseconds(updated, alreadyMilliseconds: updatedAtIsMilliseconds),
                    archived: try requiredBoolean(statement, column: 10, name: "threads.archived"),
                    childEdgeStatus: nil
                ))
            case SQLITE_DONE:
                return records
            case let code:
                throw CodexThreadIndexError.queryFailed(code, context: "read threads")
            }
        }
    }

    private func resolvedDisplayTitle(
        displayName: String?,
        title: String?,
        agentNickname: String?,
        agentRole: String?,
        sourceRaw: String
    ) -> String? {
        let sourceMetadata = try? JSONDecoder().decode(
            SafeThreadSourceMetadata.self,
            from: Data(sourceRaw.utf8)
        )
        let normalizedSource = sourceRaw.lowercased()
        // Codex now backfills names such as "Guardian review" on historical checks.
        // Preserve their internal identity before considering any display metadata.
        if sourceMetadata?.subagent?.other?.lowercased() == "guardian"
            || normalizedSource == "guardian" {
            return "命令权限检查"
        }
        if let displayName = normalizedDisplayTitle(displayName) {
            return displayName
        }
        if let title = normalizedDisplayTitle(title), !isSystemTemplateTitle(title) {
            return title
        }
        if let nickname = normalizedDisplayTitle(agentNickname) {
            return "Codex 子任务 · \(nickname)"
        }
        if let role = normalizedDisplayTitle(agentRole) {
            return "Codex 子任务 · \(role)"
        }

        if let spawn = sourceMetadata?.subagent?.threadSpawn {
            if let nickname = normalizedDisplayTitle(spawn.agentNickname) {
                return "Codex 子任务 · \(nickname)"
            }
            if let role = normalizedDisplayTitle(spawn.agentRole) {
                return "Codex 子任务 · \(role)"
            }
            return "Codex 子任务"
        }
        if normalizedSource.contains("guardian") { return "命令权限检查" }
        if normalizedSource.contains("subagent") { return "Codex 子任务" }
        return nil
    }

    private func normalizedDisplayTitle(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let singleLine = rawValue.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !singleLine.isEmpty else { return nil }
        return String(singleLine.prefix(120))
    }

    private func isSystemTemplateTitle(_ title: String) -> Bool {
        title.lowercased().hasPrefix("the following is the codex")
    }

    private func readEdges(
        database: OpaquePointer,
        knownThreadIDs: Set<String>,
        includesParentThreadID: Bool
    ) throws -> [String: ThreadSpawnEdgeRecord] {
        let parentExpression = includesParentThreadID ? "parent_thread_id" : "NULL"
        let sql = """
            SELECT child_thread_id, status, \(parentExpression)
            FROM thread_spawn_edges ORDER BY child_thread_id
            """
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw CodexThreadIndexError.queryFailed(prepareResult, context: "read thread edges")
        }
        defer { sqlite3_finalize(statement) }

        var edges: [String: ThreadSpawnEdgeRecord] = [:]
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                let threadID = try requiredText(
                    statement,
                    column: 0,
                    name: "thread_spawn_edges.child_thread_id"
                )
                guard knownThreadIDs.contains(threadID) else { continue }
                guard let status = try optionalText(
                    statement,
                    column: 1,
                    name: "thread_spawn_edges.status"
                ) else { continue }
                let edge = ThreadSpawnEdgeRecord(
                    parentThreadID: try optionalText(
                        statement,
                        column: 2,
                        name: "thread_spawn_edges.parent_thread_id"
                    ),
                    status: status
                )
                if let existing = edges[threadID], existing != edge {
                    throw CodexThreadIndexError.conflictingChildStatuses
                }
                edges[threadID] = edge
            case SQLITE_DONE:
                return edges
            case let code:
                throw CodexThreadIndexError.queryFailed(code, context: "read thread edges")
            }
        }
    }

    private func requiredText(_ statement: OpaquePointer, column: Int32, name: String) throws -> String {
        guard sqlite3_column_type(statement, column) == SQLITE_TEXT,
              let pointer = sqlite3_column_text(statement, column) else {
            throw CodexThreadIndexError.invalidValue(name)
        }
        return String(cString: pointer)
    }

    private func optionalText(_ statement: OpaquePointer, column: Int32, name: String) throws -> String? {
        if sqlite3_column_type(statement, column) == SQLITE_NULL { return nil }
        return try requiredText(statement, column: column, name: name)
    }

    private func requiredInteger(_ statement: OpaquePointer, column: Int32, name: String) throws -> Int64 {
        guard sqlite3_column_type(statement, column) == SQLITE_INTEGER else {
            throw CodexThreadIndexError.invalidValue(name)
        }
        return sqlite3_column_int64(statement, column)
    }

    private func requiredBoolean(_ statement: OpaquePointer, column: Int32, name: String) throws -> Bool {
        let value = try requiredInteger(statement, column: column, name: name)
        guard value == 0 || value == 1 else {
            throw CodexThreadIndexError.invalidValue(name)
        }
        return value == 1
    }

    private func milliseconds(_ value: Int64, alreadyMilliseconds: Bool) throws -> Int64 {
        guard !alreadyMilliseconds else { return value }
        let (result, overflow) = value.multipliedReportingOverflow(by: 1_000)
        guard !overflow else { throw CodexThreadIndexError.timestampOverflow }
        return result
    }
}

private struct ThreadSpawnEdgeRecord: Equatable {
    let parentThreadID: String?
    let status: String
}

private struct SafeThreadSourceMetadata: Decodable {
    let subagent: SafeSubagentMetadata?
}

private struct SafeSubagentMetadata: Decodable {
    let other: String?
    let threadSpawn: SafeThreadSpawnMetadata?

    enum CodingKeys: String, CodingKey {
        case other
        case threadSpawn = "thread_spawn"
    }
}

private struct SafeThreadSpawnMetadata: Decodable {
    let agentNickname: String?
    let agentRole: String?
    let parentThreadID: String?

    enum CodingKeys: String, CodingKey {
        case agentNickname = "agent_nickname"
        case agentRole = "agent_role"
        case parentThreadID = "parent_thread_id"
    }
}

private struct SafeSessionRelationshipEnvelope: Decodable {
    let timestamp: String?
    let type: String
    let payload: SafeSessionRelationshipPayload
}

private struct SafeSessionRelationshipPayload: Decodable {
    let id: String?
    let timestamp: String?
    let parentThreadID: String?
    let source: SafeThreadSourceMetadata?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
        parentThreadID = try container.decodeIfPresent(String.self, forKey: .parentThreadID)
        source = try? container.decode(SafeThreadSourceMetadata.self, forKey: .source)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case source
        case parentThreadID = "parent_thread_id"
    }
}

enum CodexThreadIndexError: Error, CustomStringConvertible, Equatable {
    case openFailed(Int32)
    case busyTimeoutFailed(Int32)
    case missingTable(String)
    case missingColumns(table: String, columns: [String])
    case queryFailed(Int32, context: String)
    case invalidValue(String)
    case timestampOverflow
    case conflictingChildStatuses

    var description: String {
        switch self {
        case .openFailed:
            return "index open failed"
        case .busyTimeoutFailed:
            return "index busy timeout setup failed"
        case let .missingTable(table):
            return "missing table: \(table)"
        case let .missingColumns(table, columns):
            return "missing columns in \(table): \(columns.joined(separator: ","))"
        case let .queryFailed(_, context):
            return "index query failed: \(context)"
        case let .invalidValue(column):
            return "invalid index value: \(column)"
        case .timestampOverflow:
            return "index timestamp overflow"
        case .conflictingChildStatuses:
            return "conflicting child edge statuses"
        }
    }
}
