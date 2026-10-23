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
        XCTAssertEqual(event.name, "命令执行（工具名未记录）")
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
                                    "item": ["id": "spawn", "type": "CollabAgentToolCall", "tool": "spawn_agent", "receiver_thread_ids": ["child"], "model": "requested-model", "reasoning_effort": "high"]], offset: 200),
            try line("event_msg", ["type": "task_complete", "turn_id": "turn-a", "time_to_first_token_ms": 250], offset: 1_000)
        ].joined()
        let child = [
            try line("session_meta", ["id": "child", "source": ["subagent": ["thread_spawn": ["agent_nickname": "Ada", "agent_role": "reviewer"]]], "instructions": ["private": true]]),
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
        let group = try XCTUnwrap(trace.nodes.first { $0.id == "agent:child" })
        XCTAssertEqual(group.name, "子代理 · Ada")
        XCTAssertEqual(group.agent?.role, "reviewer")
        XCTAssertEqual(group.model, "model-child")
        XCTAssertEqual(group.reasoningEffort, .low)
        XCTAssertFalse(String(describing: trace).contains("private"))
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

    func testExecutionMetadataAliasesUnknownValuesAndProcessIsolation() throws {
        var slice = ReplyTraceSlice(threadID: "main", turnID: "turn-a")
        for (index, source) in ["unified_exec_startup", "unifiedExecInteraction", "future-source"].enumerated() {
            slice.consume(try decode("event_msg", ["type": "item_completed", "turn_id": "turn-a",
                "item": ["type": "CommandExecution", "id": "cmd-\(index)", "source": source,
                         "process_id": "session-7", "plugin_id": "example-plugin", "command": ["private": true]]], offset: Int64(index)))
        }
        let nodes = slice.resolvedNodes(parentID: "root")
        XCTAssertEqual(nodes.map { $0.tool?.source }, [.unifiedExecStartup, .unifiedExecInteraction, nil])
        XCTAssertEqual(nodes.map(\.name), ["exec_command", "write_stdin", "命令执行（工具名未记录）"])
        XCTAssertEqual(nodes.first?.tool?.pluginID, "example-plugin")
        let otherThread = ReplyTraceNode(id: "other", threadID: "other", turnID: "turn-a", kind: .tool,
            name: "命令执行", status: .completed, startedAt: base, timing: .point,
            tool: .init(processID: "session-7"))
        let trace = ReplyTrace(nodes: nodes + [otherThread], notices: [])
        XCTAssertEqual(trace.relatedExecutions(to: nodes[0]).map(\.id), [nodes[1].id, nodes[2].id])
        XCTAssertFalse(String(describing: nodes).contains("private"))
        let invalid = try decode("event_msg", ["type": "item_completed", "item": ["type": "commandExecution",
            "id": "bad", "source": ["private": true], "processId": "/private/path", "pluginId": "../private"]])
        XCTAssertNil(invalid.toolMetadata?.source)
        XCTAssertNil(invalid.toolMetadata?.processID)
        XCTAssertNil(invalid.toolMetadata?.pluginID)
    }

    func testCommandNamesPreserveExactCallsWithoutUsingWrapperOrOtherTurnNames() throws {
        var slice = ReplyTraceSlice(threadID: "main", turnID: nil)
        slice.consume(try decode("turn_context", ["turn_id": "turn-a"]))
        for (id, name) in [("shell-call", "shell_command"), ("startup", "exec_command"), ("wrapper", "exec")] {
            slice.consume(try decode("response_item", ["type": "function_call", "call_id": id,
                "namespace": "functions", "name": name, "arguments": ["private": true]]))
        }
        for (id, source) in [("shell-call", "agent"), ("startup", "unified_exec_startup"),
                             ("interaction", "unified_exec_interaction"), ("wrapper", "unified_exec_startup"),
                             ("user", "user_shell"), ("unknown", "future-source")] {
            slice.consume(try decode("event_msg", ["type": "item_completed", "turn_id": "turn-a",
                "started_at_ms": base, "completed_at_ms": base + 100,
                "item": ["id": id, "type": "CommandExecution", "source": source,
                         "command": ["private": true], "aggregated_output": ["private": true]]]))
        }
        // Calls can arrive after item metadata. Matching never depends on adjacency or time.
        slice.consume(try decode("response_item", ["type": "function_call", "call_id": "interaction",
            "namespace": "functions", "name": "write_stdin"]))
        slice.consume(try decode("turn_context", ["turn_id": "turn-b"]))
        slice.consume(try decode("response_item", ["type": "function_call", "call_id": "unknown", "name": "shell"]))
        slice.consume(try decode("event_msg", ["type": "item_completed", "turn_id": "turn-b",
            "item": ["id": "other", "type": "CommandExecution", "source": "agent"]]))
        let nodes = slice.resolvedNodes(parentID: "root")
        let names = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.name) })
        XCTAssertEqual(names["item:main:turn-a:shell-call"], "functions.shell_command")
        XCTAssertEqual(names["item:main:turn-a:startup"], "functions.exec_command")
        XCTAssertEqual(names["item:main:turn-a:interaction"], "functions.write_stdin")
        XCTAssertEqual(names["item:main:turn-a:wrapper"], "exec_command")
        XCTAssertEqual(names["item:main:turn-a:user"], "用户 Shell")
        XCTAssertEqual(names["item:main:turn-a:unknown"], "命令执行（工具名未记录）")
        XCTAssertEqual(names["item:main:turn-b:other"], "命令执行（工具名未记录）")
        XCTAssertEqual(nodes.count, 7)
        XCTAssertTrue(nodes.filter { $0.turnID == "turn-a" }.allSatisfy { $0.duration == 100 && $0.timing == .recorded })
        XCTAssertFalse(String(describing: nodes).contains("private"))
    }

    func testReadOnlyHintDistinguishesFalseMissingAndMalformed() throws {
        for (value, expected) in [(true as Any, true as Bool?), (false as Any, false as Bool?),
                                   ("true" as Any, nil), (NSNull() as Any, nil)] {
            let event = try decode("event_msg", ["type": "item_completed", "item": ["type": "McpToolCall", "id": "mcp",
                "readOnlyHint": value, "pluginId": "example-plugin", "result": ["private": true]]])
            XCTAssertEqual(event.toolMetadata?.readOnlyHint, expected)
            XCTAssertEqual(event.toolMetadata?.pluginID, "example-plugin")
            XCTAssertFalse(String(describing: event).contains("private"))
        }
        XCTAssertNil(try decode("event_msg", ["type": "item_completed", "item": ["type": "McpToolCall", "id": "mcp"]]).toolMetadata?.readOnlyHint)
    }

    func testAgentActionsKeepRequestedConfigurationSeparateAndIgnoreMessages() throws {
        var slice = ReplyTraceSlice(threadID: "main", turnID: "turn-a")
        slice.consume(try decode("turn_context", ["turn_id": "turn-a", "model": "caller-model", "effort": "high"]))
        slice.consume(try decode("event_msg", ["type": "item_completed", "item": [
            "type": "collabAgentToolCall", "id": "spawn", "tool": "spawnAgent", "receiverThreadIds": ["child"],
            "model": "requested-model", "reasoningEffort": "low", "prompt": ["private": true],
            "agentsStates": ["child": ["status": "pendingInit", "message": ["private": true]],
                             "another": ["status": "future-private-value", "message": "private"]]
        ]]))
        let node = try XCTUnwrap(slice.resolvedNodes(parentID: "root").first)
        XCTAssertEqual(node.model, "caller-model")
        XCTAssertEqual(node.reasoningEffort, .high)
        XCTAssertEqual(node.agent?.model, "requested-model")
        XCTAssertEqual(node.agent?.reasoningEffort, .low)
        XCTAssertEqual(node.agent?.action, .spawnAgent)
        XCTAssertEqual(node.agent?.configurationIsRequested, true)
        XCTAssertEqual(node.agent?.targets, [.init(threadID: "another", status: nil), .init(threadID: "child", status: .pendingInit)])
        XCTAssertFalse(String(describing: node).contains("private"))
        let activity = try decode("event_msg", ["type": "item_completed", "item": [
            "type": "SubAgentActivity", "id": "activity", "agent_thread_id": "child", "kind": "interacted",
            "model": "resolved-model", "reasoning_effort": "medium"]])
        XCTAssertEqual(activity.agent?.action, .interacted)
        XCTAssertEqual(activity.agent?.configurationIsRequested, false)
        XCTAssertEqual(activity.agent?.model, "resolved-model")
        XCTAssertEqual(activity.childThreadIDs, ["child"])
    }

    func testContextCapacityAndWindowNumberStayWithSelectedReply() throws {
        var slice = ReplyTraceSlice(threadID: "main", turnID: "turn-a")
        slice.consume(try decode("turn_context", ["turn_id": "turn-a"]))
        slice.consume(try decode("event_msg", ["type": "token_count", "info": [
            "model_context_window": 200_000, "total_token_usage": ["private": true]]]))
        slice.consume(try decode("event_msg", ["type": "item_completed", "item": ["type": "Reasoning", "id": "reasoning"]]))
        slice.consume(try decode("compacted", ["window_id": "w-2", "window_number": 2, "replacement_history": ["private": true]]))
        slice.consume(try decode("turn_context", ["turn_id": "turn-b"]))
        slice.consume(try decode("event_msg", ["type": "token_count", "info": ["model_context_window": 900_000]]))
        slice.consume(try decode("compacted", ["window_id": "w-3", "window_number": 3]))
        XCTAssertEqual(slice.modelContextWindow, 200_000)
        XCTAssertEqual(slice.contextWindowNumber, 2)
        XCTAssertTrue(slice.resolvedNodes(parentID: "root").allSatisfy { $0.modelContextWindow == 200_000 })
        XCTAssertFalse(String(describing: slice.resolvedNodes(parentID: "root")).contains("private"))
        for invalid in [-1 as Any, 0 as Any, "100" as Any, Int.max as Any] {
            XCTAssertNil(try decode("event_msg", ["type": "token_count", "info": ["model_context_window": invalid]]).modelContextWindow)
        }
        XCTAssertNil(try decode("compacted", ["window_number": -1]).contextWindowNumber)
        XCTAssertEqual(try decode("compacted", ["window_number": 0]).contextWindowNumber, 0)
    }

    func testCompactionMarkersDeduplicateAndFallBackPerTurnWithoutInventingTiming() throws {
        var slice = ReplyTraceSlice(threadID: "main", turnID: nil)
        slice.consume(try decode("turn_context", ["turn_id": "turn-a"]))
        let marker = try decode("compacted", ["window_id": "w-1", "window_number": 1], offset: 300)
        slice.consume(marker)
        slice.consume(marker)
        let item = try decode("event_msg", ["type": "item_completed", "started_at_ms": base + 100, "completed_at_ms": base + 300,
            "item": ["type": "ContextCompaction", "id": "compact"]], offset: 300)
        slice.consume(item)
        slice.consume(item)
        slice.consume(try decode("turn_context", ["turn_id": "turn-b"]))
        slice.consume(try decode("compacted", ["window_id": "w-2", "window_number": 2], offset: 400))
        let trace = ReplyTrace(nodes: slice.resolvedNodes(parentID: "root"), notices: [])
        XCTAssertEqual(trace.compactions.count, 2)
        XCTAssertEqual(trace.compactions.map(\.timing), [.recorded, .point])
        XCTAssertNil(trace.compactions.first?.contextWindowNumber)
        XCTAssertEqual(trace.compactions.last?.contextWindowNumber, 2)
        XCTAssertEqual(trace.recordedCompactionDuration, 200)
    }

    func testCompactionDurationUnionsParallelIntervalsAndExcludesIncompleteRecords() {
        var first = traceNode("first", kind: .compaction, duration: 200)
        var second = traceNode("second", kind: .compaction, duration: 300)
        second.startedAt += 100
        let third = traceNode("point", kind: .compaction, duration: nil, timing: .point)
        var running = traceNode("running", kind: .compaction, duration: 5_000)
        running.status = .running
        XCTAssertEqual(ReplyTrace(nodes: [first, second, third, running], notices: []).recordedCompactionDuration, 300)
        first.status = .failed
        XCTAssertNil(ReplyTrace(nodes: [first, third, running], notices: []).recordedCompactionDuration)
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
