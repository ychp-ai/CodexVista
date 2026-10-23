import Foundation

/// Deliberately has no keys for content, arguments, commands, results or summaries.
struct ReplyTraceEvent: Decodable, Sendable {
    let timestamp: Int64?
    var type = "ignored"
    var threadID: String?
    var turnID: String?
    var rootTurnID: String?
    var model: String?
    var itemID: String?
    var kind: ReplyTraceNodeKind?
    var name: String?
    var status: ReplyTraceStatus = .unknown
    var start: Int64?
    var end: Int64?
    var exitCode: Int?
    var tokens: ReplyTraceTokens?
    var childThreadIDs: [String] = []
    var reasoningEffort: ReplyTraceReasoningEffort?
    var messagePhase: ReplyTraceMessagePhase?
    var timeToFirstTokenMilliseconds: Int64?

    private enum Key: String, CodingKey {
        case timestamp, type, payload, model, item, id, name, namespace, status, server, tool, usage
        case threadID = "thread_id", turnID = "turn_id", rootTurnID = "root_turn_id"
        case callID = "call_id", responseID = "response_id", agentThreadID = "agent_thread_id"
        case receiverThreadIDs = "receiver_thread_ids"
        case startedAt = "started_at", completedAt = "completed_at"
        case startedAtMS = "started_at_ms", completedAtMS = "completed_at_ms"
        case exitCode = "exit_code"
        case effort, phase
        case timeToFirstTokenMS = "time_to_first_token_ms"
    }

    init(from decoder: Decoder) throws {
        let envelope = try decoder.container(keyedBy: Key.self)
        timestamp = Self.milliseconds(try? envelope.decode(String.self, forKey: .timestamp))
        let envelopeType = try envelope.decode(String.self, forKey: .type)
        guard ["turn_context", "event_msg", "response_item", "token_usage_record"].contains(envelopeType),
              let p = try? envelope.nestedContainer(keyedBy: Key.self, forKey: .payload) else { return }
        threadID = Self.identifier(try? p.decode(String.self, forKey: .threadID))
        turnID = Self.identifier(try? p.decode(String.self, forKey: .turnID))
        rootTurnID = Self.identifier(try? p.decode(String.self, forKey: .rootTurnID))
        if envelopeType == "turn_context" {
            type = "context"
            model = Self.identifier(try? p.decode(String.self, forKey: .model))
            reasoningEffort = try? p.decode(ReplyTraceReasoningEffort.self, forKey: .effort)
            return
        }
        if envelopeType == "token_usage_record" {
            type = "usage"
            itemID = Self.identifier(try? p.decode(String.self, forKey: .responseID))
            tokens = try? p.decode(ReplyTraceTokens.self, forKey: .usage)
            return
        }
        let eventType = try? p.decode(String.self, forKey: .type)
        if envelopeType == "response_item" {
            switch eventType {
            case "function_call", "custom_tool_call":
                type = "call"
                let namespace = Self.identifier(try? p.decode(String.self, forKey: .namespace))
                name = Self.identifier(try? p.decode(String.self, forKey: .name))
                if let namespace, let toolName = name { name = namespace + "." + toolName }
                itemID = Self.identifier(try? p.decode(String.self, forKey: .callID))
            case "function_call_output", "custom_tool_call_output":
                type = "output"
                itemID = Self.identifier(try? p.decode(String.self, forKey: .callID))
            default: break
            }
            return
        }
        switch eventType {
        case "task_started": type = "start"
        case "task_complete", "turn_aborted":
            type = "end"
            status = eventType == "task_complete" ? .completed : .interrupted
            start = Self.milliseconds(try? p.decode(String.self, forKey: .startedAt))
            end = Self.milliseconds(try? p.decode(String.self, forKey: .completedAt)) ?? timestamp
            if eventType == "task_complete" {
                timeToFirstTokenMilliseconds = Self.validMilliseconds(try? p.decode(Int64.self, forKey: .timeToFirstTokenMS))
            }
        case "item_started", "item_completed":
            guard let item = try? p.nestedContainer(keyedBy: Key.self, forKey: .item),
                  let itemType = try? item.decode(String.self, forKey: .type) else { return }
            itemID = Self.identifier(try? item.decode(String.self, forKey: .id))
            start = Self.validMilliseconds(try? p.decode(Int64.self, forKey: .startedAtMS))
            end = Self.validMilliseconds(try? p.decode(Int64.self, forKey: .completedAtMS))
            if eventType == "item_started" { status = .running }
            else { status = .completed }
            if let raw = try? item.decode(String.self, forKey: .status) {
                switch raw.lowercased() {
                case "failed", "error", "declined": status = .failed
                case "interrupted", "cancelled", "canceled": status = .interrupted
                case "inprogress", "in_progress", "running": status = .running
                case "completed", "success": status = .completed
                default: status = .unknown
                }
            }
            switch itemType {
            case "CommandExecution", "commandExecution":
                kind = .tool; name = "命令执行"
                exitCode = try? item.decode(Int.self, forKey: .exitCode)
                if let exitCode, exitCode != 0 { status = .failed }
            case "McpToolCall", "mcpToolCall":
                kind = .tool
                let server = Self.identifier(try? item.decode(String.self, forKey: .server))
                let tool = Self.identifier(try? item.decode(String.self, forKey: .tool))
                name = [server, tool].compactMap { $0 }.joined(separator: ".")
                if name == "" { name = "MCP 工具" }
            case "FileChange", "fileChange": kind = .tool; name = "文件变更"
            case "Reasoning", "reasoning": kind = .reasoning; name = "推理阶段"
            case "AgentMessage", "agentMessage":
                kind = .message
                messagePhase = try? item.decode(ReplyTraceMessagePhase.self, forKey: .phase)
                name = messagePhase?.title ?? "回复阶段"
            case "ContextCompaction", "contextCompaction": kind = .compaction; name = "上下文压缩"
            case "SubAgentActivity", "subAgentActivity":
                kind = .subagent; name = "子代理活动"
                childThreadIDs = [Self.identifier(try? item.decode(String.self, forKey: .agentThreadID))].compactMap { $0 }
            case "CollabAgentToolCall", "collabAgentToolCall":
                kind = .tool
                name = Self.identifier(try? item.decode(String.self, forKey: .tool)) ?? "代理协作"
                childThreadIDs = (try? item.decode([String].self, forKey: .receiverThreadIDs))?
                    .compactMap(Self.identifier) ?? []
            case "Extension": kind = .tool; name = "扩展工具"
            case "ImageView", "imageView": kind = .tool; name = "查看图片"
            default: return
            }
            type = "item"
        default: break
        }
    }

