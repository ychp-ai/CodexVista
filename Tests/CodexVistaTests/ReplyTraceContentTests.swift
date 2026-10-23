import Foundation
import XCTest
@testable import CodexVista

final class ReplyTraceContentTests: XCTestCase {
    func testReasoningMatchesItemIDAndSeparatesSummaryFromBody() throws {
        let content = try read([
            context(), message("user", "需求"),
            item("item_started", "reason-1", "Reasoning"),
            message("user", "节点启动之后的新输入"),
            item("item_completed", "reason-1", "Reasoning", ["raw_content": ["推理原文"], "summary_text": ["摘要"]]),
            item("item_completed", "other", "Reasoning", ["raw_content": ["其他推理"]])
        ])
        XCTAssertTrue(content.found)
        XCTAssertFalse(content.outputIsEstimated)
        XCTAssertEqual(content.input.map(\.text), ["需求"])
        XCTAssertEqual(content.output.map(\.text), ["推理原文", "摘要"])
        XCTAssertEqual(content.output.map(\.title), ["推理正文", "推理摘要"])
    }

    func testModelUsesBoundedResponseSegmentAndExcludesFutureText() throws {
        let content = try read([
            context(), message("user", "问题"), message("assistant", "第一段输出"), usage("r1"),
            response(["type": "function_call_output", "call_id": "tool", "output": "工具结果"]),
            item("item_started", "reason-2", "Reasoning"),
            item("item_completed", "reason-2", "Reasoning", ["summary_text": ["第二段推理"]]),
            message("assistant", "第二段回答"), usage("r2"),
            message("assistant", "不应归入第二次调用"), usage("r3")
        ], node: model("r2"))
        XCTAssertTrue(content.found)
        XCTAssertTrue(content.outputIsEstimated)
        XCTAssertEqual(content.input.map(\.text), ["问题", "第一段输出", "工具结果"])
        XCTAssertEqual(content.output.map(\.text), ["第二段推理", "第二段回答"])
        XCTAssertTrue(content.outputScope.contains("无法确认"))
        XCTAssertTrue(content.inputScope.contains("不能还原完整"))
    }

    func testRepeatedUsageAndLifecycleEventsDoNotDuplicateText() throws {
        let completed = item("item_completed", "reason-1", "Reasoning", ["summary_text": ["合成摘要"]])
        let content = try read([
            context(), message("user", "问题"), usage("r1"),
            completed, completed, usage("r1"), usage("r2")
        ], node: model("r2"))
        XCTAssertEqual(content.output.map(\.text), ["合成摘要"])
    }

    func testDoesNotReadOtherTurnsOrThreadsWithReusedItemIDs() throws {
        var foreign = item("item_completed", "reason-1", "Reasoning", ["summary_text": ["错误线程"]])
        foreign.payload["thread_id"] = "foreign"
        let content = try read([
            context("other-turn"), message("user", "另一轮的问题"),
            item("item_completed", "reason-1", "Reasoning", ["summary_text": ["错误回复"]]),
            context(), message("user", "正确问题"), foreign,
            item("item_completed", "reason-1", "Reasoning", ["summary_text": ["正确回复"]])
        ])
        XCTAssertEqual(content.input.map(\.text), ["正确问题"])
        XCTAssertEqual(content.output.map(\.text), ["正确回复"])
    }

    func testSessionIdentityMismatchReturnsUnavailable() throws {
        let content = try read([
            Record(type: "session_meta", payload: ["id": "foreign"]), context(),
            item("item_completed", "reason-1", "Reasoning", ["summary_text": ["错误文件"]])
        ])
        XCTAssertFalse(content.found)
        XCTAssertTrue(content.output.isEmpty)
    }

    func testMissingExplicitNodeIdentityDoesNotMatchAnonymousItems() throws {
        var node = reasoning()
        node.sourceItemID = nil
        let content = try read([context(), response(["type": "reasoning", "summary": [["type": "summary_text", "text": "摘要"]]])], node: node)
        XCTAssertFalse(content.found)
        XCTAssertTrue(content.output.isEmpty)
    }

