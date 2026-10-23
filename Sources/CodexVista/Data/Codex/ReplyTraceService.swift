import Foundation

enum ReplyTraceError: Error, LocalizedError {
    case missingSource, unreadableSource

    var errorDescription: String? {
        switch self {
        case .missingSource: "找不到这次回复的本地记录。记录可能已移动或删除。"
        case .unreadableSource: "无法读取本地调用记录，请检查 Codex 数据目录后重试。"
        }
    }
}

actor ReplyTraceService {
    static let shared = ReplyTraceService()
    private let rootURL: URL

    init(rootURL: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex")) {
        self.rootURL = rootURL
    }

    func load(reply: ProjectReplyUsage) throws -> ReplyTrace {
        guard let threadID = reply.traceThreadID else { throw ReplyTraceError.missingSource }
        let inventory: CodexSourceInventory
        do { inventory = try CodexSourceDiscovery().discover(rootURL: rootURL) }
        catch { throw ReplyTraceError.unreadableSource }
        return try load(reply: reply, threadID: threadID, inventory: inventory)
    }

    func loadContent(node: ReplyTraceNode) throws -> ReplyTraceNodeContent {
        try Task.checkCancellation()
        let inventory: CodexSourceInventory
        do { inventory = try CodexSourceDiscovery().discover(rootURL: rootURL) }
        catch { throw ReplyTraceError.unreadableSource }
        guard let url = inventory.rollouts.first(where: { $0.thread?.threadID == node.threadID })?.url
            ?? inventory.rollouts.first(where: { $0.url.lastPathComponent.hasSuffix("-\(node.threadID).jsonl") })?.url
        else { throw ReplyTraceError.missingSource }
        do { return try ReplyTraceContentReader().read(url, node: node) }
        catch is CancellationError { throw CancellationError() }
        catch { throw ReplyTraceError.unreadableSource }
    }

    private func load(reply: ProjectReplyUsage, threadID: String, inventory: CodexSourceInventory) throws -> ReplyTrace {
        func source(_ id: String) -> URL? {
            inventory.rollouts.first { $0.thread?.threadID == id }?.url
                ?? inventory.rollouts.first { $0.url.lastPathComponent.hasSuffix("-\(id).jsonl") }?.url
        }
        guard let url = source(threadID) else { throw ReplyTraceError.missingSource }
        var main = ReplyTraceSlice(threadID: threadID, turnID: reply.id)
        do { try main.read(url) }
        catch is CancellationError { throw CancellationError() }
        catch { throw ReplyTraceError.unreadableSource }
        let rootID = "reply:\(threadID):\(reply.id)"
        let initialNodes = main.resolvedNodes(parentID: rootID)
        let start = main.start ?? reply.startedAtMilliseconds ?? initialNodes.map(\.startedAt).min() ?? reply.lastUsageAtMilliseconds
        let end = main.end ?? reply.endedAtMilliseconds
        let intervalEnd = max(start, end ?? Int64(Date().timeIntervalSince1970 * 1_000))
        let status: ReplyTraceStatus = main.status ?? {
            switch reply.status {
            case .completed: .completed
            case .interrupted, .rolledBack: .interrupted
            case .inProgress: .running
            case .unknown: .unknown
            }
        }()
        let root = ReplyTraceNode(
            id: rootID, parentID: nil, threadID: threadID, turnID: reply.id,
            kind: .reply, name: "本次回复", status: status,
            startedAt: start, endedAt: end, timing: main.start != nil && main.end != nil ? .recorded : .estimated,
            model: reply.modelCalls.map(\.name).joined(separator: " · "),
            reasoningEffort: main.reasoningEffort,
            timeToFirstTokenMilliseconds: main.timeToFirstTokenMilliseconds,
            modelContextWindow: main.modelContextWindow, contextWindowNumber: main.contextWindowNumber
        )
        var nodes = [root] + initialNodes
        var notices = main.notices
        var visited: Set<String> = [threadID]
        var queue = main.childParents.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        // Old rollouts may only expose relationships in the read-only index.
        for child in inventory.threadIndex where child.parentThreadID == threadID
            && child.createdAtMilliseconds >= start && child.createdAtMilliseconds <= intervalEnd {
            if !queue.contains(where: { $0.0 == child.threadID }) { queue.append((child.threadID, rootID)) }
        }
        while !queue.isEmpty, visited.count < 24, nodes.count < 6_000 {
            try Task.checkCancellation()
            let (childID, parentID) = queue.removeFirst()
            guard visited.insert(childID).inserted else { continue }
            guard let childURL = source(childID) else {
                notices.append("部分子代理记录不可用，调用链可能不完整。")
                continue
            }
            var child = ReplyTraceSlice(threadID: childID, turnID: nil, interval: start...intervalEnd)
            do { try child.read(childURL) }
            catch is CancellationError { throw CancellationError() }
            catch { notices.append("部分子代理记录读取失败。"); continue }
            let groupID = "agent:\(childID)"
            let childNodes = child.resolvedNodes(parentID: groupID)
            guard !childNodes.isEmpty else { continue }
            let index = inventory.threadIndex.first { $0.threadID == childID }
            let nickname = child.agentIdentity?.nickname ?? index?.agentNickname
            let role = child.agentIdentity?.role ?? index?.agentRole
            let models = Set(childNodes.compactMap(\.model)).sorted()
            let efforts = Set(childNodes.compactMap(\.reasoningEffort))
            nodes.append(ReplyTraceNode(
                id: groupID, parentID: parentID, threadID: childID, turnID: nil,
                kind: .subagent, name: "子代理 · \(nickname ?? role ?? ThreadDisplayIdentifier.make(from: childID))",
                status: child.status ?? .unknown,
                startedAt: childNodes.map(\.startedAt).min() ?? start,
                endedAt: childNodes.compactMap(\.endedAt).max(), timing: .estimated,
                model: models.isEmpty ? nil : models.joined(separator: " · "),
                reasoningEffort: efforts.count == 1 ? efforts.first : nil,
                agent: ReplyTraceAgentMetadata(nickname: nickname, role: role),
                modelContextWindow: child.modelContextWindow, contextWindowNumber: child.contextWindowNumber
            ))
            nodes.append(contentsOf: childNodes)
            notices.append(contentsOf: child.notices)
            queue.append(contentsOf: child.childParents.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
        }
        if !queue.isEmpty { notices.append("记录较多，已限制本次加载范围；部分子代理未展开。") }
        if nodes.count == 1 { notices.append("这次回复没有可展示的节点元数据，可能来自较早的 Codex 版本。") }
        if !nodes.contains(where: { $0.kind == .usage }) {
            notices.append("记录未提供逐次模型用量；回复总 Token 仍以看板统计为准。")
        }
        return ReplyTrace(nodes: nodes, notices: Array(Set(notices)).sorted())
    }
}

/// One-pass metadata reduction for a single reply, or a linked agent's bounded time range.
struct ReplyTraceSlice {
    let threadID: String
    let turnID: String?
    var interval: ClosedRange<Int64>?
    private(set) var start: Int64?
    private(set) var end: Int64?
    private(set) var status: ReplyTraceStatus?
    private(set) var timeToFirstTokenMilliseconds: Int64?
    private(set) var childParents: [String: String] = [:]
    private(set) var notices: [String] = []
    private(set) var agentIdentity: ReplyTraceAgentMetadata?
    private(set) var modelContextWindow: Int?
    private(set) var contextWindowNumber: Int?
    private var currentTurn: String?
    private var modelsByTurn: [String: String] = [:]
    private var effortsByTurn: [String: ReplyTraceReasoningEffort] = [:]
    private var items: [String: ReplyTraceNode] = [:]
    private var commandItems: Set<String> = []
    private var calls: [String: ReplyTraceNode] = [:]
    private var outputTimes: [String: Int64] = [:]
    private var capacityByTurn: [String: Int] = [:]
    private var compactionMarkers: [String: ReplyTraceNode] = [:]

    var reasoningEffort: ReplyTraceReasoningEffort? { turnID.flatMap { effortsByTurn[$0] } }

    init(threadID: String, turnID: String?, interval: ClosedRange<Int64>? = nil) {
        self.threadID = threadID
        self.turnID = turnID
        self.interval = interval
    }

    mutating func read(_ url: URL) throws {
        let decoder = JSONDecoder()
        let incomplete = try ReplyTraceLineReader().read(url) { data in
            guard let event = try? decoder.decode(ReplyTraceEvent.self, from: data) else {
                if !notices.contains("部分记录无法解析，已跳过。") { notices.append("部分记录无法解析，已跳过。") }
                return
            }
            consume(event)
        }
        if incomplete { notices.append("部分记录尚未写完或超过读取上限；刷新后可重新加载。") }
    }

    mutating func consume(_ event: ReplyTraceEvent) {
        guard event.threadID == nil || event.threadID == threadID else { return }
        if event.type == "session" {
            agentIdentity = event.agent
            return
        }
        if event.type == "context" || event.type == "start" {
            currentTurn = event.turnID ?? currentTurn
            if let model = event.model, let currentTurn { modelsByTurn[currentTurn] = model }
            if event.type == "context", let currentTurn { effortsByTurn[currentTurn] = event.reasoningEffort }
        }
        let resolvedTurn = event.turnID ?? currentTurn
        let model = resolvedTurn.flatMap { modelsByTurn[$0] }
        let effort = resolvedTurn.flatMap { effortsByTurn[$0] }
        if let turnID, resolvedTurn != turnID { return }
        guard event.type != "ignored", let timestamp = event.timestamp ?? event.start else { return }
        let eventStart = event.start ?? timestamp
        if let interval, !interval.contains(eventStart) { return }
        guard items.count + calls.count + compactionMarkers.count < 5_000 else {
            if !notices.contains("节点较多，仅展示前 5,000 条元数据。") { notices.append("节点较多，仅展示前 5,000 条元数据。") }
            return
        }
        switch event.type {
        case "capacity":
            if let capacity = event.modelContextWindow, let resolvedTurn {
                capacityByTurn[resolvedTurn] = capacity
                modelContextWindow = capacity
            }
        case "compacted":
            if let number = event.contextWindowNumber, resolvedTurn != nil {
                contextWindowNumber = number
            }
            // A marker and ContextCompaction can describe the same work. Prefer item spans per turn.
            guard let windowID = event.itemID, let resolvedTurn else { return }
            let key = "compacted:\(threadID):\(resolvedTurn):\(windowID)"
            compactionMarkers[key] = ReplyTraceNode(
                id: key, threadID: threadID, turnID: resolvedTurn, kind: .compaction,
                name: "上下文压缩", status: .completed, startedAt: timestamp, timing: .point,
                model: model, reasoningEffort: effort, contextWindowNumber: event.contextWindowNumber
            )
        case "start":
            start = min(start ?? timestamp, timestamp)
            end = nil
            status = .running
            timeToFirstTokenMilliseconds = nil
        case "end":
            if let recordedStart = event.start { start = min(start ?? recordedStart, recordedStart) }
            end = event.end ?? timestamp
            status = event.status
            timeToFirstTokenMilliseconds = event.timeToFirstTokenMilliseconds
        case "item":
            guard let itemID = event.itemID, let kind = event.kind, let name = event.name else { return }
            let key = "item:\(threadID):\(resolvedTurn ?? "unknown"):\(itemID)"
            if event.isCommandExecution { commandItems.insert(key) }
            // Repeated completion records and a preceding item_started collapse into one span.
            if items[key]?.endedAt != nil, event.end == nil { return }
            let validEnd = event.end.flatMap { $0 >= eventStart ? $0 : nil }
            items[key] = ReplyTraceNode(
                id: key, parentID: nil, threadID: threadID, turnID: resolvedTurn,
                kind: kind, name: name, status: event.status,
                startedAt: eventStart, endedAt: validEnd,
                timing: event.start != nil && validEnd != nil ? .recorded : .point,
                model: model, exitCode: event.exitCode, reasoningEffort: effort, messagePhase: event.messagePhase,
                tool: event.toolMetadata, agent: event.agent, sourceItemID: itemID
            )
            for childID in event.childThreadIDs where childID != threadID && childParents[childID] == nil {
                childParents[childID] = key
            }
        case "usage":
            guard let responseID = event.itemID, let tokens = event.tokens,
                  tokens.inputTokens >= 0, tokens.cachedInputTokens >= 0,
                  tokens.outputTokens >= 0, tokens.reasoningOutputTokens >= 0, tokens.totalTokens >= 0,
                  tokens.cachedInputTokens <= tokens.inputTokens,
                  tokens.reasoningOutputTokens <= tokens.outputTokens else { return }
            let key = "usage:\(threadID):\(responseID)"
            if items[key] == nil {
                items[key] = ReplyTraceNode(
                    id: key, parentID: nil, threadID: threadID, turnID: resolvedTurn,
                    kind: .usage, name: "模型用量", status: .completed,
                    startedAt: timestamp, endedAt: nil, timing: .point,
                    model: model, tokens: tokens, reasoningEffort: effort, responseID: responseID
                )
            }
        case "call":
            guard let callID = event.itemID, let name = event.name else { return }
            let key = "call:\(threadID):\(resolvedTurn ?? "unknown"):\(callID)"
            if calls[key] == nil {
                calls[key] = ReplyTraceNode(
                    id: key, parentID: nil, threadID: threadID, turnID: resolvedTurn,
                    kind: .tool, name: name, status: .unknown,
                    startedAt: timestamp, endedAt: nil, timing: .estimated, model: model, reasoningEffort: effort
                )
            }
        case "output":
            guard let callID = event.itemID else { return }
            outputTimes["call:\(threadID):\(resolvedTurn ?? "unknown"):\(callID)"] = timestamp
        default: break
        }
    }

    func resolvedNodes(parentID: String) -> [ReplyTraceNode] {
        let turnsWithRecordedTools = Set(items.values.filter { $0.kind == .tool }.compactMap(\.turnID))
        var result = Array(items.values)
        let turnsWithCompactionItems = Set(items.values.filter { $0.kind == .compaction }.compactMap(\.turnID))
        result.append(contentsOf: compactionMarkers.values.filter { !turnsWithCompactionItems.contains($0.turnID ?? "") })
        for (id, var call) in calls {
            // New item metadata describes actual tools inside wrappers such as functions.exec.
            // Mixing the wrapper records in would double count the same work.
            guard !turnsWithRecordedTools.contains(call.turnID ?? "") else { continue }
            if let output = outputTimes[id], output >= call.startedAt { call.endedAt = output }
            if call.endedAt == nil, status == .running { call.status = .running }
            result.append(call)
        }
        return result.map { node in
            var node = node
            // Preserve an explicit tool name only for the exact same call ID and turn.
            // Wrapper calls such as functions.exec do not identify the command inside them.
            if commandItems.contains(node.id),
               let call = calls["call:" + node.id.dropFirst("item:".count)],
               let toolName = call.name.split(separator: ".").last,
               ["exec_command", "write_stdin", "shell", "shell_command", "local_shell"].contains(String(toolName)) {
                node.name = call.name
            }
            node.parentID = parentID
            node.modelContextWindow = node.turnID.flatMap { capacityByTurn[$0] }
            // Window numbers belong to marker records; do not infer a marker-to-span pairing.
            return node
        }.sorted {
            if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
            return $0.id < $1.id
        }
    }
}