    private static func identifier(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.utf8.count <= 180,
              value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "_-.:/".unicodeScalars.contains($0) }) else { return nil }
        return value
    }

    private static func milliseconds(_ value: String?) -> Int64? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        guard let date else { return nil }
        let milliseconds = date.timeIntervalSince1970 * 1_000
        guard milliseconds.isFinite, milliseconds >= 0, milliseconds < 253_402_300_800_000 else { return nil }
        return Int64(milliseconds.rounded())
    }

    private static func validMilliseconds(_ value: Int64?) -> Int64? {
        guard let value, value >= 0, value < 253_402_300_800_000 else { return nil }
        return value
    }
}

/// Bounds memory per line; never retains raw lines after the metadata callback returns.
struct ReplyTraceLineReader {
    var maximumLineBytes = 8 * 1_024 * 1_024
    var maximumFileBytes = 256 * 1_024 * 1_024
    var chunkSize = 64 * 1_024

    func read(_ url: URL, consume: (Data) throws -> Void) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var pending = Data()
        var skipping = false
        var incomplete = false
        var bytesRead = 0
        while bytesRead < maximumFileBytes,
              let chunk = try handle.read(upToCount: min(chunkSize, maximumFileBytes - bytesRead)), !chunk.isEmpty {
            try Task.checkCancellation()
            bytesRead += chunk.count
            var start = chunk.startIndex
            for newline in chunk.indices where chunk[newline] == 0x0A {
                if !skipping, pending.count + newline - start <= maximumLineBytes {
                    pending.append(contentsOf: chunk[start..<newline])
                    if !pending.isEmpty { try consume(pending) }
                } else { incomplete = true }
                pending.removeAll(keepingCapacity: true)
                skipping = false
                start = newline + 1
            }
            if !skipping, pending.count + chunk.endIndex - start <= maximumLineBytes {
                pending.append(contentsOf: chunk[start...])
            } else { skipping = true; pending.removeAll(keepingCapacity: true); incomplete = true }
        }
        // A trailing partial line is intentionally ignored until a later refresh.
        return incomplete || !pending.isEmpty || bytesRead == maximumFileBytes
    }
}
