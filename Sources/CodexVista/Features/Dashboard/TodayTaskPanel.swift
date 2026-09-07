import AppKit
import SwiftUI

struct TodayTaskPanel: View {
    let ranking: WorkspaceUsageRanking

    @State private var selectedTaskID: TodayTaskUsageEntry.ID?
    @State private var detailWindowController: ProjectDetailWindowController?

    var body: some View {
        ZStack {
            panelContent

            if detailWindowController != nil {
                Color.black.opacity(0.12)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                    .allowsHitTesting(true)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            CodexVistaTheme.dashboardSurfaceStrong.opacity(0.74),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CodexVistaTheme.dashboardBorder, lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.14), value: detailWindowController != nil)
        .onChange(of: ranking.entries) { _, _ in
            guard let selectedTaskID else { return }
            guard
                let task = tasks.first(where: { $0.id == selectedTaskID }),
                let detailWindowController
            else {
                dismissTaskDetail()
                return
            }
            detailWindowController.update(task: task)
        }
        .onDisappear {
            dismissTaskDetail()
        }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Rectangle()
                .fill(CodexVistaTheme.dashboardBorder)
                .frame(height: 1)

            if tasks.isEmpty {
                emptyState
            } else {
                tableHeader
                taskList
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CodexVistaTheme.dashboardAccent)
                .frame(width: 24, height: 24)
                .background(
                    CodexVistaTheme.dashboardAccent.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("今日任务")
                    .font(.system(size: 13, weight: .semibold))
                Text("进行中的任务优先 · 悬浮查看用量，点击打开详情")
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            }

            Spacer()

            headerMetric("任务", value: "\(tasks.count)")
            headerSeparator
            headerMetric("进行中", value: "\(runningTaskCount)")
            headerSeparator
            headerMetric("今日 Token", value: TokenFormatter.compact(ranking.totalTokens))
            headerSeparator
            headerMetric(
                "耗时",
                value: TokenFormatter.compactWorktime(ranking.totalAIWorktimeMilliseconds)
            )
        }
        .frame(height: 42)
        .padding(.horizontal, 12)
    }

    private var tableHeader: some View {
        taskColumns(
            status: "状态",
            task: "任务名",
            workspace: "所属项目",
            lastUpdated: "最后更新",
            replies: "回复",
            aiWorktime: "耗时",
            aiWorktimeHelp: "今日回复生命周期累计耗时",
            tokens: "今日 Token",
            action: "操作",
            isHeader: true
        )
        .padding(.horizontal, 12)
        .background(CodexVistaTheme.dashboardControlBackground.opacity(0.36))
    }

    private var taskList: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(tasks) { task in
                    TodayTaskHoverRow(
                        task: task,
                        isEnabled: detailWindowController == nil,
                        onOpen: { presentTaskDetail(task) }
                    ) {
                        taskRow(task)
                    }

                    if task.id != tasks.last?.id {
                        Rectangle()
                            .fill(CodexVistaTheme.dashboardBorder.opacity(0.62))
                            .frame(height: 1)
                            .padding(.leading, 64)
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .scrollIndicators(.visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "今日暂无任务",
            systemImage: "checklist",
            description: Text("今天产生 Token 用量的任务会显示在这里。")
        )
        .foregroundStyle(CodexVistaTheme.dashboardMutedText)
    }

    private func taskRow(_ task: TodayTaskUsageEntry) -> some View {
        let status = ProjectReplyPresentation.status(task.status)
        return taskColumns(
            status: status.title,
            task: task.title,
            workspace: task.workspace.name,
            lastUpdated: ProjectUsageDateFormatter.relative(task.lastUpdatedAtMilliseconds),
            replies: "\(task.conversation.replies.count)",
            aiWorktime: TokenFormatter.compactWorktime(task.aiWorktimeMilliseconds),
            aiWorktimeHelp: "今日耗时："
                + TokenFormatter.worktime(task.aiWorktimeMilliseconds),
            tokens: TokenFormatter.compact(task.conversation.tokens),
            action: "查看详情",
            isHeader: false,
            statusColor: status.color,
            statusIcon: ProjectReplyPresentation.icon(task.status),
            isSelected: selectedTaskID == task.id
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(task.title)，所属项目 \(task.workspace.name)，"
                + "状态 \(status.title)，今日 "
                + "\(TokenFormatter.compact(task.conversation.tokens)) Token，"
                + "耗时 \(TokenFormatter.worktime(task.aiWorktimeMilliseconds))，"
                + "\(task.conversation.replies.count) 次回复"
        )
        .accessibilityHint("悬浮查看回复数、总耗时、模型和 Skills / Tools 用量，点击打开今日任务详情窗口")
    }

    private func taskColumns(
        status: String,
        task: String,
        workspace: String,
        lastUpdated: String,
        replies: String,
        aiWorktime: String,
        aiWorktimeHelp: String,
        tokens: String,
        action: String,
        isHeader: Bool,
        statusColor: Color = CodexVistaTheme.dashboardMutedText,
        statusIcon: String? = nil,
        isSelected: Bool = false
    ) -> some View {
        let font: Font = isHeader
            ? .system(size: 9, weight: .semibold)
            : .system(size: 10.5, weight: .medium)
        let textColor = isHeader
            ? CodexVistaTheme.dashboardMutedText
            : CodexVistaTheme.dashboardPrimaryText.opacity(0.88)

        return HStack(spacing: 10) {
            HStack(spacing: 5) {
                if let statusIcon {
                    Image(systemName: statusIcon)
                        .font(.system(size: 8.5, weight: .semibold))
                }
                Text(status)
                    .lineLimit(1)
            }
            .foregroundStyle(isHeader ? textColor : statusColor)
            .frame(width: 70, alignment: .leading)

            HStack(spacing: 7) {
                if !isHeader {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(CodexVistaTheme.dashboardAccentSecondary)
                }
                Text(task)
                    .font(isHeader ? font : .system(size: 10.5, weight: .semibold))
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            .frame(minWidth: 190, maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                if !isHeader {
                    Image(systemName: "square.grid.3x3.topleft.filled")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(CodexVistaTheme.dashboardAccentSecondary)
                }
                Text(workspace)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: 154, alignment: .leading)

            Text(lastUpdated)
                .monospacedDigit()
                .frame(width: 88, alignment: .leading)

            Text(replies)
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)

            Text(aiWorktime)
                .font(
                    isHeader
                        ? font
                        : .system(size: 10.5, weight: .semibold, design: .rounded)
                )
                .foregroundStyle(
                    isHeader ? textColor : CodexVistaTheme.dashboardAccentSecondary
                )
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(width: 68, alignment: .trailing)
                .help(aiWorktimeHelp)

            Text(tokens)
                .font(isHeader ? font : .system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 78, alignment: .trailing)

            HStack(spacing: 3) {
                Text(action)
                if !isHeader {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                }
            }
            .foregroundStyle(isHeader ? textColor : CodexVistaTheme.dashboardAccent)
            .frame(width: 68, alignment: .trailing)
        }
        .font(font)
        .foregroundStyle(textColor)
        .frame(maxWidth: .infinity, minHeight: isHeader ? 26 : 50)
        .padding(.horizontal, 6)
        .background(
            isSelected ? CodexVistaTheme.dashboardAccent.opacity(0.09) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }

    private var tasks: [TodayTaskUsageEntry] {
        ranking.todayTasks
    }

    private var runningTaskCount: Int {
        tasks.filter { $0.status == .inProgress }.count
    }

    private var headerSeparator: some View {
        Rectangle()
            .fill(CodexVistaTheme.dashboardBorder)
            .frame(width: 1, height: 14)
    }

    private func headerMetric(_ title: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            Text(value)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(CodexVistaTheme.dashboardAccent)
                .monospacedDigit()
        }
    }

    @MainActor
    private func presentTaskDetail(_ task: TodayTaskUsageEntry) {
        guard detailWindowController == nil,
              let parentWindow = NSApp.mainWindow ?? NSApp.keyWindow
        else { return }
        selectedTaskID = task.id
        let controller = ProjectDetailWindowController(
            task: task,
            parentWindow: parentWindow
        ) {
            detailWindowController = nil
            selectedTaskID = nil
        }
        detailWindowController = controller
        controller.show()
    }

    @MainActor
    private func dismissTaskDetail() {
        detailWindowController?.dismiss()
        detailWindowController = nil
        selectedTaskID = nil
    }
}

