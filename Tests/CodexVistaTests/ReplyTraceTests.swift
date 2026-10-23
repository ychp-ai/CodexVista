import Foundation
import XCTest
@testable import CodexVista

final class ReplyTraceTests: XCTestCase {
    private let base: Int64 = 1_760_000_000_000

    func testWhitelistIgnoresContentAndExtractsFailedCommandTiming() throws {
        let event = try decode("event_msg", [
            "type": "item_completed", "thread_id": "main", "turn_id": "turn-a",
            "started_at_ms": base, "completed_at_ms": base + 200,
            "item": ["type": "CommandExecution", "id": "cmd-1", "status": "completed", "exit_code": 2,
                     "command": ["private": true], "aggregated_output": ["private": true], "cwd": ["private": true]]
        ])
        XCTAssertEqual(event.kind, .tool)
        XCTAssertEqual(event.name, "命令执行")
        XCTAssertEqual(event.status, .failed)
        XCTAssertEqual(event.end! - event.start!, 200)
        XCTAssertFalse(String(describing: event).contains("private"))
    }

    func testSeparateTurnsDeduplicateItemsAndUsageWithoutCountingWrappers() throws {
        var slice = ReplyTraceSlice(threadID: "main", turnID: "turn-a")
        slice.consume(try decode("turn_context", ["turn_id": "turn-a", "model": "model-a"]))
        slice.consume(try decode("response_item", ["type": "function_call", "call_id": "wrapper", "name": "exec", "arguments": ["private": true]]))
        let item = try decode("event_msg", [
            "type": "item_completed", "turn_id": "turn-a", "started_at_ms": base, "completed_at_ms": base + 500,
            "item": ["id": "cmd-1", "type": "CommandExecution", "status": "completed"]
        ])
        slice.consume(item)
        slice.consume(item)
        let usage = try decode("token_usage_record", [
            "thread_id": "main", "turn_id": "turn-a", "response_id": "response-a", "usage": tokenPayload,
            "turn_token_usage": ["total_tokens": 999_999]
        ])
        slice.consume(usage)
        slice.consume(usage)
        slice.consume(try decode("event_msg", ["type": "item_completed", "turn_id": "turn-b", "item": ["id": "other", "type": "Reasoning"]]))
        let nodes = slice.resolvedNodes(parentID: "root")
        XCTAssertEqual(nodes.count, 2)
        XCTAssertEqual(nodes.filter { $0.kind == .tool }.count, 1)
        XCTAssertEqual(nodes.first { $0.kind == .usage }?.tokens?.totalTokens, 150)
        XCTAssertEqual(nodes.first { $0.kind == .usage }?.tokens?.uncachedInput, 60)
        XCTAssertEqual(nodes.first { $0.kind == .usage }?.tokens?.visibleOutput, 30)
        XCTAssertTrue(nodes.allSatisfy { $0.parentID == "root" && $0.model == "model-a" })
        XCTAssertEqual(ReplyTrace(nodes: nodes, notices: []).cacheHitRate, 0.4)
    }

    func testLegacyPairsByCallIDAndDoesNotInferSuccessFromOutput() throws {
        var slice = ReplyTraceSlice(threadID: "main", turnID: "turn-a")
        slice.consume(try decode("event_msg", ["type": "task_started", "turn_id": "turn-a"]))
        slice.consume(try decode("response_item", ["type": "function_call", "call_id": "a", "name": "one"]))
        slice.consume(try decode("response_item", ["type": "custom_tool_call", "call_id": "b", "name": "two"], offset: 10))
        slice.consume(try decode("response_item", ["type": "custom_tool_call_output", "call_id": "b", "output": ["private": true]], offset: 100))
        slice.consume(try decode("response_item", ["type": "function_call_output", "call_id": "a", "output": "private"], offset: 300))
        slice.consume(try decode("response_item", ["type": "function_call", "call_id": "c", "name": "three"], offset: 400))
        let nodes = slice.resolvedNodes(parentID: "root")
        XCTAssertEqual(nodes.map(\.duration), [300, 90, nil])
        XCTAssertEqual(nodes.map(\.status), [.unknown, .unknown, .running])
        XCTAssertTrue(nodes.allSatisfy { $0.timing == .estimated })
    }

