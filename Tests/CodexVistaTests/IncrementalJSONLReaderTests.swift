import Foundation
import XCTest
@testable import CodexVista

final class IncrementalJSONLReaderTests: XCTestCase {
    func testCommitsOnlyCompleteLinesAndContinuesAfterAppendAcrossChunkBoundaries() throws {
        let url = try temporaryFile(contents: "{\"type\":\"one\"}\n{\"type\":\"two")
        let reader = IncrementalJSONLReader(chunkSize: 8)

        let first = try reader.read(file: url, fromOffset: 0)

        XCTAssertEqual(first.lines.map { String(decoding: $0.data, as: UTF8.self) }, ["{\"type\":\"one\"}"])
        XCTAssertEqual(first.lines.map(\.endOffset), [15])
        XCTAssertEqual(first.committedOffset, 15)
        XCTAssertFalse(first.wasTruncated)

        try append("\"}\n", to: url)
        let second = try reader.read(file: url, fromOffset: first.committedOffset)

        XCTAssertEqual(second.lines.map { String(decoding: $0.data, as: UTF8.self) }, ["{\"type\":\"two\"}"])
        XCTAssertEqual(second.lines.map(\.endOffset), [30])
        XCTAssertEqual(second.committedOffset, 30)
        XCTAssertFalse(second.wasTruncated)
    }

    func testReturnsEveryCompleteLineAndAbsoluteEndOffset() throws {
        let url = try temporaryFile(contents: "a\n\nbb\npartial")

        let batch = try IncrementalJSONLReader(chunkSize: 1).read(file: url, fromOffset: 0)

        XCTAssertEqual(batch.lines.map(\.data), [Data("a".utf8), Data(), Data("bb".utf8)])
        XCTAssertEqual(batch.lines.map(\.endOffset), [2, 3, 6])
        XCTAssertEqual(batch.committedOffset, 6)
        XCTAssertFalse(batch.wasTruncated)
    }

    func testTruncationDoesNotReadFromStartUntilImporterResetsGeneration() throws {
        let url = try temporaryFile(contents: "new\n")

        let truncated = try IncrementalJSONLReader(chunkSize: 2).read(file: url, fromOffset: 20)

        XCTAssertEqual(truncated.lines, [])
        XCTAssertEqual(truncated.committedOffset, 0)
        XCTAssertTrue(truncated.wasTruncated)

        let restarted = try IncrementalJSONLReader(chunkSize: 2).read(file: url, fromOffset: 0)
        XCTAssertEqual(restarted.lines.map(\.data), [Data("new".utf8)])
        XCTAssertEqual(restarted.committedOffset, 4)
        XCTAssertFalse(restarted.wasTruncated)
    }

    func testRejectsInvalidConfigurationAndNegativeOffset() throws {
        let url = try temporaryFile(contents: "line\n")

        XCTAssertThrowsError(try IncrementalJSONLReader(chunkSize: 0).read(file: url, fromOffset: 0))
        XCTAssertThrowsError(try IncrementalJSONLReader(chunkSize: 8).read(file: url, fromOffset: -1))
    }

    func testDiscoveryUsesPathScopedIdentityWhenFileMovesToArchive() throws {
        let root = try temporaryDirectory()
        let session = root.appending(path: "sessions/2026/07/14/rollout.jsonl")
        try write("{}\n", to: session)
        let modificationDate = Date(timeIntervalSince1970: 1_234_567)
        try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: session.path)

        let first = try XCTUnwrap(CodexSourceDiscovery().discover(rootURL: root).rollouts.first)
        let archived = root.appending(path: "archived_sessions/rollout.jsonl")
        try FileManager.default.createDirectory(
            at: archived.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: first.url, to: archived)
        let second = try XCTUnwrap(CodexSourceDiscovery().discover(rootURL: root).rollouts.first)