private struct TodayTaskHoverRow<Content: View>: View {
    let task: TodayTaskUsageEntry
    let isEnabled: Bool
    let onOpen: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isPresented = false
    @State private var isRowHovered = false
    @State private var isCardHovered = false
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        Button {
            closePopover()
            onOpen()
        } label: {
            content()
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering in
            isRowHovered = hovering
            updatePresentation()
        }
        .popover(
            isPresented: Binding(
                get: { isPresented },
                set: { if !$0 { closePopover() } }
            ),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .trailing
        ) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("今日用量 · 总耗时为今日回复累计耗时")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    ProjectConversationHoverCard(conversation: task.conversation)
                }
            }
            .frame(maxHeight: 620)
            .onHover { hovering in
                isCardHovered = hovering
                updatePresentation()
            }
            .onExitCommand(perform: closePopover)
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { closePopover() }
        }
        .onDisappear(perform: closePopover)
    }

    private func updatePresentation() {
        dismissTask?.cancel()
        guard isEnabled else {
            closePopover()
            return
        }
        if isRowHovered || isCardHovered {
            isPresented = true
        } else {
            // Allow the pointer to cross the gap between the row and its popover.
            dismissTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, !isRowHovered, !isCardHovered else { return }
                closePopover()
            }
        }
    }

    private func closePopover() {
        dismissTask?.cancel()
        dismissTask = nil
        isPresented = false
        isRowHovered = false
        isCardHovered = false
    }
}