    func testRawResponseReasoningAndEncryptedOnlyRecords() throws {
        let plain = try read([context(), response([
            "type": "reasoning", "id": "reason-1",
            "content": [["type": "reasoning_text", "text": "原文"]],
            "summary": [["type": "summary_text", "text": "摘要"]],
            "encrypted_content": "CIPHERTEXT_MUST_NOT_APPEAR"
        ])])
        XCTAssertEqual(plain.output.map(\.text), ["原文", "摘要"])
        let encrypted = try read([context(), response([
            "type": "reasoning", "id": "reason-1", "encrypted_content": "CIPHERTEXT_MUST_NOT_APPEAR"
        ])])
        XCTAssertTrue(encrypted.found)
        XCTAssertEqual(encrypted.output.first?.title, "推理不可用")
        XCTAssertFalse(String(describing: encrypted).contains("CIPHERTEXT_MUST_NOT_APPEAR"))
    }

    func testToolCallArgumentsAndResultsRemainPlainText() throws {
        let script = "printf 'example'"
        let content = try read([
            context(), message("user", "演示输入"),
            response(["type": "function_call_output", "call_id": "earlier", "output": [["type": "input_text", "text": "示例结果"]]]),
            response(["type": "function_call", "call_id": "call", "namespace": "functions", "name": "exec_command", "arguments": script]),
            usage("r1")
        ], node: model("r1"))
        XCTAssertEqual(content.input.map(\.text), ["演示输入", "示例结果"])
        XCTAssertEqual(content.output.first?.title, "工具调用 · functions.exec_command")
        XCTAssertEqual(content.output.first?.text, script)
    }

    func testUnsupportedAttachmentsAreNotDecodedOrFetched() throws {
        let content = try read([
            context(), response(["type": "message", "role": "user", "content": [
                ["type": "input_image", "image_url": "https://example.invalid/private-image"],
                ["type": "input_text", "text": "仅显示文字"]
            ]]), item("item_completed", "reason-1", "Reasoning")
        ])
        XCTAssertEqual(content.input.map(\.text), ["仅显示文字"])
        XCTAssertFalse(String(describing: content).contains("private-image"))
    }

    func testCompactionResetsContextAndPendingOutputs() throws {
        let content = try read([
            context(), message("user", "压缩前"), message("assistant", "旧输出"),
            Record(type: "compacted", payload: ["message": "不得当作完整输入", "replacement_history": []]),
            message("user", "压缩后"), message("assistant", "新输出"), usage("r1")
        ], node: model("r1"))
        XCTAssertTrue(content.crossedCompaction)
        XCTAssertEqual(content.input.map(\.text), ["压缩后"])
        XCTAssertEqual(content.output.map(\.text), ["新输出"])
    }

    func testTextBudgetsPreserveUnicodeAndSignalTruncation() throws {
        var records = [context()]
        for index in 0..<40 { records.append(message("user", "片段\(index)")) }
        records.append(item("item_completed", "reason-1", "Reasoning", ["raw_content": [String(repeating: "🙂", count: 20_000)]]))
        let content = try read(records)
        XCTAssertTrue(content.truncated)
        XCTAssertEqual(content.input.count, 32)
        XCTAssertEqual(content.input.first?.text, "片段8")
        XCTAssertEqual(content.output.first?.text.count, 16_384)
        XCTAssertTrue(content.output.first?.truncated == true)
    }

    func testTotalSectionBudgetEvictsOldestBlocks() throws {
        let records = [context()] + (0..<10).map { message("user", "\($0)" + String(repeating: "字", count: 15_999)) }
            + [item("item_completed", "reason-1", "Reasoning")]
        let content = try read(records)
        XCTAssertTrue(content.truncated)
        XCTAssertLessThanOrEqual(content.input.reduce(0) { $0 + $1.text.count }, 65_536)
        XCTAssertTrue(content.input.last?.text.hasPrefix("9") == true)
    }

