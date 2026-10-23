import Foundation

enum ReplyTraceNodeKind: String, CaseIterable, Sendable {
    case reply, subagent, tool, reasoning, message, usage, compaction

    var title: String {
        switch self {
        case .reply: "回复"
        case .subagent: "子代理"
        case .tool: "工具"
        case .reasoning: "推理阶段"
        case .message: "回复阶段"
        case .usage: "Token 记录"
        case .compaction: "上下文压缩"
        }
    }
}

enum ReplyTraceStatus: String, Sendable {
    case completed, failed, interrupted, running, unknown

    var title: String {
        switch self {
        case .completed: "已完成"
        case .failed: "失败"
        case .interrupted: "已中断"
        case .running: "进行中"
        case .unknown: "状态未知"
        }
    }
}

enum ReplyTraceTiming: String, Sendable {
    case recorded, estimated, point

    var title: String {
        switch self {
        case .recorded: "原始起止时间"
        case .estimated: "记录时间估算"
        case .point: "单点记录"
        }
    }
}

enum ReplyTraceReasoningEffort: String, Decodable, Sendable {
    case none, minimal, low, medium, high, xhigh, max, ultra
}

enum ReplyTraceMessagePhase: String, Decodable, Sendable {
    case commentary
    case partialAnswer = "partial_answer"
    case finalAnswer = "final_answer"

    var title: String {
        switch self {
        case .commentary: "进度说明"
        case .partialAnswer: "阶段性回答"
        case .finalAnswer: "最终回答"
        }
    }
}

struct ReplyTraceTokens: Equatable, Sendable, Decodable {
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let reasoningOutputTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens", cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens", reasoningOutputTokens = "reasoning_output_tokens"
        case totalTokens = "total_tokens"
    }

    var uncachedInput: Int { max(0, inputTokens - cachedInputTokens) }
    var visibleOutput: Int { max(0, outputTokens - reasoningOutputTokens) }
    var cacheHitRate: Double? {
        guard inputTokens > 0, cachedInputTokens >= 0, cachedInputTokens <= inputTokens else { return nil }
        return Double(cachedInputTokens) / Double(inputTokens)
    }
}

enum ReplyTraceCommandSource: String, CaseIterable, Sendable {
    case agent, userShell, unifiedExecStartup, unifiedExecInteraction

    init?(metadata: String?) {
        guard let metadata, let value = Self.allCases.first(where: {
            $0.rawValue.lowercased() == metadata.replacingOccurrences(of: "_", with: "").lowercased()
        }) else { return nil }
        self = value
    }

    var title: String {
        switch self {
        case .agent: "代理命令"
        case .userShell: "用户 Shell"
        case .unifiedExecStartup: "启动执行会话"
        case .unifiedExecInteraction: "继续执行会话"
        }
    }

    var commandName: String {
        switch self {
        case .unifiedExecStartup: "exec_command"
        case .unifiedExecInteraction: "write_stdin"
        case .userShell: "用户 Shell"
        case .agent: "命令执行（工具名未记录）"
        }
    }
}

struct ReplyTraceToolMetadata: Equatable, Sendable {
    var source: ReplyTraceCommandSource?
    var processID: String?
    var pluginID: String?
    var readOnlyHint: Bool?
}

enum ReplyTraceAgentAction: String, CaseIterable, Sendable {
    case spawnAgent, sendInput, resumeAgent, wait, closeAgent, sendMessage, followupTask, interruptAgent, listAgents
    case started, interacted, interrupted, completed

    init?(metadata: String?) {
        guard let metadata, let value = Self.allCases.first(where: {
            $0.rawValue.lowercased() == metadata.replacingOccurrences(of: "_", with: "").lowercased()
        }) else { return nil }
        self = value
    }

    var title: String {
        switch self {
        case .spawnAgent: "创建子代理"
        case .sendInput: "发送输入"
        case .resumeAgent: "恢复子代理"
        case .wait: "等待子代理"
        case .closeAgent: "关闭子代理"
        case .sendMessage: "发送消息"
        case .followupTask: "追加任务"
        case .interruptAgent: "中断子代理"
        case .listAgents: "列出子代理"
        case .started: "子代理启动"
        case .interacted: "子代理交互"
        case .interrupted: "子代理中断"
        case .completed: "子代理完成"
        }
    }
}

enum ReplyTraceAgentStatus: String, CaseIterable, Sendable {
    case pendingInit, running, interrupted, completed, errored, shutdown, notFound