struct TodayTaskDetailView: View {
    let task: TodayTaskUsageEntry
    let onClose: () -> Void
    let onReplyHover: (ProjectReplyDetailRow?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    taskHeader
                    summaryCards
                    tokenBreakdownCard
                    workspaceDirectoryCard
                    replyDetailCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.visible)

            footer
        }
        .frame(minWidth: 720, minHeight: 520)
        .ignoresSafeArea(.container, edges: .top)
        .background { CodexVistaBackdrop() }
        .foregroundStyle(CodexVistaTheme.dashboardPrimaryText)
        .onDisappear { onReplyHover(nil) }
        .onExitCommand(perform: onClose)
    }

    private var titleBar: some View {
        ZStack {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText.opacity(0.55))
                Text("今日任务详情")
                    .font(.system(size: 12, weight: .semibold))
            }

            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("关闭今日任务详情")
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(CodexVistaTheme.dashboardSurfaceOpaque)
        .contentShape(Rectangle())
    }

    private var taskHeader: some View {
        let status = ProjectReplyPresentation.status(task.status)
        return HStack(spacing: 14) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 52, height: 52)
                .background(
                    CodexVistaTheme.brandGradient,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .shadow(color: CodexVistaTheme.dashboardAccent.opacity(0.22), radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.system(size: 20, weight: .semibold))
                    .lineLimit(2)
                    .truncationMode(.tail)

                HStack(spacing: 8) {
                    Label(task.workspace.name, systemImage: "square.grid.3x3.topleft.filled")
                    Label(
                        ProjectUsageDateFormatter.relative(task.lastUpdatedAtMilliseconds),
                        systemImage: "clock"
                    )
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            }

            Spacer()

            Label(status.title, systemImage: ProjectReplyPresentation.icon(task.status))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(status.color)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(status.color.opacity(0.09), in: Capsule())
                .overlay { Capsule().stroke(status.color.opacity(0.28), lineWidth: 1) }
        }
        .padding(.horizontal, 2)
    }

    private var summaryCards: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 10
        ) {
            metricCard(
                "今日 Token",
                value: TokenFormatter.compact(task.conversation.tokens),
                icon: "number.square.fill",
                tint: CodexVistaTheme.dashboardAccent
            )
            metricCard(
                "耗时",
                value: TokenFormatter.compactWorktime(task.aiWorktimeMilliseconds),
                icon: "stopwatch.fill",
                tint: CodexVistaTheme.dashboardAccentSecondary
            )
            .help(
                "今日耗时："
                    + TokenFormatter.worktime(task.aiWorktimeMilliseconds)
            )
            .accessibilityLabel(
                "今日耗时 "
                    + TokenFormatter.worktime(task.aiWorktimeMilliseconds)
            )
            metricCard(
                "回复数",
                value: "\(task.conversation.replies.count)",
                icon: "bubble.left.and.text.bubble.right.fill",
                tint: CodexVistaTheme.accent
            )
            metricCard(
                "相关目录",
                value: "\(task.workspace.directories.count)",
                icon: "folder.fill",
                tint: CodexVistaTheme.dashboardAccentSecondary
            )
        }
    }

    private func metricCard(_ title: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 66)
        .background(
            CodexVistaTheme.dashboardTile.opacity(0.82),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(CodexVistaTheme.dashboardBorder, lineWidth: 1)
        }
    }

    private var tokenBreakdownCard: some View {
        detailCard(title: "Token 用量构成", icon: "chart.bar.xaxis") {
            VStack(alignment: .leading, spacing: 9) {
                GeometryReader { geometry in
                    HStack(spacing: 1) {
                        ForEach(tokenSegments) { segment in
                            segment.color
                                .frame(width: segmentBarWidth(segment, available: geometry.size.width))
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 8)
                .background(CodexVistaTheme.dashboardControlBackground, in: Capsule())

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 7
                ) {
                    ForEach(tokenSegments) { segment in
                        HStack(spacing: 7) {
                            Circle().fill(segment.color).frame(width: 7, height: 7)
                            Text(segment.title)
                                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                            Spacer()
                            Text(TokenFormatter.compact(segment.value))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                            Text(TokenFormatter.percentage(segment.share))
                                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                                .monospacedDigit()
                                .frame(width: 42, alignment: .trailing)
                        }
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    }
                }

                if task.unattributedTokens > 0 {
                    Label(
                        "另有 \(TokenFormatter.compact(task.unattributedTokens)) Token 无法归属到具体回复",
                        systemImage: "info.circle"
                    )
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                }
            }
        }
    }

    private var workspaceDirectoryCard: some View {
        detailCard(title: "项目相关目录", icon: "folder.fill") {
            if task.workspace.directories.isEmpty {
                Text("未识别到相关目录")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(task.workspace.directories) { directory in
                        HStack(spacing: 9) {
                            Image(systemName: "folder")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(CodexVistaTheme.dashboardAccentSecondary)
                                .frame(width: 18)
                            Text(directory.name)
                                .font(.system(size: 10.5, weight: .semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(directory.name)
                            Spacer()
                        }
                        .frame(minHeight: 38)

                        if directory.id != task.workspace.directories.last?.id {
                            Rectangle()
                                .fill(CodexVistaTheme.dashboardBorder.opacity(0.62))
                                .frame(height: 1)
                                .padding(.leading, 28)
                        }
                    }
                }
            }
        }
    }

    private var replyDetailCard: some View {
        detailCard(title: "回复明细", icon: "bubble.left.and.text.bubble.right") {
            ProjectReplyDetailList(
                rows: replyRows,
                emptyDescription: "该任务今天还没有可展示的回复"
            ) { row in
                onReplyHover(row)
            }
        }
    }

    private func detailCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CodexVistaTheme.dashboardPrimaryText.opacity(0.92))
            content()
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            CodexVistaTheme.dashboardTile.opacity(0.86),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(CodexVistaTheme.dashboardBorder, lineWidth: 1)
        }
        .shadow(color: CodexVistaTheme.dashboardShadow.opacity(0.52), radius: 6, y: 2)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(CodexVistaTheme.dashboardBorder)
                .frame(height: 1)
            HStack {
                Spacer()
                Button("完成", action: onClose)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 78, height: 28)
                    .background(CodexVistaTheme.brandGradient, in: RoundedRectangle(cornerRadius: 7))
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
        }
        .background(CodexVistaTheme.dashboardSurfaceStrong.opacity(0.80))
    }

    private var replyRows: [ProjectReplyDetailRow] {
        task.conversation.replies.map { reply in
            ProjectReplyDetailRow(
                id: "\(task.id)-\(reply.id)",
                conversationTitle: task.title,
                reply: reply
            )
        }
        .sorted {
            if $0.reply.displayAtMilliseconds != $1.reply.displayAtMilliseconds {
                return $0.reply.displayAtMilliseconds > $1.reply.displayAtMilliseconds
            }
            return $0.id < $1.id
        }
    }

    private var tokenSegments: [TodayTaskTokenSegment] {
        let breakdown = task.tokenBreakdown
        let total = max(breakdown.total, 1)
        return [
            TodayTaskTokenSegment(
                id: "input", title: "输入", value: breakdown.input,
                share: Double(breakdown.input) / Double(total),
                color: CodexVistaTheme.dashboardInput
            ),
            TodayTaskTokenSegment(
                id: "cached", title: "缓存输入", value: breakdown.cachedInput,
                share: Double(breakdown.cachedInput) / Double(total),
                color: CodexVistaTheme.dashboardCachedInput
            ),
            TodayTaskTokenSegment(
                id: "output", title: "输出", value: breakdown.output,
                share: Double(breakdown.output) / Double(total),
                color: CodexVistaTheme.output
            ),
            TodayTaskTokenSegment(
                id: "reasoning", title: "推理", value: breakdown.reasoning,
                share: Double(breakdown.reasoning) / Double(total),
                color: CodexVistaTheme.reasoning
            )
        ]
    }

    private func segmentBarWidth(
        _ segment: TodayTaskTokenSegment,
        available: CGFloat
    ) -> CGFloat {
        guard segment.value > 0 else { return 0 }
        return max(3, (available - 3) * segment.share)
    }
}

private struct TodayTaskTokenSegment: Identifiable {
    let id: String
    let title: String
    let value: Int
    let share: Double
    let color: Color
}