    func testResponseAndLifecycleCopiesDeduplicateButDistinctMessagesSurvive() throws {
        let content = try read([
            context(), message("assistant", "相同内容"),
            item("item_completed", "message-1", "AgentMessage", ["content": [["type": "Text", "text": "相同内容"]]]),
            message("assistant", "另一段"), usage("r1")
        ], node: model("r1"))
        XCTAssertEqual(content.output.map(\.text), ["相同内容", "另一段"])
    }

    func testPartialAndMalformedLinesReportIncompleteWithoutSavingSource() throws {
        let url = try file([context(), item("item_completed", "reason-1", "Reasoning", ["summary_text": ["有效内容"]])])
        let original = try Data(contentsOf: url) + Data("not-json\n{\"partial\":".utf8)
        try original.write(to: url)
        let content = try ReplyTraceContentReader().read(url, node: reasoning())
        XCTAssertTrue(content.incomplete)
        XCTAssertEqual(content.output.first?.text, "有效内容")
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testCancellationStopsContentRead() async throws {
        let url = try file([context(), message("user", "合成内容")])
        let node = reasoning()
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try ReplyTraceContentReader().read(url, node: node)
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError { }
    }

    func testMessageNodeSupportsTextParts() throws {
        var node = reasoning()
        node = ReplyTraceNode(id: "message", threadID: "main", turnID: "turn", kind: .message,
                              name: "回复阶段", status: .completed, startedAt: 0, timing: .point, sourceItemID: "message-1")
        let content = try read([context(), message("user", "输入"),
            item("item_completed", "message-1", "AgentMessage", ["content": [["type": "Text", "text": "输出"]]])], node: node)
        XCTAssertEqual(content.input.first?.text, "输入")
        XCTAssertEqual(content.output.first?.text, "输出")
    }

    private struct Record {
        let type: String
        var payload: [String: Any]
    }
    private func context(_ turn: String = "turn") -> Record { .init(type: "turn_context", payload: ["turn_id": turn]) }
    private func response(_ payload: [String: Any]) -> Record { .init(type: "response_item", payload: payload) }
    private func message(_ role: String, _ text: String) -> Record {
        response(["type": "message", "role": role, "content": [["type": role == "user" ? "input_text" : "output_text", "text": text]]])
    }
    private func item(_ event: String, _ id: String, _ type: String, _ body: [String: Any] = [:]) -> Record {
        .init(type: "event_msg", payload: ["type": event, "item": body.merging(["id": id, "type": type]) { _, new in new }])
    }
    private func usage(_ id: String) -> Record {
        .init(type: "token_usage_record", payload: ["response_id": id, "thread_id": "main", "turn_id": "turn"])
    }
    private func reasoning() -> ReplyTraceNode {
        .init(id: "reason", threadID: "main", turnID: "turn", kind: .reasoning, name: "推理阶段",
              status: .completed, startedAt: 0, timing: .point, sourceItemID: "reason-1")
    }
    private func model(_ id: String) -> ReplyTraceNode {
        .init(id: id, threadID: "main", turnID: "turn", kind: .usage, name: "模型用量",
              status: .completed, startedAt: 0, timing: .point, responseID: id)
    }
    private func read(_ records: [Record], node: ReplyTraceNode? = nil) throws -> ReplyTraceNodeContent {
        try ReplyTraceContentReader().read(file(records), node: node ?? reasoning())
    }
    private func file(_ records: [Record]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "content-test-\(UUID().uuidString).jsonl")
        let data = try records.reduce(into: Data()) { result, record in
            result.append(try JSONSerialization.data(withJSONObject: ["type": record.type, "payload": record.payload]))
            result.append(0x0A)
        }
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
