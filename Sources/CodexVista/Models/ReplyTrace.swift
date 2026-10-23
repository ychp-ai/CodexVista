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

struct ReplyTraceNode: Identifiable, Equatable, Sendable {
    let id: String
    var parentID: String?
    let threadID: String
    let turnID: String?
    let kind: ReplyTraceNodeKind
    let name: String
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
