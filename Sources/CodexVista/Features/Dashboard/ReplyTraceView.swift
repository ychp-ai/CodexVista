import AppKit
import SwiftUI

@MainActor
final class ReplyTraceWindowController: NSWindowController, NSWindowDelegate {
    static let shared = ReplyTraceWindowController()
    private var parentCloseObserver: NSObjectProtocol?

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1_040, height: 670),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        super.init(window: panel)
        panel.title = "回复调用链"
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 880, height: 560)
        panel.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(row: ProjectReplyDetailRow) {
        guard let window else { return }
        let parent = NSApp.keyWindow === window ? window.parent : NSApp.keyWindow
        detachParent()
        window.contentViewController = NSHostingController(rootView: CodexVistaAppearanceContainer {
            ReplyTraceView(row: row, onClose: { [weak self] in self?.close() }).id(row.id)
        })
        window.level = parent?.level ?? .normal
        if let parent {
            parent.addChildWindow(window, ordered: .above)
            parentCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: parent, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            }
        }
        let visible = (parent?.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_200, height: 800)
        let size = NSSize(width: min(1_040, visible.width - 32), height: min(694, visible.height - 32))
        window.setFrame(NSRect(
            x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
            width: size.width, height: size.height
        ), display: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        detachParent()
        window?.contentViewController = nil
    }

    private func detachParent() {
        if let parentCloseObserver {
            NotificationCenter.default.removeObserver(parentCloseObserver)
            self.parentCloseObserver = nil
        }
        if let window { window.parent?.removeChildWindow(window) }
    }
}

struct ReplyTraceView: View {
    let row: ProjectReplyDetailRow
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var trace: ReplyTrace?
    @State private var isLoading = true
    @State private var error: String?
    @State private var reload = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.title2)
                    .foregroundStyle(CodexVistaTheme.dashboardAccent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("回复调用链").font(.system(size: 17, weight: .semibold))
                    Text(row.conversationTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                        .lineLimit(1)
                }
                Spacer()
                Button { reload += 1 } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    .disabled(isLoading)
                    .keyboardShortcut("r", modifiers: .command)
                Button("完成") { if let onClose { onClose() } else { dismiss() } }.keyboardShortcut(.cancelAction)
            }
            .padding(20)
            Divider()
            if isLoading {
                ProgressView("正在读取本地调用记录…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                ContentUnavailableView {
                    Label("调用链暂不可用", systemImage: "exclamationmark.bubble")
                } description: { Text(error) } actions: {
                    Button("重新加载") { reload += 1 }
                }
            } else if let trace {
                ReplyTraceContent(trace: trace, totalTokens: row.reply.totalTokens)
            }
        }
        .foregroundStyle(CodexVistaTheme.dashboardPrimaryText)
        .background(CodexVistaTheme.dashboardBackground)
        .frame(minWidth: 860, idealWidth: 1_040, minHeight: 520, idealHeight: 670)
        .task(id: reload) {
            isLoading = true
            error = nil
            do {
                trace = try await ReplyTraceService.shared.load(reply: row.reply)
                try Task.checkCancellation()
                isLoading = false
            } catch is CancellationError {
                // The window closed or a newer refresh superseded this load.
            } catch {
                self.error = (error as? ReplyTraceError)?.errorDescription ?? "读取失败，请稍后重试。"
                isLoading = false
            }
        }
    }
}

struct ReplyTraceContent: View {
    let trace: ReplyTrace
    let totalTokens: Int
    @State private var selection: String?
    @State private var search = ""
    @State private var filter = TraceFilter.all
    @State private var collapsed = Set<String>()
    @State private var showsInspector = false
    @State private var showsSlowTools = false
    @State private var timelineRevealRequest = 0
    @FocusState private var timelineIsFocused: Bool

    private enum TraceFilter: String, CaseIterable, Identifiable {
        case all = "全部", tools = "工具", usage = "Token", failures = "失败"
        var id: Self { self }
    }

    private var selected: ReplyTraceNode? {
        trace.nodes.first { $0.id == selection } ?? trace.nodes.first
    }