        XCTAssertNotEqual(first.fileID, second.fileID)
        XCTAssertEqual(first.deviceID, second.deviceID)
        XCTAssertEqual(first.inode, second.inode)
        XCTAssertNotEqual(first.url, second.url)
        XCTAssertFalse(first.isArchived)
        XCTAssertTrue(second.isArchived)
        XCTAssertEqual(second.fileSize, 3)
        XCTAssertEqual(second.modificationTimeMilliseconds, 1_234_567_000)
    }

    func testDiscoveryScansSessionsRecursivelyAndArchiveOnlyDirectly() throws {
        let root = try temporaryDirectory()
        try write("{}\n", to: root.appending(path: "sessions/2026/07/14/included.jsonl"))
        try write("{}\n", to: root.appending(path: "sessions/ignored.txt"))
        try write("{}\n", to: root.appending(path: "archived_sessions/included.jsonl"))
        try write("{}\n", to: root.appending(path: "archived_sessions/nested/excluded.jsonl"))

        let inventory = try CodexSourceDiscovery().discover(rootURL: root)

        XCTAssertEqual(inventory.rollouts.map { $0.url.lastPathComponent }.sorted(), ["included.jsonl", "included.jsonl"])
        XCTAssertEqual(inventory.rollouts.filter(\.isArchived).count, 1)
        XCTAssertEqual(inventory.indexHealth, .missing)
        XCTAssertEqual(inventory.threadIndex, [])
    }

    func testDiscoveryUsesCurrentRootSetWhenBackupHasLaterFileModificationDate() throws {
        let root = try temporaryDirectory()
        let backup = root.appending(path: ".codex-global-state.json.bak")
        let current = root.appending(path: ".codex-global-state.json")
        try write(
            #"{"local-projects":{"project-a":{"name":"Old","rootPaths":["/repo/first"],"updatedAt":1000}}}"#,
            to: backup
        )
        try write(
            #"{"local-projects":{"project-a":{"name":"Current","rootPaths":["/repo/first","/repo/second"],"updatedAt":2000}}}"#,
            to: current
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 10)], ofItemAtPath: backup.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: current.path
        )

        let metadata = CodexWorkspaceMetadataReader().read(rootURL: root)

        XCTAssertEqual(metadata.count, 1)
        XCTAssertEqual(metadata.first?.name, "Current")
        XCTAssertEqual(metadata.first?.rootPaths, ["/repo/first", "/repo/second"])
    }

    func testDiscoveryRecoversArchivedWorkspaceNamesAndPrefersNewestMetadata() throws {
        let root = try temporaryDirectory()
        let historicalState = root.appending(path: "..codex-global-state.json.tmp-older")
        let currentState = root.appending(path: ".codex-global-state.json")
        try write(
            #"{"local-projects":{"archived":{"name":"open-api","rootPaths":["/repo/retail-sales","/repo/guide-performance"]},"active":{"name":"CodexVista-old","rootPaths":["/repo/CodexVista"]}}}"#,
            to: historicalState
        )
        try write(
            #"{"local-projects":{"active":{"name":"CodexVista","rootPaths":["/repo/CodexVista"]}}}"#,
            to: currentState
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)],
            ofItemAtPath: historicalState.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 2)],
            ofItemAtPath: currentState.path
        )

        let metadata = try CodexSourceDiscovery().discover(rootURL: root).workspaceMetadata

        XCTAssertEqual(metadata.map(\.name).sorted(), ["CodexVista", "open-api"])
        XCTAssertEqual(
            metadata.first { $0.name == "open-api" }?.rootPaths,
            ["/repo/retail-sales", "/repo/guide-performance"]
        )
    }

    func testDiscoveryUsesNewestNumericStateDatabaseAndMergesThreadByStandardizedPath() throws {
        let root = try temporaryDirectory()
        let rollout = root.appending(path: "sessions/2026/07/14/rollout.jsonl")
        try write("{}\n", to: rollout)
        try makeThreadDatabase(
            at: root.appending(path: "state_2.sqlite"),
            threadID: "old",
            rolloutPath: rollout.path,
            source: "cli",
            model: nil,
            createdAtMilliseconds: 1_000,
            updatedAtMilliseconds: 2_000,
            archived: false
        )
        try makeThreadDatabase(
            at: root.appending(path: "state_10.sqlite"),
            threadID: "new",
            rolloutPath: rollout.deletingLastPathComponent().appending(path: "./rollout.jsonl").path,
            source: "vscode",
            model: "gpt-test",
            createdAtMilliseconds: 3_000,
            updatedAtMilliseconds: 4_000,
            archived: true
        )

        let inventory = try CodexSourceDiscovery().discover(rootURL: root)

        XCTAssertEqual(inventory.indexHealth, .available)
        XCTAssertEqual(inventory.threadIndex.map(\.threadID), ["new"])
        let thread = try XCTUnwrap(inventory.rollouts.first?.thread)
        XCTAssertEqual(thread.threadID, "new")
        XCTAssertEqual(thread.sourceRaw, "vscode")
        XCTAssertEqual(thread.model, "gpt-test")
        XCTAssertEqual(thread.createdAtMilliseconds, 3_000)
        XCTAssertEqual(thread.updatedAtMilliseconds, 4_000)
        XCTAssertTrue(thread.archived)
    }

    func testDiscoveryIgnoresNewerStateDirectoryAndUsesNewestRegularDatabaseFile() throws {
        let root = try temporaryDirectory()
        let rollout = root.appending(path: "sessions/rollout.jsonl")
        try write("{}\n", to: rollout)
        try makeThreadDatabase(
            at: root.appending(path: "state_10.sqlite"),
            threadID: "regular-file",
            rolloutPath: rollout.path,
            source: "cli",
            model: nil,
            createdAtMilliseconds: 1_000,
            updatedAtMilliseconds: 2_000,
            archived: false
        )
        try FileManager.default.createDirectory(
            at: root.appending(path: "state_999.sqlite", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )

        let inventory = try CodexSourceDiscovery().discover(rootURL: root)

        XCTAssertEqual(inventory.indexHealth, .available)
        XCTAssertEqual(inventory.threadIndex.map(\.threadID), ["regular-file"])
        XCTAssertEqual(inventory.rollouts.first?.thread?.threadID, "regular-file")
    }

    func testIndexReaderAcceptsMillisecondOnlyTimestampColumns() throws {
        let root = try temporaryDirectory()
        let databaseURL = root.appending(path: "state_4.sqlite")
        let database = try SQLiteDatabase(url: databaseURL)
        try database.execute(sql: """
            CREATE TABLE threads(
              id TEXT NOT NULL,
              rollout_path TEXT NOT NULL,
              source TEXT NOT NULL,
              model TEXT,
              created_at_ms INTEGER NOT NULL,
              updated_at_ms INTEGER NOT NULL,
              archived INTEGER NOT NULL
            )
            """)
        try database.execute(
            sql: "INSERT INTO threads VALUES (?, ?, ?, ?, ?, ?, ?)",
            bindings: [.text("thread"), .text("/tmp/anonymous.jsonl"), .text("vscode"),
                       .text("gpt-test"), .integer(1_234), .integer(5_678), .integer(1)]
        )

        let records = try CodexThreadIndexReader().read(databaseURL: databaseURL)

        XCTAssertEqual(records, [
            ThreadIndexRecord(
                threadID: "thread",
                rolloutPath: "/tmp/anonymous.jsonl",
                sourceRaw: "vscode",
                model: "gpt-test",
                createdAtMilliseconds: 1_234,
                updatedAtMilliseconds: 5_678,
                archived: true,
                childEdgeStatus: nil
            )
        ])
    }

    func testIndexReaderProvidesSanitizedDisplayTitlesWithoutRequiringThem() throws {
        let root = try temporaryDirectory()
        let databaseURL = root.appending(path: "state_4.sqlite")
        let database = try SQLiteDatabase(url: databaseURL)
        try database.execute(sql: """
            CREATE TABLE threads(
              id TEXT NOT NULL,
              rollout_path TEXT NOT NULL,
              source TEXT NOT NULL,
              model TEXT,
              name TEXT,
              title TEXT,
              created_at_ms INTEGER NOT NULL,
              updated_at_ms INTEGER NOT NULL,
              archived INTEGER NOT NULL
            )
            """)
        try database.execute(
            sql: """
                INSERT INTO threads(
                  id, rollout_path, source, model, name, title,
                  created_at_ms, updated_at_ms, archived
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?), (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            bindings: [
                .text("renamed"), .text("/tmp/renamed.jsonl"), .text("vscode"), .null,
                .text("  手动\n名称  "), .text("旧标题"), .integer(1_000), .integer(2_000), .integer(0),
                .text("titled"), .text("/tmp/titled.jsonl"), .text("cli"), .null,
                .text("   "), .text("  修复\n项目用量  "), .integer(3_000), .integer(4_000), .integer(0)
            ]
        )
        try database.execute(
            sql: """
                INSERT INTO threads(
                  id, rollout_path, source, model, name, title,
                  created_at_ms, updated_at_ms, archived
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?), (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            bindings: [
                .text("guardian"), .text("/tmp/guardian.jsonl"),
                .text(#"{"subagent":{"other":"guardian"}}"#), .null, .null,
                .text("The following is the Codex desktop context"),
                .integer(5_000), .integer(6_000), .integer(0),
                .text("subagent"), .text("/tmp/subagent.jsonl"),
                .text(#"{"subagent":{"thread_spawn":{"agent_nickname":"Ada","agent_role":null}}}"#), .null, .null,
                .text("The following is the Codex task context"),
                .integer(7_000), .integer(8_000), .integer(0)
            ]
        )
        try database.execute(
            sql: """
                INSERT INTO threads(
                  id, rollout_path, source, model, name, title,
                  created_at_ms, updated_at_ms, archived
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            bindings: [
                .text("plain-template"), .text("/tmp/plain.jsonl"), .text("cli"), .null, .null,
                .text("The following is the Codex task context"),
                .integer(9_000), .integer(10_000), .integer(0)
            ]
        )

        let records = try CodexThreadIndexReader().read(databaseURL: databaseURL)
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.threadID, $0) })

        XCTAssertEqual(recordsByID["renamed"]?.displayTitle, "手动 名称")
        XCTAssertEqual(recordsByID["titled"]?.displayTitle, "修复 项目用量")
        XCTAssertEqual(recordsByID["guardian"]?.displayTitle, "命令权限检查")
        XCTAssertEqual(recordsByID["subagent"]?.displayTitle, "Codex 子任务 · Ada")
        XCTAssertNil(recordsByID["plain-template"]?.displayTitle)
        XCTAssertEqual(
            CodexSourceDiscovery().threadDisplayTitles(rootURL: root),
            [
                "renamed": "手动 名称",
                "titled": "修复 项目用量",
                "guardian": "命令权限检查",
                "subagent": "Codex 子任务 · Ada"
            ]
        )
    }

    func testGuardianIdentitySurvivesIndexTitleBackfill() throws {
        let root = try temporaryDirectory()
        let databaseURL = root.appending(path: "state_5.sqlite")
        try makeThreadDatabase(
            at: databaseURL,
            threadID: "guardian",
            rolloutPath: "/tmp/guardian.jsonl",
            source: #"{"subagent":{"other":"guardian"}}"#,
            model: nil,
            createdAtMilliseconds: 1_000,
            updatedAtMilliseconds: 2_000,
            archived: false
        )
        let database = try SQLiteDatabase(url: databaseURL)
        try database.execute(sql: "ALTER TABLE threads ADD COLUMN name TEXT")
        try database.execute(sql: "ALTER TABLE threads ADD COLUMN title TEXT")
        try database.execute(sql: "ALTER TABLE threads ADD COLUMN agent_nickname TEXT")

        let discovery = CodexSourceDiscovery()
        XCTAssertEqual(discovery.threadDisplayTitles(rootURL: root)["guardian"], "命令权限检查")

        // New Codex indexes backfill names on existing internal review threads.
        try database.execute(sql: """
            UPDATE threads SET name = 'Guardian review', title = 'Guardian review',
                               agent_nickname = 'Reviewer'
            """)
        let title = discovery.threadDisplayTitles(rootURL: root)["guardian"]
        XCTAssertEqual(title, "命令权限检查")
        XCTAssertFalse(ProjectConversationUsage.isIncludedInTaskMetrics(displayTitle: title))

        try database.execute(sql: "UPDATE threads SET name = NULL")
        XCTAssertEqual(discovery.threadDisplayTitles(rootURL: root)["guardian"], "命令权限检查")

        // A user task with the same title is not an internal permission check.
        try database.execute(sql: "UPDATE threads SET source = 'vscode', name = 'Guardian review'")
        let userTitle = discovery.threadDisplayTitles(rootURL: root)["guardian"]
        XCTAssertEqual(userTitle, "Guardian review")
        XCTAssertTrue(ProjectConversationUsage.isIncludedInTaskMetrics(displayTitle: userTitle))

        try database.execute(
            sql: "UPDATE threads SET source = ?",
            bindings: [.text(#"{"subagent":{"thread_spawn":{"agent_nickname":"guardian"}}}"#)]
        )
        XCTAssertEqual(discovery.threadDisplayTitles(rootURL: root)["guardian"], "Guardian review")
    }

    func testIndexReaderFallsBackFromLegacySecondsAndAllowsMissingOptionalTablesAndColumns() throws {
        let root = try temporaryDirectory()
        let databaseURL = root.appending(path: "state_4.sqlite")
        let database = try SQLiteDatabase(url: databaseURL)
        try database.execute(sql: """
            CREATE TABLE threads(
              id TEXT NOT NULL,
              rollout_path TEXT NOT NULL,
              source TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              archived INTEGER NOT NULL
            )
            """)
        try database.execute(
            sql: "INSERT INTO threads VALUES (?, ?, ?, ?, ?, ?)",
            bindings: [.text("thread"), .text("/tmp/anonymous.jsonl"), .text("cli"),
                       .integer(12), .integer(34), .integer(0)]
        )

        let records = try CodexThreadIndexReader().read(databaseURL: databaseURL)

        XCTAssertEqual(records, [
            ThreadIndexRecord(
                threadID: "thread",
                rolloutPath: "/tmp/anonymous.jsonl",
                sourceRaw: "cli",
                model: nil,
                createdAtMilliseconds: 12_000,
                updatedAtMilliseconds: 34_000,
                archived: false,
                childEdgeStatus: nil
            )
        ])
    }

    func testIndexReaderUsesExplicitChildEdgeStatusAndDeduplicatesMatchingRows() throws {
        let root = try temporaryDirectory()
        let databaseURL = root.appending(path: "state_4.sqlite")
        try makeThreadDatabase(
            at: databaseURL,
            threadID: "child",
            rolloutPath: "/tmp/anonymous.jsonl",
            source: "cli",
            model: nil,
            createdAtMilliseconds: 1_000,
            updatedAtMilliseconds: 2_000,
            archived: false
        )
        let database = try SQLiteDatabase(url: databaseURL)
        try database.execute(sql: "CREATE TABLE thread_spawn_edges(child_thread_id TEXT, status TEXT)")
        try database.execute(
            sql: "INSERT INTO thread_spawn_edges VALUES (?, ?), (?, ?)",
            bindings: [.text("child"), .text("open"), .text("child"), .text("open")]
        )

        let records = try CodexThreadIndexReader().read(databaseURL: databaseURL)

        XCTAssertEqual(records.first?.childEdgeStatus, "open")
    }

    func testIndexReaderProvidesParentThreadIDFromSpawnEdge() throws {
        let root = try temporaryDirectory()
        let databaseURL = root.appending(path: "state_4.sqlite")
        try makeThreadDatabase(
            at: databaseURL,
            threadID: "child",
            rolloutPath: "/tmp/child.jsonl",
            source: "cli",
            model: nil,
            createdAtMilliseconds: 1_000,
            updatedAtMilliseconds: 2_000,
            archived: false
        )
        let database = try SQLiteDatabase(url: databaseURL)
        try database.execute(sql: """
            CREATE TABLE thread_spawn_edges(
              parent_thread_id TEXT, child_thread_id TEXT, status TEXT
            )
            """)
        try database.execute(
            sql: "INSERT INTO thread_spawn_edges VALUES (?, ?, ?)",
            bindings: [.text("parent"), .text("child"), .text("completed")]
        )

        let record = try XCTUnwrap(CodexThreadIndexReader().read(databaseURL: databaseURL).first)
        let metadata = CodexSourceDiscovery().threadDashboardMetadata(rootURL: root)

        XCTAssertEqual(record.parentThreadID, "parent")
        XCTAssertEqual(record.childEdgeStatus, "completed")
        XCTAssertEqual(metadata.parentThreadIDsByChildThreadID, ["child": "parent"])
        XCTAssertEqual(
            metadata.childThreadRelationsByChildThreadID["child"],
            CodexChildThreadRelation(
                parentThreadID: "parent",
                childCreatedAtMilliseconds: 1_000
            )
        )
    }

    func testDashboardMetadataReadsParentRelationFromSafeSessionFields() throws {
        let root = try temporaryDirectory()
        let rollout = root.appending(path: "sessions/child.jsonl")
        try write(
            """
            {"timestamp":"2026-08-21T08:00:00.125Z","type":"session_meta","payload":{"id":"child","parent_thread_id":"parent","source":{"subagent":{"other":"review"}}}}
            """ + "\n",
            to: rollout
        )
        try makeThreadDatabase(
            at: root.appending(path: "state_5.sqlite"),
            threadID: "child",
            rolloutPath: rollout.path,
            source: #"{"subagent":{"other":"review"}}"#,
            model: nil,
            createdAtMilliseconds: 1_000,
            updatedAtMilliseconds: 2_000,
            archived: false
        )

        let metadata = CodexSourceDiscovery().threadDashboardMetadata(rootURL: root)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expectedCreatedAt = Int64(
            (try XCTUnwrap(formatter.date(from: "2026-08-21T08:00:00.125Z")))
                .timeIntervalSince1970 * 1_000
        )

        XCTAssertEqual(metadata.parentThreadIDsByChildThreadID, ["child": "parent"])
        XCTAssertEqual(
            metadata.childThreadRelationsByChildThreadID["child"]?.childCreatedAtMilliseconds,
            expectedCreatedAt
        )
    }

    func testConflictingChildStatusesDegradeDiscoveryWithoutBlockingRollouts() throws {
        let root = try temporaryDirectory()
        let rollout = root.appending(path: "sessions/rollout.jsonl")
        try write("{}\n", to: rollout)
        let databaseURL = root.appending(path: "state_4.sqlite")
        try makeThreadDatabase(
            at: databaseURL,
            threadID: "child",
            rolloutPath: rollout.path,
            source: "cli",
            model: nil,
            createdAtMilliseconds: 1_000,
            updatedAtMilliseconds: 2_000,
            archived: false
        )
        let database = try SQLiteDatabase(url: databaseURL)
        try database.execute(sql: "CREATE TABLE thread_spawn_edges(child_thread_id TEXT, status TEXT)")
        try database.execute(
            sql: "INSERT INTO thread_spawn_edges VALUES (?, ?), (?, ?)",
            bindings: [.text("child"), .text("open"), .text("child"), .text("closed")]
        )

        let inventory = try CodexSourceDiscovery().discover(rootURL: root)

        XCTAssertEqual(inventory.rollouts.count, 1)
        XCTAssertNil(inventory.rollouts.first?.thread)
        XCTAssertEqual(inventory.threadIndex, [])
        XCTAssertEqual(inventory.indexHealth, .degraded("conflicting child edge statuses"))
    }

    func testIndexReaderOpensReadOnlyDatabaseAndRejectsLegacyTimestampOverflow() throws {
        let root = try temporaryDirectory()
        let readOnlyURL = root.appending(path: "state_1.sqlite")
        try makeThreadDatabase(
            at: readOnlyURL,
            threadID: "thread",
            rolloutPath: "/tmp/anonymous.jsonl",
            source: "cli",
            model: nil,
            createdAtMilliseconds: 1_000,
            updatedAtMilliseconds: 2_000,
            archived: false
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: readOnlyURL.path)

        XCTAssertEqual(try CodexThreadIndexReader().read(databaseURL: readOnlyURL).map(\.threadID), ["thread"])

        let overflowURL = root.appending(path: "state_2.sqlite")
        let overflowDatabase = try SQLiteDatabase(url: overflowURL)
        try overflowDatabase.execute(sql: """
            CREATE TABLE threads(
              id TEXT NOT NULL,
              rollout_path TEXT NOT NULL,
              source TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              archived INTEGER NOT NULL
            )
            """)
        try overflowDatabase.execute(
            sql: "INSERT INTO threads VALUES (?, ?, ?, ?, ?, ?)",
            bindings: [.text("thread"), .text("/tmp/anonymous.jsonl"), .text("cli"),
                       .integer(Int64.max), .integer(1), .integer(0)]
        )

        XCTAssertThrowsError(try CodexThreadIndexReader().read(databaseURL: overflowURL)) { error in
            XCTAssertEqual(error as? CodexThreadIndexError, .timestampOverflow)
        }
    }

    func testMalformedNewestIndexIsDegradedButFilesystemRolloutsRemainAvailable() throws {
        let root = try temporaryDirectory()
        try write("{}\n", to: root.appending(path: "sessions/rollout.jsonl"))
        let malformed = try SQLiteDatabase(url: root.appending(path: "state_99.sqlite"))
        try malformed.execute(sql: "CREATE TABLE unrelated(value TEXT)")

        let inventory = try CodexSourceDiscovery().discover(rootURL: root)

        XCTAssertEqual(inventory.rollouts.count, 1)
        XCTAssertEqual(inventory.threadIndex, [])
        guard case let .degraded(detail) = inventory.indexHealth else {
            return XCTFail("Expected degraded index health")
        }
        XCTAssertTrue(detail.contains("threads"))
        XCTAssertFalse(detail.contains(root.path))
    }
}

private extension IncrementalJSONLReaderTests {
    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "CodexVistaTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func temporaryFile(contents: String) throws -> URL {
        let directory = try temporaryDirectory()
        let url = directory.appending(path: UUID().uuidString)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    func append(_ contents: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(contents.utf8))
    }

    func makeThreadDatabase(
        at url: URL,
        threadID: String,
        rolloutPath: String,
        source: String,
        model: String?,
        createdAtMilliseconds: Int64,
        updatedAtMilliseconds: Int64,
        archived: Bool
    ) throws {
        let database = try SQLiteDatabase(url: url)
        try database.execute(sql: """
            CREATE TABLE threads(
              id TEXT NOT NULL,
              rollout_path TEXT NOT NULL,
              source TEXT NOT NULL,
              model TEXT,
              created_at_ms INTEGER NOT NULL,
              updated_at_ms INTEGER NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              archived INTEGER NOT NULL
            )
            """)
        try database.execute(
            sql: """
            INSERT INTO threads(
              id, rollout_path, source, model, created_at_ms, updated_at_ms,
              created_at, updated_at, archived
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(threadID), .text(rolloutPath), .text(source), model.map(SQLiteValue.text) ?? .null,
                .integer(createdAtMilliseconds), .integer(updatedAtMilliseconds),
                .integer(createdAtMilliseconds / 1_000), .integer(updatedAtMilliseconds / 1_000),
                .integer(archived ? 1 : 0)
            ]
        )
    }
}
