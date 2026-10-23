import Foundation

/// Explicitly invoked by the node inspector, separate from the metadata decoder/importer.
struct ReplyTraceContentReader {
    var lineReader = ReplyTraceLineReader()
    static let maximumBlockCharacters = 16_384
    static let maximumSectionCharacters = 65_536
    static let maximumBlocks = 32

    func read(_ url: URL, node: ReplyTraceNode) throws -> ReplyTraceNodeContent {
        guard node.supportsContent, let turnID = node.turnID else { return .init() }
        guard node.kind == .usage ? node.responseID != nil : node.sourceItemID != nil else { return .init() }
        var result = ReplyTraceNodeContent(outputIsEstimated: node.kind == .usage)
        var currentTurn: String?
        var sourceMatches = true
        var context = TextBuffer()
        var pendingOutput = TextBuffer()
        var inputAtOutput: TextBuffer?
        var seenResponses = Set<String>()
        var selectedItemFound = false
        let decoder = JSONDecoder()
        let incomplete = try lineReader.read(url) { data in
            try Task.checkCancellation()
            // Check scope without decoding any body text from other turns/threads.
            guard let event = try? decoder.decode(ReplyTraceEvent.self, from: data) else {
                result.incomplete = true
                return
            }
            if event.type == "session" {
                sourceMatches = event.threadID == nil || event.threadID == node.threadID
                return
            }
            guard sourceMatches, event.threadID == nil || event.threadID == node.threadID else { return }
            if event.type == "context" || event.type == "start" {
                let next = event.turnID ?? currentTurn
                if next != currentTurn {
                    context = TextBuffer()
                    pendingOutput = TextBuffer()
                    inputAtOutput = nil
                }
                currentTurn = next
            }
            guard (event.turnID ?? currentTurn) == turnID else { return }
            if event.type == "compacted" {
                context = TextBuffer()
                pendingOutput = TextBuffer()
                inputAtOutput = nil
                if !result.found { result.crossedCompaction = true }
                return
            }
            if event.type == "usage", let responseID = event.itemID {
                guard seenResponses.insert(responseID).inserted else { return }
                if node.kind == .usage, node.responseID == responseID, !result.found {
                    result.found = true
                    let input = inputAtOutput ?? context
                    result.input = input.blocks
                    result.output = pendingOutput.blocks
                    result.truncated = input.truncated || pendingOutput.truncated
                }
                pendingOutput = TextBuffer()
                inputAtOutput = nil
                return
            }
            // Once a model record is resolved, later text can never enter its content.
            guard node.kind != .usage || !result.found else { return }
            guard let record = try? decoder.decode(ContentRecord.self, from: data) else {
                result.incomplete = true
                return
            }
            guard record.recognized else { return }
            let isTarget = node.kind != .usage && record.itemID == node.sourceItemID
                && record.kind == node.kind
            if isTarget, !selectedItemFound {
                selectedItemFound = true
                result.found = true
                result.input = context.blocks
                result.truncated = context.truncated
            }
            if record.isOutput, inputAtOutput == nil { inputAtOutput = context }
            for block in record.blocks {
                if isTarget {
                    var output = TextBuffer(blocks: result.output, truncated: result.truncated)
                    output.append(block)
                    result.output = output.blocks
                    result.truncated = output.truncated
                }
                if record.isOutput { pendingOutput.append(block) }
                context.append(block)
            }
        }
        result.incomplete = result.incomplete || incomplete
        return result
    }
}

private struct TextBuffer {
    var blocks: [ReplyTraceTextBlock] = []
    var truncated = false

    mutating func append(_ block: ReplyTraceTextBlock) {
        guard !block.text.isEmpty else { return }
        if let index = blocks.firstIndex(where: { $0.id == block.id }) {
            blocks[index] = block
        } else if !blocks.contains(where: {
            ($0.id.hasPrefix("anonymous:") || block.id.hasPrefix("anonymous:"))
                && $0.title == block.title && $0.text == block.text
        }) {
            // Response items and lifecycle items can contain the same text under different IDs.
            blocks.append(block)
        }
        truncated = truncated || block.truncated
        while blocks.count > ReplyTraceContentReader.maximumBlocks
            || blocks.reduce(0, { $0 + $1.text.count }) > ReplyTraceContentReader.maximumSectionCharacters {
            blocks.removeFirst()
            truncated = true
        }
    }
}

/// Only decodes known plain-text fields. No generic JSON rendering or attachment loading.
private struct ContentRecord: Decodable {
    var recognized = false
    var itemID: String?
    var kind: ReplyTraceNodeKind?
    var isOutput = false
    var blocks: [ReplyTraceTextBlock] = []