    private var visibleRows: [(node: ReplyTraceNode, depth: Int, hasChildren: Bool)] {
        let children = Dictionary(grouping: trace.nodes, by: { $0.parentID ?? "" })
        let byID = Dictionary(uniqueKeysWithValues: trace.nodes.map { ($0.id, $0) })
        let filtering = filter != .all || !search.isEmpty
        var included = Set<String>()
        for node in trace.nodes {
            let matchesFilter = switch filter {
            case .all: true
            case .tools: node.kind == .tool
            case .usage: node.kind == .usage
            case .failures: node.status == .failed
            }
            guard matchesFilter, search.isEmpty || node.name.localizedCaseInsensitiveContains(search) else { continue }
            var ancestor: ReplyTraceNode? = node
            while let current = ancestor, included.insert(current.id).inserted {
                ancestor = current.parentID.flatMap { byID[$0] }
            }
        }
        var result: [(ReplyTraceNode, Int, Bool)] = []
        func append(_ parent: String, depth: Int) {
            guard depth < 25 else { return }
            for node in children[parent] ?? [] where included.contains(node.id) {
                let hasChildren = children[node.id]?.isEmpty == false
                result.append((node, depth, hasChildren))
                if filtering || !collapsed.contains(node.id) { append(node.id, depth: depth + 1) }
            }
        }
        append("", depth: 0)
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                metric("记录跨度", value: ReplyTraceFormat.duration(trace.end - trace.start))
                Spacer(minLength: 0)
                metric("首 Token 延迟", value: trace.root?.timeToFirstTokenMilliseconds.map(ReplyTraceFormat.duration) ?? "未记录")
                    .help("Codex 记录的本次回复首 Token 延迟，不代表每次模型请求的延迟。")
                Spacer(minLength: 0)
                metric("推理强度", value: trace.root?.reasoningEffort?.rawValue ?? "未记录")
                    .help("本次主回复的推理强度配置；子代理节点按各自回复的配置展示。")
                Spacer(minLength: 0)
                metric("链路缓存命中率", value: ReplyTraceFormat.cacheHitRate(trace.cacheHitRate))
                    .help("已加载的主回复及子代理用量记录：缓存输入 ÷ 总输入。记录不完整时仅代表已加载部分。")
                Spacer()
                metric("回复总 Token", value: TokenFormatter.compact(totalTokens))
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            Divider()
            HStack {
                Picker("节点筛选", selection: $filter) {
                    ForEach(TraceFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 250)
                Button { showsSlowTools.toggle() } label: {
                    Label("慢工具排行", systemImage: "timer")
                }
                .popover(isPresented: $showsSlowTools, arrowEdge: .bottom) {
                    ReplyTraceSlowTools(nodes: trace.slowestTools, traceStart: trace.start) { node in
                        search = ""
                        filter = .all
                        collapsed.removeAll()
                        selection = node.id
                        timelineRevealRequest += 1
                        showsInspector = true
                        showsSlowTools = false
                        timelineIsFocused = true
                    }
                }
                Spacer()
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("筛选节点名称", text: $search).textFieldStyle(.plain).frame(width: 160)
                Toggle(isOn: $showsInspector) { Label("节点详情", systemImage: "sidebar.right") }
                    .toggleStyle(.button)
                    .help("显示或隐藏所选节点的详情")
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            GeometryReader { geometry in
                HSplitView {
                    timeline.frame(minWidth: 560)
                    if showsInspector, let selected {
                        ReplyTraceInspector(node: selected, traceStart: trace.start)
                            .frame(minWidth: 230, idealWidth: 260, maxWidth: 300)
                    }
                }
                .onAppear { showsInspector = geometry.size.width >= 960 }
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("\(trace.nodes.count) 个节点 · \(trace.toolCount) 次工具调用 · \(trace.failureCount) 个失败节点")
                Text("仅展示本地元数据 · ≈ 表示估算时间 · 圆点表示单点记录 · 层级由回复与代理关系重建")
                if !trace.notices.isEmpty {
                    Text(trace.notices.joined(separator: " ")).foregroundStyle(CodexVistaTheme.dashboardMutedText)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
    }

    private var timeline: some View {
        VStack(spacing: 0) {
            HStack {
                Text("节点 / 耗时").frame(width: 265, alignment: .leading)
                Text("0s")
                Spacer()
                Text(ReplyTraceFormat.duration(trace.end - trace.start))
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            .padding(.horizontal, 14).frame(height: 30)
            Divider()
            if visibleRows.isEmpty {
                ContentUnavailableView("没有匹配节点", systemImage: "line.3.horizontal.decrease.circle")
            } else {
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(visibleRows, id: \.node.id) { entry in
                                HStack(spacing: 0) {
                                    HStack(spacing: 5) {
                                        if entry.hasChildren {
                                            Button {
                                                if !collapsed.insert(entry.node.id).inserted { collapsed.remove(entry.node.id) }
                                            } label: {
                                                Image(systemName: collapsed.contains(entry.node.id) ? "chevron.right" : "chevron.down")
                                                    .font(.system(size: 8, weight: .bold)).frame(width: 12)
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel(collapsed.contains(entry.node.id) ? "展开子节点" : "收起子节点")
                                        } else { Color.clear.frame(width: 12, height: 1) }
                                        Image(systemName: ReplyTraceFormat.icon(entry.node.kind))
                                            .foregroundStyle(ReplyTraceFormat.color(entry.node))
                                        Text(entry.node.name).lineLimit(1).help(entry.node.name)
                                        Spacer(minLength: 4)
                                        Text(ReplyTraceFormat.nodeDuration(entry.node))
                                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                                    }
                                    .font(.system(size: 11))
                                    .padding(.leading, CGFloat(min(entry.depth, 5)) * 12)
                                    .padding(.trailing, 12)
                                    .frame(width: 265)
                                    ReplyTraceBar(node: entry.node, trace: trace)
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .background(selected?.id == entry.node.id ? CodexVistaTheme.dashboardAccent.opacity(0.10) : .clear)
                                .contentShape(Rectangle())
                                .onTapGesture { selection = entry.node.id; timelineIsFocused = true }
                                .accessibilityElement(children: .contain)
                                .accessibilityLabel("\(entry.node.name)，\(entry.node.status.title)，\(ReplyTraceFormat.nodeDuration(entry.node))")
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { selection = entry.node.id; timelineIsFocused = true }
                                .id(entry.node.id)
                            }
                        }
                    }
                    .focusable()
                    .focused($timelineIsFocused)
                    .onChange(of: selection) { _, id in
                        if let id { reader.scrollTo(id, anchor: .center) }
                    }
                    .onChange(of: timelineRevealRequest, initial: true) { _, _ in
                        if let selection { reader.scrollTo(selection, anchor: .center) }
                    }
                    .onMoveCommand { direction in
                        let rows = visibleRows
                        guard !rows.isEmpty else { return }
                        let index = rows.firstIndex { $0.node.id == selected?.id } ?? 0
                        switch direction {
                        case .up: selection = rows[max(0, index - 1)].node.id
                        case .down: selection = rows[min(rows.count - 1, index + 1)].node.id
                        case .left: collapsed.insert(rows[index].node.id)
                        case .right: collapsed.remove(rows[index].node.id)
                        default: break
                        }
                        if let selection { reader.scrollTo(selection) }
                    }
                }
            }
        }
        .background(CodexVistaTheme.dashboardSurface.opacity(0.35))
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 10)).foregroundStyle(CodexVistaTheme.dashboardMutedText)
            Text(value).font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
        }
    }
}

private struct ReplyTraceSlowTools: View {
    let nodes: [ReplyTraceNode]
    let traceStart: Int64
    let onSelect: (ReplyTraceNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("慢工具排行").font(.headline)
            Text("当前链路耗时最长的 5 次工具调用，点击定位节点。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if nodes.isEmpty {
                Text("尚无完整工具耗时记录")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 70)
            } else {
                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    Button { onSelect(node) } label: {
                        HStack(spacing: 10) {
                            Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary).frame(width: 16)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(node.name).lineLimit(1).foregroundStyle(CodexVistaTheme.dashboardPrimaryText)
                                Text("+\(ReplyTraceFormat.duration(max(0, node.startedAt - traceStart))) · \(node.status.title)")
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Text(ReplyTraceFormat.nodeDuration(node)).monospacedDigit()
                                .foregroundStyle(ReplyTraceFormat.color(node))
                            Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                        .font(.system(size: 12))
                        .padding(.vertical, 7).padding(.horizontal, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("定位到 \(node.name)，\(ReplyTraceFormat.nodeDuration(node))")
                }
            }
            Text("包含已记录与估算耗时（≈）；单点和进行中的调用不参与排名。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(18).frame(width: 380)
    }
}

private struct ReplyTraceBar: View {
    let node: ReplyTraceNode
    let trace: ReplyTrace

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width - 8)
            let offset = min(1, max(0, Double(node.startedAt - trace.start) / Double(trace.duration))) * width
            let span = min(width - offset, max(4, Double(node.duration ?? 0) / Double(trace.duration) * width))
            ZStack(alignment: .leading) {
                HStack {
                    ForEach(0..<5) { _ in Rectangle().fill(CodexVistaTheme.dashboardBorder.opacity(0.5)).frame(width: 1); Spacer(minLength: 0) }
                }
                if node.timing == .point || node.endedAt == nil {
                    Circle().fill(ReplyTraceFormat.color(node)).frame(width: 7, height: 7).offset(x: offset)
                } else {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(ReplyTraceFormat.color(node).opacity(node.timing == .estimated ? 0.45 : 0.8))
                        .frame(width: max(3, span), height: 12)
                        .offset(x: offset)
                }
            }
            .frame(height: proxy.size.height)
        }
        .help("\(node.status.title) · \(node.timing.title)")
    }
}

private struct ReplyTraceInspector: View {
    let node: ReplyTraceNode
    let traceStart: Int64

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(node.kind.title, systemImage: ReplyTraceFormat.icon(node.kind))
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(ReplyTraceFormat.color(node))
                Text(node.name).font(.system(size: 15, weight: .semibold)).textSelection(.enabled)
                field("状态", node.status.title)
                field("耗时", ReplyTraceFormat.nodeDuration(node))
                field("时间来源", node.timing.title)
                field("相对开始", "+\(ReplyTraceFormat.duration(max(0, node.startedAt - traceStart)))")
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
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
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

private enum ReplyTraceFormat {
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