    func testUnknownItemsBadTimingAndWrongThreadAreSafe() throws {
        var slice = ReplyTraceSlice(threadID: "main", turnID: "turn-a")
        slice.consume(try decode("turn_context", ["turn_id": "turn-a"]))
        slice.consume(try decode("event_msg", ["type": "item_completed", "item": ["id": "future", "type": "FutureType", "content": "private"]]))
        slice.consume(try decode("event_msg", ["type": "item_completed", "thread_id": "other", "item": ["id": "wrong", "type": "Reasoning"]]))
        slice.consume(try decode("event_msg", ["type": "item_completed", "started_at_ms": base + 100, "completed_at_ms": base,
                                               "item": ["id": "bad-clock", "type": "Reasoning", "raw_content": "private"]]))
        let nodes = slice.resolvedNodes(parentID: "root")
        XCTAssertEqual(nodes.count, 1)
        XCTAssertNil(nodes[0].endedAt)
        XCTAssertEqual(nodes[0].timing, .point)
    }

    func testStreamingReaderSkipsOversizedLinesAndDoesNotCommitPartialLine() throws {
        let directory = try temporaryDirectory()
        let url = directory.appending(path: "test.jsonl")
        try Data("a\n123456789\nbb\npartial".utf8).write(to: url)
        var lines: [String] = []
        let incomplete = try ReplyTraceLineReader(maximumLineBytes: 4, maximumFileBytes: 1_000, chunkSize: 3).read(url) {
            lines.append(String(decoding: $0, as: UTF8.self))
        }
        XCTAssertTrue(incomplete)
        XCTAssertEqual(lines, ["a", "bb"])
    }

    func testOnDemandLoadWithoutIndexIncludesOnlyLinkedChildTimeRange() async throws {
        let directory = try temporaryDirectory()
        let sessions = directory.appending(path: "sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let main = [
            try line("turn_context", ["turn_id": "turn-a", "effort": "high"]),
            try line("event_msg", ["type": "task_started", "turn_id": "turn-a"]),
            try line("event_msg", ["type": "item_completed", "turn_id": "turn-a", "started_at_ms": base + 100, "completed_at_ms": base + 200,
                                    "item": ["id": "spawn", "type": "CollabAgentToolCall", "tool": "spawn_agent", "receiver_thread_ids": ["child"]]], offset: 200),
            try line("event_msg", ["type": "task_complete", "turn_id": "turn-a", "time_to_first_token_ms": 250], offset: 1_000)
        ].joined()
        let child = [
            try line("turn_context", ["turn_id": "child-turn", "model": "model-child", "effort": "low"]),
            try line("event_msg", ["type": "item_completed", "started_at_ms": base - 1_000, "completed_at_ms": base - 100,
                                    "item": ["id": "old", "type": "CommandExecution"]], offset: -100),
            try line("event_msg", ["type": "item_completed", "started_at_ms": base + 200, "completed_at_ms": base + 600,
                                    "item": ["id": "new", "type": "CommandExecution"]], offset: 600),
            try line("event_msg", ["type": "item_completed", "started_at_ms": base + 2_000, "completed_at_ms": base + 2_100,
                                    "item": ["id": "later", "type": "CommandExecution"]], offset: 2_100)
        ].joined()
        try Data(main.utf8).write(to: sessions.appending(path: "rollout-main.jsonl"))
        try Data(child.utf8).write(to: sessions.appending(path: "rollout-child.jsonl"))
        let trace = try await ReplyTraceService(rootURL: directory).load(reply: reply())
        XCTAssertEqual(trace.nodes.filter { $0.kind == .subagent }.count, 1)
        XCTAssertEqual(trace.nodes.filter { $0.kind == .tool }.count, 2)
        XCTAssertFalse(trace.nodes.contains { $0.id.hasSuffix(":old") || $0.id.hasSuffix(":later") })
        XCTAssertEqual(trace.nodes.first?.status, .completed)
        XCTAssertEqual(trace.root?.timeToFirstTokenMilliseconds, 250)
        XCTAssertEqual(trace.root?.reasoningEffort, .high)
        XCTAssertEqual(trace.nodes.first { $0.id.hasSuffix(":new") }?.reasoningEffort, .low)
        XCTAssertEqual(trace.nodes.first { $0.kind == .subagent }?.parentID, trace.nodes.first { $0.name == "spawn_agent" }?.id)
        XCTAssertTrue(trace.nodes.allSatisfy { node in
            node.parentID == nil || trace.nodes.contains(where: { $0.id == node.parentID })
        })
    }

    func testMissingRolloutHasDistinctError() async throws {
        let service = ReplyTraceService(rootURL: try temporaryDirectory())
        do {
            _ = try await service.load(reply: reply())
            XCTFail("Expected missing source")
        } catch ReplyTraceError.missingSource { }
    }