    private enum Key: String, CodingKey {
        case type, payload, item, id, role, content, text, summary, name, namespace, arguments, input, output
        case callID = "call_id", summaryText = "summary_text", rawContent = "raw_content"
        case encryptedContent = "encrypted_content"
    }

    init(from decoder: Decoder) throws {
        let envelope = try decoder.container(keyedBy: Key.self)
        let type = try envelope.decode(String.self, forKey: .type)
        guard type == "response_item" || type == "event_msg" else { return }
        let payload = try envelope.nestedContainer(keyedBy: Key.self, forKey: .payload)
        let container: KeyedDecodingContainer<Key>
        if type == "event_msg" {
            guard let eventType = try? payload.decode(String.self, forKey: .type),
                  ["item_started", "item_completed"].contains(eventType) else { return }
            container = try payload.nestedContainer(keyedBy: Key.self, forKey: .item)
        } else { container = payload }
        let itemType = try container.decode(String.self, forKey: .type)
        itemID = try? container.decode(String.self, forKey: .id)
        let key = itemID ?? (try? container.decode(String.self, forKey: .callID)) ?? "anonymous"
        switch itemType {
        case "Reasoning", "reasoning":
            recognized = true
            kind = .reasoning
            isOutput = true
            add(strings(container, .rawContent) + texts(container, .content), title: "推理正文", key: key + ":reasoning")
            add(strings(container, .summaryText) + texts(container, .summary), title: "推理摘要", key: key + ":summary")
            if blocks.isEmpty, container.contains(.encryptedContent),
               (try? container.decodeNil(forKey: .encryptedContent)) == false {
                add(["本地仅记录了加密推理内容，无法显示原文。"], title: "推理不可用", key: key + ":encrypted")
            }
        case "message", "AgentMessage", "agentMessage", "UserMessage", "userMessage":
            let role = (try? container.decode(String.self, forKey: .role))
                ?? (["UserMessage", "userMessage"].contains(itemType) ? "user" : "assistant")
            guard ["user", "assistant", "system", "developer"].contains(role) else { return }
            recognized = true
            isOutput = role == "assistant"
            kind = isOutput ? .message : nil
            let title = ["user": "用户输入", "assistant": "模型回复", "system": "系统消息", "developer": "开发者消息"][role]!
            add(texts(container, .content), title: title, key: key + ":" + role)
        case "function_call", "custom_tool_call":
            recognized = true
            isOutput = true
            let name = ReplyTraceEvent.identifier(try? container.decode(String.self, forKey: .name)) ?? "未记录名称"
            let namespace = ReplyTraceEvent.identifier(try? container.decode(String.self, forKey: .namespace))
            let title = "工具调用 · " + (namespace.map { $0 + "." } ?? "") + name
            let argument = try? container.decode(String.self, forKey: itemType == "function_call" ? .arguments : .input)
            add([argument ?? "未记录文本参数"], title: title, key: key + ":call")
        case "function_call_output", "custom_tool_call_output":
            recognized = true
            let output = (try? container.decode(String.self, forKey: .output)).map { [$0] }
                ?? texts(container, .output)
            add(output, title: "工具返回", key: key + ":result")
        default: break
        }
    }

    private func strings(_ container: KeyedDecodingContainer<Key>, _ key: Key) -> [String] {
        (try? container.decode([String].self, forKey: key)) ?? []
    }

    private func texts(_ container: KeyedDecodingContainer<Key>, _ key: Key) -> [String] {
        (try? container.decode([TextPart].self, forKey: key))?.compactMap(\.text) ?? []
    }

    private mutating func add(_ values: [String], title: String, key: String) {
        var text = ""
        var truncated = false
        for value in values where !value.isEmpty {
            let value = (text.isEmpty ? "" : "\n\n") + value
            let remaining = max(0, ReplyTraceContentReader.maximumBlockCharacters - text.count)
            text += value.prefix(remaining)
            if value.count > remaining { truncated = true; break }
        }
        guard !text.isEmpty else { return }
        // Without a recorded item ID, use content identity so separate messages are not overwritten.
        let id = key.hasPrefix("anonymous:") ? key + ":" + UUID().uuidString : key
        blocks.append(.init(id: id, title: title, text: text, truncated: truncated))
    }
}

private struct TextPart: Decodable {
    let text: String?
    private enum Key: String, CodingKey { case type, text }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        let type = try? container.decode(String.self, forKey: .type)
        if ["input_text", "output_text", "summary_text", "reasoning_text", "text", "Text"].contains(type) {
            text = try? container.decode(String.self, forKey: .text)
        } else { text = nil }
    }
}
