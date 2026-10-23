import Foundation

/// Ephemeral detail content. Never part of the statistics store or trace metadata cache.
struct ReplyTraceNodeContent: Equatable, Sendable {
    var input: [ReplyTraceTextBlock] = []
    var output: [ReplyTraceTextBlock] = []
    var found = false
    var truncated = false
    var incomplete = false
    var crossedCompaction = false
    var outputIsEstimated = false

    var inputScope: String {
        "本轮中、该节点之前记录的上下文片段。可能缺少系统指令、历史消息和多模态内容，不能还原完整模型请求。"
    }

    var outputScope: String {
        outputIsEstimated
            ? "相邻模型用量记录之间的输出片段，按记录顺序关联。原始记录没有逐条响应关联，无法确认全部属于这次模型调用。"
            : "按节点 ID 匹配的本地记录。推理摘要与推理正文分别标注。"
    }
}

struct ReplyTraceTextBlock: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let text: String
    var truncated = false
}