    func testDelayedUsageKeepsItsOwnTurnModelAndRejectsOverlappingTokenSplits() throws {
        var slice = ReplyTraceSlice(threadID: "main", turnID: "turn-a")
        slice.consume(try decode("turn_context", ["turn_id": "turn-a", "model": "model-a"]))
        slice.consume(try decode("turn_context", ["turn_id": "turn-b", "model": "model-b"]))
        slice.consume(try decode("token_usage_record", ["turn_id": "turn-a", "response_id": "late", "usage": tokenPayload]))
        var invalidUsage = tokenPayload
        invalidUsage["cached_input_tokens"] = 999
        slice.consume(try decode("token_usage_record", ["turn_id": "turn-a", "response_id": "bad", "usage": invalidUsage]))
        let nodes = slice.resolvedNodes(parentID: "root")
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0].model, "model-a")
    }

    func testOutOfRangeTimestampDoesNotOverflowTimeline() throws {
        let event = try decode("event_msg", [
            "type": "item_completed", "turn_id": "turn-a", "started_at_ms": Int64.min, "completed_at_ms": Int64.max,
            "item": ["type": "Reasoning", "id": "invalid-clock"]
        ])
        XCTAssertNil(event.start)
        XCTAssertNil(event.end)
        var slice = ReplyTraceSlice(threadID: "main", turnID: "turn-a")
        slice.consume(event)
        XCTAssertEqual(slice.resolvedNodes(parentID: "root")[0].startedAt, base)
    }

    func testFirstTokenLatencyAcceptsZeroAndRejectsMissingMalformedOrAbortedValues() throws {
        for value in [0, 350] {
            let event = try decode("event_msg", ["type": "task_complete", "time_to_first_token_ms": value])
            XCTAssertEqual(event.timeToFirstTokenMilliseconds, Int64(value))
        }
        for value in [NSNull(), -1, Int64.max, "350", ["private": true]] as [Any] {
            let event = try decode("event_msg", ["type": "task_complete", "time_to_first_token_ms": value])
            XCTAssertNil(event.timeToFirstTokenMilliseconds)
        }
        XCTAssertNil(try decode("event_msg", ["type": "task_complete"]).timeToFirstTokenMilliseconds)
        XCTAssertNil(try decode("event_msg", ["type": "turn_aborted", "time_to_first_token_ms": 100]).timeToFirstTokenMilliseconds)
    }

    func testReplyMetadataStaysWithItsTurnAndUnknownEffortDoesNotLeak() throws {
        var slice = ReplyTraceSlice(threadID: "main", turnID: "turn-a")
        slice.consume(try decode("turn_context", ["turn_id": "turn-a", "effort": "high"]))
        slice.consume(try decode("turn_context", ["turn_id": "turn-b", "effort": "low"]))
        slice.consume(try decode("event_msg", ["type": "task_complete", "turn_id": "turn-b", "time_to_first_token_ms": 900]))
        slice.consume(try decode("event_msg", ["type": "task_complete", "thread_id": "other", "turn_id": "turn-a", "time_to_first_token_ms": 800]))
        XCTAssertNil(slice.timeToFirstTokenMilliseconds)
        slice.consume(try decode("token_usage_record", ["turn_id": "turn-a", "response_id": "late", "usage": tokenPayload]))
        slice.consume(try decode("event_msg", ["type": "task_complete", "turn_id": "turn-a", "time_to_first_token_ms": 250]))
        XCTAssertEqual(slice.reasoningEffort, .high)
        XCTAssertEqual(slice.timeToFirstTokenMilliseconds, 250)
        XCTAssertEqual(slice.resolvedNodes(parentID: "root").first?.reasoningEffort, .high)
        slice.consume(try decode("turn_context", ["turn_id": "turn-a", "effort": "unknown-private-value"]))
        XCTAssertNil(slice.reasoningEffort)
        slice.consume(try decode("event_msg", ["type": "task_started", "turn_id": "turn-a"]))
        XCTAssertNil(slice.timeToFirstTokenMilliseconds)
    }

    func testMessagePhasesAreWhitelistedAndUnknownPhaseKeepsMessageNode() throws {
        for (phase, title) in [("commentary", "进度说明"), ("partial_answer", "阶段性回答"), ("final_answer", "最终回答"), ("unknown-private-value", "回复阶段")] {
            var slice = ReplyTraceSlice(threadID: "main", turnID: "turn-a")
            slice.consume(try decode("event_msg", [
                "type": "item_completed", "turn_id": "turn-a",
                "item": ["type": "AgentMessage", "id": "message", "phase": phase, "text": ["private": true]]
            ]))
            let node = try XCTUnwrap(slice.resolvedNodes(parentID: "root").first)
            XCTAssertEqual(node.kind, .message)
            XCTAssertEqual(node.name, title)
            XCTAssertEqual(node.messagePhase, ReplyTraceMessagePhase(rawValue: phase))
            XCTAssertFalse(String(describing: node).contains("private"))
        }
        XCTAssertEqual(try decode("event_msg", ["type": "item_completed", "item": ["type": "AgentMessage", "id": "old"]]).name, "回复阶段")
    }

    func testCacheHitRateIsWeightedAcrossUsageNodesAndNeverUsesRootTotals() throws {
        func usage(_ input: Int, _ cached: Int) -> ReplyTraceTokens {
            ReplyTraceTokens(inputTokens: input, cachedInputTokens: cached, outputTokens: 50, reasoningOutputTokens: 20, totalTokens: input + 50)
        }
        var first = traceNode("first", kind: .usage)
        first.tokens = usage(100, 40)
        var child = traceNode("child", kind: .usage)
        child.tokens = usage(900, 810)
        var root = traceNode("root", kind: .reply)
        root.tokens = usage(10_000, 0)
        let trace = ReplyTrace(nodes: [root, first, child], notices: ["部分记录缺失"])
        XCTAssertEqual(try XCTUnwrap(trace.cacheHitRate), 0.85, accuracy: 0.000_001)
        XCTAssertNil(usage(0, 0).cacheHitRate)
        XCTAssertNil(usage(100, 101).cacheHitRate)
        XCTAssertNil(usage(100, -1).cacheHitRate)
        XCTAssertEqual(usage(100, 0).cacheHitRate, 0)
        XCTAssertEqual(usage(100, 100).cacheHitRate, 1)
        XCTAssertNil(ReplyTrace(nodes: [root], notices: []).cacheHitRate)
    }

    func testSlowToolsRankIndividualDurationsAndExcludeIncompleteSpans() {
        var candidates = (1...7).map { traceNode("tool-\($0)", duration: Int64($0) * 100) }
        var estimated = traceNode("legacy", duration: 800, timing: .estimated)
        estimated.status = .unknown
        var failed = traceNode("failed", duration: 900)
        failed.status = .failed
        var running = traceNode("running", duration: 5_000)
        running.status = .running
        candidates += [estimated, failed, running, traceNode("point", duration: 6_000, timing: .point),
                       traceNode("unfinished", duration: nil), traceNode("reply", kind: .reply, duration: 10_000)]
        let trace = ReplyTrace(nodes: candidates, notices: [])
        XCTAssertEqual(trace.slowestTools.map(\.id), ["failed", "legacy", "tool-7", "tool-6", "tool-5"])
        XCTAssertEqual(trace.slowestTools[1].timing, .estimated)
        XCTAssertEqual(ReplyTrace(nodes: [traceNode("b"), traceNode("a")], notices: []).slowestTools.map(\.id), ["a", "b"])
        XCTAssertTrue(ReplyTrace(nodes: [], notices: []).slowestTools.isEmpty)
    }

    private func traceNode(_ id: String, kind: ReplyTraceNodeKind = .tool, duration: Int64? = 100,
                           timing: ReplyTraceTiming = .recorded) -> ReplyTraceNode {
        ReplyTraceNode(id: id, threadID: "anonymous", turnID: "turn-a", kind: kind, name: id,
                       status: .completed, startedAt: base, endedAt: duration.map { base + $0 }, timing: timing)
    }

    private var tokenPayload: [String: Int] {
        ["input_tokens": 100, "cached_input_tokens": 40, "output_tokens": 50, "reasoning_output_tokens": 20, "total_tokens": 150]
    }

    private func decode(_ type: String, _ payload: [String: Any], offset: Int64 = 0) throws -> ReplyTraceEvent {
        try JSONDecoder().decode(ReplyTraceEvent.self, from: Data(line(type, payload, offset: offset).utf8))
    }

    private func line(_ type: String, _ payload: [String: Any], offset: Int64 = 0) throws -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date(timeIntervalSince1970: Double(base + offset) / 1_000))
        let data = try JSONSerialization.data(withJSONObject: ["timestamp": timestamp, "type": type, "payload": payload], options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "ReplyTraceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func reply() -> ProjectReplyUsage {
        ProjectReplyUsage(
            id: "turn-a", status: .completed, modelCalls: [], uncachedInputTokens: 60,
            cachedInputTokens: 40, visibleOutputTokens: 30, reasoningTokens: 20, totalTokens: 150,
            estimatedCostBreakdown: nil, unpricedModelCount: 0, referencePricedModelCount: 0,
            startedAtMilliseconds: base, endedAtMilliseconds: base + 1_000, aiWorktimeMilliseconds: 1_000,
            lastUsageAtMilliseconds: base + 1_000, skillCalls: [], toolCalls: [], traceThreadID: "main"
        )
    }
}
