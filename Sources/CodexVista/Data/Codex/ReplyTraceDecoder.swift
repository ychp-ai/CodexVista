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
    var toolMetadata: ReplyTraceToolMetadata?
    var isCommandExecution = false
    var agent: ReplyTraceAgentMetadata?
    var modelContextWindow: Int?
    var contextWindowNumber: Int?

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
        case source, subagent, kind, info
        case threadSpawn = "thread_spawn", agentNickname = "agent_nickname", agentRole = "agent_role"
        case processID = "process_id", processIDCamel = "processId"
        case pluginID = "plugin_id", pluginIDCamel = "pluginId"
        case readOnlyHint = "readOnlyHint", readOnlyHintSnake = "read_only_hint"
        case agentThreadIDCamel = "agentThreadId", receiverThreadIDsCamel = "receiverThreadIds"
        case agentsStates = "agents_states", agentsStatesCamel = "agentsStates"
        case reasoningEffort = "reasoning_effort", reasoningEffortCamel = "reasoningEffort"
        case modelContextWindow = "model_context_window"
        case windowNumber = "window_number", windowID = "window_id"
    }

    init(from decoder: Decoder) throws {
        let envelope = try decoder.container(keyedBy: Key.self)
        timestamp = Self.milliseconds(try? envelope.decode(String.self, forKey: .timestamp))
        let envelopeType = try envelope.decode(String.self, forKey: .type)
        guard ["session_meta", "turn_context", "event_msg", "response_item", "token_usage_record", "compacted"].contains(envelopeType),
              let p = try? envelope.nestedContainer(keyedBy: Key.self, forKey: .payload) else { return }
        threadID = Self.identifier(try? p.decode(String.self, forKey: .threadID))
        turnID = Self.identifier(try? p.decode(String.self, forKey: .turnID))
        rootTurnID = Self.identifier(try? p.decode(String.self, forKey: .rootTurnID))
        if envelopeType == "session_meta" {
            type = "session"
            threadID = Self.identifier(try? p.decode(String.self, forKey: .id))
            let source = try? p.nestedContainer(keyedBy: Key.self, forKey: .source)
            let subagent = try? source?.nestedContainer(keyedBy: Key.self, forKey: .subagent)
            let spawn = try? subagent?.nestedContainer(keyedBy: Key.self, forKey: .threadSpawn)
            agent = ReplyTraceAgentMetadata(
                nickname: Self.label((try? p.decode(String.self, forKey: .agentNickname)) ?? (try? spawn?.decode(String.self, forKey: .agentNickname))),
                role: Self.label((try? p.decode(String.self, forKey: .agentRole)) ?? (try? spawn?.decode(String.self, forKey: .agentRole)))
            )
            return
        }
        if envelopeType == "compacted" {
            type = "compacted"
            itemID = Self.identifier(try? p.decode(String.self, forKey: .windowID))
            contextWindowNumber = Self.nonnegativeInteger(try? p.decode(Int.self, forKey: .windowNumber))
            return
        }
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
        case "token_count":
            type = "capacity"
            let info = try? p.nestedContainer(keyedBy: Key.self, forKey: .info)
            if let value = Self.nonnegativeInteger(try? info?.decode(Int.self, forKey: .modelContextWindow)), value > 0 {
                modelContextWindow = value
            }
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
                kind = .tool
                isCommandExecution = true
                toolMetadata = ReplyTraceToolMetadata(
                    source: ReplyTraceCommandSource(metadata: try? item.decode(String.self, forKey: .source)),
                    processID: Self.identifier((try? item.decode(String.self, forKey: .processID)) ?? (try? item.decode(String.self, forKey: .processIDCamel))),
                    pluginID: Self.identifier((try? item.decode(String.self, forKey: .pluginID)) ?? (try? item.decode(String.self, forKey: .pluginIDCamel)))
                )
                name = toolMetadata?.source?.commandName ?? "命令执行（工具名未记录）"
                exitCode = try? item.decode(Int.self, forKey: .exitCode)
                if let exitCode, exitCode != 0 { status = .failed }
            case "McpToolCall", "mcpToolCall":
                kind = .tool
                let server = Self.identifier(try? item.decode(String.self, forKey: .server))
                let tool = Self.identifier(try? item.decode(String.self, forKey: .tool))
                name = [server, tool].compactMap { $0 }.joined(separator: ".")
                if name == "" { name = "MCP 工具" }
                toolMetadata = ReplyTraceToolMetadata(
                    pluginID: Self.identifier((try? item.decode(String.self, forKey: .pluginIDCamel)) ?? (try? item.decode(String.self, forKey: .pluginID))),
                    readOnlyHint: (try? item.decode(Bool.self, forKey: .readOnlyHint)) ?? (try? item.decode(Bool.self, forKey: .readOnlyHintSnake))
                )
            case "FileChange", "fileChange": kind = .tool; name = "文件变更"
            case "Reasoning", "reasoning": kind = .reasoning; name = "推理阶段"
            case "AgentMessage", "agentMessage":
                kind = .message
                messagePhase = try? item.decode(ReplyTraceMessagePhase.self, forKey: .phase)
                name = messagePhase?.title ?? "回复阶段"
            case "ContextCompaction", "contextCompaction": kind = .compaction; name = "上下文压缩"
            case "SubAgentActivity", "subAgentActivity":
                kind = .subagent; name = "子代理活动"
                childThreadIDs = [Self.identifier((try? item.decode(String.self, forKey: .agentThreadID)) ?? (try? item.decode(String.self, forKey: .agentThreadIDCamel)))].compactMap { $0 }
                agent = ReplyTraceAgentMetadata(action: ReplyTraceAgentAction(metadata: try? item.decode(String.self, forKey: .kind)))
                name = agent?.action?.title ?? name
            case "CollabAgentToolCall", "collabAgentToolCall":
                kind = .tool
                name = Self.identifier(try? item.decode(String.self, forKey: .tool)) ?? "代理协作"
                childThreadIDs = ((try? item.decode([String].self, forKey: .receiverThreadIDs)) ?? (try? item.decode([String].self, forKey: .receiverThreadIDsCamel)))?
                    .compactMap(Self.identifier) ?? []
                agent = ReplyTraceAgentMetadata(action: ReplyTraceAgentAction(metadata: try? item.decode(String.self, forKey: .tool)), configurationIsRequested: true)
            case "Extension": kind = .tool; name = "扩展工具"
            case "ImageView", "imageView": kind = .tool; name = "查看图片"
            default: return
            }
            if agent != nil {
                agent?.model = Self.identifier(try? item.decode(String.self, forKey: .model))
                agent?.reasoningEffort = (try? item.decode(ReplyTraceReasoningEffort.self, forKey: .reasoningEffort))
                    ?? (try? item.decode(ReplyTraceReasoningEffort.self, forKey: .reasoningEffortCamel))
                let states = (try? item.decode([String: AgentState].self, forKey: .agentsStates))
                    ?? (try? item.decode([String: AgentState].self, forKey: .agentsStatesCamel)) ?? [:]
                // AgentState deliberately decodes only status, never its message.
                agent?.targets = Set(childThreadIDs + states.keys.compactMap(Self.identifier)).sorted().map {
                    ReplyTraceAgentTarget(threadID: $0, status: states[$0]?.status)
                }
            }
            type = "item"
        default: break
        }
    }

    static func identifier(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.utf8.count <= 180, !value.hasPrefix("/"), !value.contains(".."),
              value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "_-.:/".unicodeScalars.contains($0) }) else { return nil }
        return value
    }

    private static func label(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.count <= 120,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !value.contains("/") else { return nil }
        return value
    }

    private static func nonnegativeInteger(_ value: Int?) -> Int? {
        guard let value, value >= 0, value < Int.max else { return nil }
        return value
    }

    private struct AgentState: Decodable {
        let status: ReplyTraceAgentStatus?
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            status = ReplyTraceAgentStatus(metadata: try? container.decode(String.self, forKey: .status))
        }
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
        let stream = try RolloutByteStream(url: url)
        var pending = Data()
        var skipping = false
        var incomplete = false
        var bytesRead = 0
        while bytesRead < maximumFileBytes,
              let chunk = try stream.read(upToCount: min(chunkSize, maximumFileBytes - bytesRead)), !chunk.isEmpty {
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
