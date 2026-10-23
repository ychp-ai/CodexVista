import SwiftUI

struct ReplyTraceInspector: View {
    let node: ReplyTraceNode
    let trace: ReplyTrace
    let onSelect: (ReplyTraceNode) -> Void

    @State private var showsContent = false

    var body: some View {
        VStack(spacing: 0) {
            if node.supportsContent {
                Picker("节点详情", selection: $showsContent) {
                    Text("概览").tag(false)
                    Text("输入 / 输出").tag(true)
                }
                .pickerStyle(.segmented).padding(12)
                Divider()
            }
            if showsContent, node.supportsContent {
                ReplyTraceContentLoader(node: node).id(node.id)
            } else { overview }
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(node.kind.title, systemImage: ReplyTraceFormat.icon(node.kind))
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(ReplyTraceFormat.color(node))
                Text(node.name).font(.system(size: 15, weight: .semibold)).textSelection(.enabled)
                field("状态", node.status.title)
                field("耗时", ReplyTraceFormat.nodeDuration(node))
                field("时间来源", node.timing.title)
                field("相对开始", "+\(ReplyTraceFormat.duration(max(0, node.startedAt - trace.start)))")
                field("开始时间", Date(timeIntervalSince1970: Double(node.startedAt) / 1_000).formatted(date: .omitted, time: .standard))
                if let model = node.model, !model.isEmpty { field("模型", model) }
                field("推理强度", node.reasoningEffort?.rawValue ?? "未记录")
                if node.kind == .reply {
                    field("首 Token", node.timeToFirstTokenMilliseconds.map(ReplyTraceFormat.duration) ?? "未记录")
                    Text("本次回复记录的首 Token 延迟，不代表每次模型请求的延迟。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if node.kind == .message { field("回复阶段", node.messagePhase?.title ?? "未记录") }
                if let exitCode = node.exitCode { field("退出码", exitCode.formatted()) }
                if let tool = node.tool { toolDetails(tool) }
                if let agent = node.agent { agentDetails(agent) }
                if let capacity = node.modelContextWindow {
                    field("上下文容量", "\(capacity.formatted()) Token")
                }
                if let number = node.contextWindowNumber { field("窗口序号", number.formatted()) }
                if let tokens = node.tokens {
                    Divider()
                    field("总 Token", tokens.totalTokens.formatted())
                    field("未缓存输入", tokens.uncachedInput.formatted())
                    field("缓存输入", tokens.cachedInputTokens.formatted())
                    field("可见输出", tokens.visibleOutput.formatted())
                    field("推理输出", tokens.reasoningOutputTokens.formatted())
                    field("缓存命中率", ReplyTraceFormat.cacheHitRate(tokens.cacheHitRate))
                    Text("用量记录没有请求起止时间，因此不计算该次模型请求耗时。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if node.timing == .estimated {
                    Text("根据记录时间重建，可能包含记录延迟；不代表精确执行时间。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Divider()
                field("线程", ThreadDisplayIdentifier.make(from: node.threadID))
                if let turnID = node.turnID { field("回复 ID", turnID) }
                if let responseID = node.responseID { field("响应 ID", responseID) }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(node.id)
    }

    @ViewBuilder
    private func toolDetails(_ tool: ReplyTraceToolMetadata) -> some View {
        Divider()
        if let source = tool.source { field("执行来源", source.title) }
        field("所属插件", tool.pluginID ?? "未记录")
        if let readOnly = tool.readOnlyHint {
            field("声明只读", readOnly ? "是" : "否")
            Text("由工具提供的提示，不代表权限限制或实际执行结果。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        if let processID = tool.processID {
            field("执行会话 ID", processID)
            let related = trace.relatedExecutions(to: node)
            if !related.isEmpty {
                Text("同一执行会话 · \(related.count) 条关联记录")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                ForEach(related) { other in
                    Button { onSelect(other) } label: {
                        Text("\(other.name) · +\(ReplyTraceFormat.duration(max(0, other.startedAt - trace.start)))")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }

    @ViewBuilder
    private func agentDetails(_ agent: ReplyTraceAgentMetadata) -> some View {
        Divider()
        if let nickname = agent.nickname { field("代理昵称", nickname) }
        if let role = agent.role { field("代理角色", role) }
        if let action = agent.action { field("协作动作", action.title) }
        if let model = agent.model { field(agent.configurationIsRequested ? "请求模型" : "子代理模型", model) }
        if let effort = agent.reasoningEffort {
            field(agent.configurationIsRequested ? "请求强度" : "子代理强度", effort.rawValue)
        }
        if agent.configurationIsRequested, agent.model != nil || agent.reasoningEffort != nil {
            Text("请求配置来自协作调用；实际配置请查看子代理节点。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        ForEach(agent.targets, id: \.threadID) { target in
            VStack(alignment: .leading, spacing: 5) {
                field("目标代理", ThreadDisplayIdentifier.make(from: target.threadID))
                field("记录状态", target.status?.title ?? "未记录")
                if let group = trace.nodes.first(where: { $0.id == "agent:\(target.threadID)" }) {
                    Button("查看子代理") { onSelect(group) }.buttonStyle(.link).font(.system(size: 11))
                }
            }
        }
    }

    private func field(_ name: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(name).font(.system(size: 10)).foregroundStyle(CodexVistaTheme.dashboardMutedText)
                .frame(width: 64, alignment: .leading)
            Text(value).font(.system(size: 11)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

struct ReplyTraceContextDetails: View {
    let trace: ReplyTrace
    let onSelect: (ReplyTraceNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("上下文与压缩").font(.system(size: 14, weight: .semibold))
            HStack(alignment: .top, spacing: 24) {
                summary("主回复容量", trace.root?.modelContextWindow.map { "\($0.formatted()) Token" } ?? "未记录")
                summary("最新窗口序号", trace.root?.contextWindowNumber.map { $0.formatted() } ?? "未记录")
            }
            HStack(alignment: .top, spacing: 24) {
                summary("链路压缩节点", trace.compactions.count.formatted())
                summary("已记录压缩耗时", trace.recordedCompactionDuration.map(ReplyTraceFormat.duration) ?? "未记录")
            }
            Text("容量与窗口序号取本次主回复的最新有效记录。容量不是当前占用量；压缩耗时合并重叠区间，仅包含有完整起止时间的已完成节点。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Divider()
            if trace.compactions.isEmpty {
                Text("本次加载范围没有压缩记录")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(trace.compactions) { node in
                            Button { onSelect(node) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(node.name)
                                        Text("\(ThreadDisplayIdentifier.make(from: node.threadID)) · +\(ReplyTraceFormat.duration(max(0, node.startedAt - trace.start)))")
                                            .font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(ReplyTraceFormat.nodeDuration(node)).monospacedDigit()
                                    Image(systemName: "arrow.up.right")
                                }
                                .font(.system(size: 12)).padding(6).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).help("定位到压缩节点")
                        }
                    }
                }
                .frame(height: min(220, CGFloat(trace.compactions.count) * 52))
            }
        }
        .padding(18).frame(width: 400)
    }

    private func summary(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 14, weight: .medium)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum ReplyTraceFormat {
    static func cacheHitRate(_ rate: Double?) -> String {
        guard let rate else { return "未记录" }
        return rate.formatted(.percent.precision(.fractionLength(1)))
    }

    static func duration(_ milliseconds: Int64) -> String {
        if milliseconds < 1_000 { return "\(milliseconds)ms" }
        return String(format: "%.1fs", Double(milliseconds) / 1_000)
    }

    static func nodeDuration(_ node: ReplyTraceNode) -> String {
        guard let duration = node.duration else { return node.status == .running ? "进行中" : "—" }
        return (node.timing == .estimated ? "≈ " : "") + self.duration(duration)
    }

    static func icon(_ kind: ReplyTraceNodeKind) -> String {
        switch kind {
        case .reply: "bubble.left"
        case .subagent: "person.2"
        case .tool: "wrench.and.screwdriver"
        case .reasoning: "brain"
        case .message: "text.bubble"
        case .usage: "number.circle"
        case .compaction: "arrow.down.right.and.arrow.up.left"
        }
    }

    static func color(_ node: ReplyTraceNode) -> Color {
        if node.status == .failed { return .red }
        if node.status == .interrupted { return .orange }
        return switch node.kind {
        case .tool: CodexVistaTheme.dashboardAccentSecondary
        case .usage: CodexVistaTheme.dashboardInput
        case .reasoning: .purple
        case .subagent: .orange
        default: CodexVistaTheme.dashboardAccent
        }
    }
}