    init?(metadata: String?) {
        guard let metadata, let value = Self.allCases.first(where: {
            $0.rawValue.lowercased() == metadata.replacingOccurrences(of: "_", with: "").lowercased()
        }) else { return nil }
        self = value
    }

    var title: String {
        switch self {
        case .pendingInit: "等待初始化"
        case .running: "运行中"
        case .interrupted: "已中断"
        case .completed: "已完成"
        case .errored: "出错"
        case .shutdown: "已关闭"
        case .notFound: "未找到"
        }
    }
}

struct ReplyTraceAgentTarget: Equatable, Sendable {
    let threadID: String
    let status: ReplyTraceAgentStatus?
}

struct ReplyTraceAgentMetadata: Equatable, Sendable {
    var nickname: String?
    var role: String?
    var action: ReplyTraceAgentAction?
    var model: String?
    var reasoningEffort: ReplyTraceReasoningEffort?
    var configurationIsRequested = false
    var targets: [ReplyTraceAgentTarget] = []
}

struct ReplyTraceNode: Identifiable, Equatable, Sendable {
    let id: String
    var parentID: String?
    let threadID: String
    let turnID: String?
    let kind: ReplyTraceNodeKind
    var name: String
    var status: ReplyTraceStatus
    var startedAt: Int64
    var endedAt: Int64?
    let timing: ReplyTraceTiming
    var model: String?
    var tokens: ReplyTraceTokens?
    var exitCode: Int?
    var reasoningEffort: ReplyTraceReasoningEffort?
    var messagePhase: ReplyTraceMessagePhase?
    var timeToFirstTokenMilliseconds: Int64?
    var tool: ReplyTraceToolMetadata?
    var agent: ReplyTraceAgentMetadata?
    var modelContextWindow: Int?
    var contextWindowNumber: Int?
    var sourceItemID: String?
    var responseID: String?

    var supportsContent: Bool { kind == .usage || kind == .reasoning || kind == .message }

    var duration: Int64? { endedAt.map { max(0, $0 - startedAt) } }
}

struct ReplyTrace: Equatable, Sendable {
    let nodes: [ReplyTraceNode]
    let notices: [String]

    var start: Int64 { nodes.map(\.startedAt).min() ?? 0 }
    var end: Int64 { nodes.map { $0.endedAt ?? $0.startedAt }.max() ?? start }
    var duration: Int64 { max(1, end - start) }
    var toolCount: Int { nodes.filter { $0.kind == .tool }.count }
    var failureCount: Int { nodes.filter { $0.status == .failed }.count }
    var root: ReplyTraceNode? { nodes.first { $0.kind == .reply && $0.parentID == nil } }
    var compactions: [ReplyTraceNode] { nodes.filter { $0.kind == .compaction } }

    func relatedExecutions(to node: ReplyTraceNode) -> [ReplyTraceNode] {
        guard let processID = node.tool?.processID else { return [] }
        return nodes.filter {
            $0.id != node.id && $0.threadID == node.threadID && $0.tool?.processID == processID
        }.sorted { $0.startedAt == $1.startedAt ? $0.id < $1.id : $0.startedAt < $1.startedAt }
    }

    /// Union of recorded intervals: parallel agents must not multiply elapsed time.
    var recordedCompactionDuration: Int64? {
        let intervals = compactions.filter { $0.timing == .recorded && $0.status == .completed }
            .compactMap { node in node.endedAt.map { (node.startedAt, $0) } }.sorted { $0.0 < $1.0 }
        guard var span = intervals.first else { return nil }
        var total: Int64 = 0
        for next in intervals.dropFirst() {
            if next.0 <= span.1 { span.1 = max(span.1, next.1) }
            else { total += span.1 - span.0; span = next }
        }
        return total + span.1 - span.0
    }

    /// Weighted by input tokens across the loaded, deduplicated usage records, including agents.
    var cacheHitRate: Double? {
        let usage = nodes.filter { $0.kind == .usage }.compactMap(\.tokens).filter { $0.cacheHitRate != nil }
        let input = usage.reduce(0.0) { $0 + Double($1.inputTokens) }
        guard input > 0 else { return nil }
        return usage.reduce(0.0) { $0 + Double($1.cachedInputTokens) } / input
    }

    var slowestTools: [ReplyTraceNode] {
        Array(nodes.filter { $0.kind == .tool && $0.timing != .point && $0.duration != nil && $0.status != .running }
            .sorted {
                if $0.duration != $1.duration { return ($0.duration ?? 0) > ($1.duration ?? 0) }
                if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
                return $0.id < $1.id
            }.prefix(5))
    }
}
