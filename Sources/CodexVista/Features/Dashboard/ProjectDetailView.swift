import Charts
import SwiftUI

struct ProjectDetailView: View {
    let entry: WorkspaceUsageEntry
    let rank: Int
    let range: ActivityRange
    let onClose: () -> Void
    let onDetailHover: (ProjectDetailHoverItem?) -> Void

    @State private var selectedTab: ProjectDetailTab = .overview
    @State private var conversationSortOrder = ProjectConversationSortOrder.defaultOrder
    @State private var conversationSearchText = ""
    @State private var selectedReplyConversationID: String?
    @State private var hoveredTrendDayID: Int64?

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    projectHeader
                    tabSelector
                    summaryCards

                    switch selectedTab {
                    case .overview:
                        overviewContent
                    case .conversations:
                        conversationDetailList
                    case .replies:
                        replyTable
                    }
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
        .onDisappear {
            onDetailHover(nil)
        }
        .onExitCommand(perform: onClose)
    }

    private var titleBar: some View {
        ZStack {
            HStack(spacing: 8) {
                Image(systemName: "circle.grid.3x3.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText.opacity(0.55))
                Text("项目详情")
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
                .help("关闭项目详情")
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: 40, alignment: .center)
        .background(CodexVistaTheme.dashboardSurfaceOpaque)
        .contentShape(Rectangle())
    }

    private var projectHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "link")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 52, height: 52)
                .background(
                    CodexVistaTheme.brandGradient,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .shadow(color: CodexVistaTheme.dashboardAccent.opacity(0.22), radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(entry.name)
                        .font(.system(size: 21, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("排行 #\(rank)")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(CodexVistaTheme.dashboardAccent)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(
                            CodexVistaTheme.dashboardAccent.opacity(0.09),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(CodexVistaTheme.dashboardAccent.opacity(0.34), lineWidth: 1)
                        }

                    if entry.isInferred {
                        Text("工作目录推测")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(CodexVistaTheme.dashboardInput)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(
                                CodexVistaTheme.dashboardInput.opacity(0.09),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(CodexVistaTheme.dashboardInput.opacity(0.32), lineWidth: 1)
                            }
                            .help("Codex 未记录 workspace_roots；此项目由会话工作目录推测，未与确定项目合并。")
                    }
                }
                Text("\(entry.rootCount) 个根目录 · 最近活动 \(ProjectUsageDateFormatter.relative(lastActivityMilliseconds))")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            }

            Spacer()
        }
        .padding(.horizontal, 2)
    }

    private var summaryCards: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 190), spacing: 10)],
            spacing: 10
        ) {
            metricCard(
                "总 Token",
                value: TokenFormatter.compact(entry.tokens),
                icon: "number.square.fill",
                tint: CodexVistaTheme.dashboardAccent
            )
            metricCard(
                "耗时",
                value: TokenFormatter.compactWorktime(entry.aiWorktimeMilliseconds),
                icon: "stopwatch.fill",
                tint: CodexVistaTheme.dashboardAccentSecondary
            )
            .help(
                "\(range.rawValue)耗时："
                    + TokenFormatter.worktime(entry.aiWorktimeMilliseconds)
            )
            .accessibilityLabel(
                "\(range.rawValue)耗时 "
                    + TokenFormatter.worktime(entry.aiWorktimeMilliseconds)
            )
            metricCard(
                "项目占比",
                value: TokenFormatter.percentage(entry.share),
                icon: "chart.pie.fill",
                tint: CodexVistaTheme.dashboardInput
            )
            metricCard(
                "任务",
                value: "\(visibleConversations.count)",
                icon: "list.bullet.rectangle.fill",
                tint: CodexVistaTheme.dashboardAccentSecondary
            )
            metricCard(
                "回复",
                value: "\(replyRows.count)",
                icon: "ellipsis.bubble.fill",
                tint: CodexVistaTheme.accent
            )
        }
    }

    private func metricCard(
        _ title: String,
        value: String,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
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
        .shadow(color: CodexVistaTheme.dashboardShadow.opacity(0.6), radius: 5, y: 2)
    }

    private var tabSelector: some View {
        HStack(spacing: 28) {
            ForEach(ProjectDetailTab.allCases) { tab in
                Button {
                    onDetailHover(nil)
                    selectedTab = tab
                } label: {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 10.5, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(
                            selectedTab == tab
                                ? CodexVistaTheme.dashboardAccent
                                : CodexVistaTheme.dashboardMutedText
                        )

                        Capsule()
                            .fill(
                                selectedTab == tab
                                    ? CodexVistaTheme.dashboardAccent
                                    : Color.clear
                            )
                            .frame(width: selectedTab == tab ? 34 : 0, height: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
            Spacer()
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CodexVistaTheme.dashboardBorder)
                .frame(height: 1)
        }
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geometry in
                HStack(alignment: .top, spacing: 12) {
                    tokenBreakdownCard
                        .frame(width: max(300, (geometry.size.width - 12) * 0.44))
                    trendCard
                }
            }
            .frame(height: 168)
            workspaceProjectCard
        }
    }

    private var workspaceProjectCard: some View {
        detailCard(title: "关联目录", icon: "folder.fill") {
            VStack(spacing: 0) {
                if entry.directories.isEmpty {
                    Text("未识别到关联目录")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                }
                ForEach(entry.directories) { directory in
                    HStack(spacing: 10) {
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
                    .padding(.horizontal, 12)
                    .frame(minHeight: 42)

                    if directory.id != entry.directories.last?.id {
                        Rectangle()
                            .fill(CodexVistaTheme.dashboardBorder.opacity(0.62))
                            .frame(height: 1)
                            .padding(.leading, 40)
                    }
                }
            }
        }
    }

    private var tokenBreakdownCard: some View {
        detailCard(title: "Token 构成", icon: "chart.bar.xaxis", height: 168) {
            TokenCompositionView(breakdown: projectTokenBreakdown)
                .padding(.top, 2)
        }
    }

    private var trendCard: some View {
        detailCard(title: "近 7 日趋势", icon: "chart.xyaxis.line", height: 168) {
            Chart(entry.dailyUsage) { point in
                AreaMark(
                    x: .value("日期", point.date),
                    y: .value("Token", point.tokens)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            CodexVistaTheme.dashboardAccent.opacity(0.24),
                            CodexVistaTheme.dashboardAccent.opacity(0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("日期", point.date),
                    y: .value("Token", point.tokens)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(CodexVistaTheme.dashboardAccent)
                .lineStyle(
                    StrokeStyle(
                        lineWidth: 2,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                if point.tokens > 0 {
                    PointMark(
                        x: .value("日期", point.date),
                        y: .value("Token", point.tokens)
                    )
                    .foregroundStyle(CodexVistaTheme.dashboardAccent)
                    .symbolSize(18)
                }

                if hoveredTrendDayID == point.id {
                    RuleMark(x: .value("悬停日期", point.date))
                        .foregroundStyle(CodexVistaTheme.dashboardAccent.opacity(0.36))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    PointMark(
                        x: .value("悬停日期", point.date),
                        y: .value("悬停 Token", point.tokens)
                    )
                    .foregroundStyle(CodexVistaTheme.dashboardAccent)
                    .symbolSize(54)
                }
            }
            .chartYScale(domain: 0...trendYAxisMaximum)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                        .foregroundStyle(CodexVistaTheme.dashboardGrid)
                    AxisValueLabel {
                        if let tokens = value.as(Int.self) {
                            Text(TokenFormatter.compact(tokens))
                        }
                    }
                }
            }
            .font(.system(size: 8, weight: .medium, design: .rounded))
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case let .active(location):
                                    guard let plotFrame = proxy.plotFrame else {
                                        hoveredTrendDayID = nil
                                        return
                                    }
                                    let plotRect = geometry[plotFrame]
                                    guard plotRect.contains(location) else {
                                        hoveredTrendDayID = nil
                                        return
                                    }
                                    let plotX = location.x - plotRect.minX
                                    guard let date: Date = proxy.value(atX: plotX) else {
                                        hoveredTrendDayID = nil
                                        return
                                    }
                                    hoveredTrendDayID = entry.dailyUsage.min {
                                        abs($0.date.timeIntervalSince(date))
                                            < abs($1.date.timeIntervalSince(date))
                                    }?.id
                                case .ended:
                                    hoveredTrendDayID = nil
                                }
                            }

                        if
                            let point = hoveredTrendPoint,
                            let plotFrame = proxy.plotFrame,
                            let pointX = proxy.position(forX: point.date)
                        {
                            let plotRect = geometry[plotFrame]
                            let tooltipHalfWidth: CGFloat = 55
                            let tooltipX = min(
                                max(
                                    plotRect.minX + pointX,
                                    plotRect.minX + tooltipHalfWidth
                                ),
                                plotRect.maxX - tooltipHalfWidth
                            )

                            trendTooltip(for: point)
                                .frame(width: tooltipHalfWidth * 2, alignment: .leading)
                                .position(
                                    x: tooltipX,
                                    y: plotRect.minY + 26
                                )
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            .frame(height: 92)
        }
    }

    private func trendTooltip(for point: ProjectDailyUsage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(
                point.date,
                format: .dateTime
                    .month(.defaultDigits)
                    .day(.defaultDigits)
                    .weekday(.abbreviated)
            )
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(CodexVistaTheme.dashboardMutedText)

            Text(TokenFormatter.compact(point.tokens))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()

            Text("7 日占比 \(TokenFormatter.percentage(trendShare(for: point)))")
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            CodexVistaTheme.dashboardSurfaceOpaque,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(CodexVistaTheme.dashboardBorder, lineWidth: 1)
        }
        .shadow(color: CodexVistaTheme.dashboardShadow, radius: 6, y: 2)
    }

    private var conversationDetailList: some View {
        conversationListCard(title: "任务明细", enablesHover: true)
    }

    private func conversationListCard(
        title: String,
        enablesHover: Bool
    ) -> some View {
        detailCard(
            title: title,
            icon: "list.bullet.rectangle",
            titleAccessory: {
                conversationSearchField
            },
            trailing: {
                conversationSortMenu
            }
        ) {
            conversationListContent(enablesHover: enablesHover)
        }
    }

    @ViewBuilder
    private func conversationListContent(enablesHover: Bool) -> some View {
        if sortedConversations.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText.opacity(0.68))
                Text("没有找到匹配的任务")
                    .font(.system(size: 11, weight: .semibold))
                Text("换个关键词试试")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            }
            .frame(maxWidth: .infinity, minHeight: 130)
        } else {
            LazyVStack(spacing: 7) {
                ForEach(Array(sortedConversations.enumerated()), id: \.element.id) {
                    index,
                    conversation in
                    conversationDetailRow(
                        conversation,
                        position: index + 1,
                        enablesHover: enablesHover
                    )
                }
            }
        }
    }

    private func conversationDetailRow(
        _ conversation: ProjectConversationUsage,
        position: Int,
        enablesHover: Bool
    ) -> some View {
        let title = conversation.displayTitle ?? conversation.shortThreadID
        let share = entry.tokens > 0
            ? min(max(Double(conversation.tokens) / Double(entry.tokens), 0), 1)
            : 0

        return HStack(alignment: .center, spacing: 12) {
            Text("\(position)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(CodexVistaTheme.dashboardAccent)
                .monospacedDigit()
                .frame(width: 28, height: 28)
                .background(
                    CodexVistaTheme.dashboardAccent.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CodexVistaTheme.dashboardPrimaryText.opacity(0.91))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    Label(
                        ProjectUsageDateFormatter.relative(
                            conversation.lastMessageAtMilliseconds
                        ),
                        systemImage: "clock"
                    )
                    Label(
                        "\(conversation.replies.count) 次回复",
                        systemImage: "bubble.left"
                    )
                    Label(
                        TokenFormatter.compactWorktime(
                            conversation.aiWorktimeMilliseconds
                        ),
                        systemImage: "stopwatch"
                    )
                    .help(
                        "\(range.rawValue)耗时："
                            + TokenFormatter.worktime(
                                conversation.aiWorktimeMilliseconds
                            )
                    )
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            }

            VStack(alignment: .trailing, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(TokenFormatter.compact(conversation.tokens))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(CodexVistaTheme.dashboardPrimaryText.opacity(0.92))
                        .monospacedDigit()
                    Text("Token")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                }

                HStack(spacing: 7) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(CodexVistaTheme.dashboardControlBackground)
                            Capsule()
                                .fill(CodexVistaTheme.dashboardAccentSecondary)
                                .frame(
                                    width: max(
                                        share > 0 ? 4 : 0,
                                        geometry.size.width * share
                                    )
                                )
                        }
                    }
                    .frame(width: 88, height: 5)

                    Text(TokenFormatter.percentage(share))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
            .frame(width: 158, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(
            CodexVistaTheme.dashboardControlBackground.opacity(0.34),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(CodexVistaTheme.dashboardBorder.opacity(0.72), lineWidth: 1)
        }
        .help(
            (conversation.displayTitle.map {
                "\($0) · 任务标识 \(conversation.shortThreadID)"
            } ?? conversation.shortThreadID)
                + (enablesHover ? " · 点击筛选回复明细" : "")
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(title)，\(conversation.tokens.formatted()) Token，"
                + "\(conversation.replies.count) 次回复，"
                + "\(range.rawValue)耗时 "
                + TokenFormatter.worktime(conversation.aiWorktimeMilliseconds)
        )
        .contentShape(Rectangle())
        .onHover { isHovering in
            guard enablesHover else { return }
            onDetailHover(isHovering ? .conversation(conversation) : nil)
        }
        .onTapGesture {
            guard enablesHover else { return }
            showReplies(for: conversation)
        }
    }

    private var conversationSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            TextField("搜索任务", text: $conversationSearchText)
                .textFieldStyle(.plain)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 9)
        .frame(width: 190, height: 28)
        .background(
            CodexVistaTheme.dashboardControlBackground.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(CodexVistaTheme.dashboardBorder.opacity(0.76), lineWidth: 1)
        }
    }

    private var conversationSortMenu: some View {
        Menu {
            Button {
                conversationSortOrder = .recent
            } label: {
                Label(
                    "按最近活动",
                    systemImage: conversationSortOrder == .recent
                        ? "checkmark.circle.fill"
                        : "clock"
                )
            }
            Button {
                conversationSortOrder = .usage
            } label: {
                Label(
                    "按 Token 用量",
                    systemImage: conversationSortOrder == .usage
                        ? "checkmark.circle.fill"
                        : "number.square"
                )
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                Text(conversationSortOrder == .recent ? "按最近活动" : "按 Token 用量")
                    .foregroundStyle(CodexVistaTheme.dashboardPrimaryText.opacity(0.88))
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                    .frame(width: 16, height: 16)
                    .background(
                        CodexVistaTheme.dashboardSurfaceStrong.opacity(0.72),
                        in: Circle()
                    )
            }
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 132, height: 28)
        .background(
            CodexVistaTheme.dashboardControlBackground.opacity(0.78),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(
                    CodexVistaTheme.dashboardBorder.opacity(0.88),
                    lineWidth: 1
                )
        }
        .shadow(
            color: CodexVistaTheme.dashboardShadow.opacity(0.28),
            radius: 2,
            y: 1
        )
        .help("切换任务排序方式")
    }

    private var replyTable: some View {
        detailCard(
            title: "回复明细",
            icon: "bubble.left.and.text.bubble.right",
            titleAccessory: {
                replyConversationFilter
            },
            trailing: {
                EmptyView()
            }
        ) {
            ProjectReplyDetailList(
                rows: replyRows,
                emptyDescription: selectedReplyConversation == nil
                    ? "该项目还没有可展示的回复"
                    : "该任务还没有可展示的回复"
            ) { row in
                onDetailHover(row.map(ProjectDetailHoverItem.reply))
            }
        }
    }

    @ViewBuilder
    private var replyConversationFilter: some View {
        if let conversation = selectedReplyConversation {
            Button {
                onDetailHover(nil)
                selectedReplyConversationID = nil
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text(conversation.displayTitle ?? conversation.shortThreadID)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(CodexVistaTheme.dashboardAccent)
                .padding(.horizontal, 8)
                .frame(maxWidth: 280, minHeight: 24)
                .background(CodexVistaTheme.dashboardAccent.opacity(0.09), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(CodexVistaTheme.dashboardAccent.opacity(0.30), lineWidth: 1)
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("清除任务筛选，显示全部回复")
            .accessibilityLabel("当前仅显示任务 \(conversation.displayTitle ?? conversation.shortThreadID) 的回复")
            .accessibilityHint("清除筛选并显示全部回复")
        }
    }

    private func showReplies(for conversation: ProjectConversationUsage) {
        onDetailHover(nil)
        selectedReplyConversationID = conversation.id
        withAnimation(.easeOut(duration: 0.16)) {
            selectedTab = .replies
        }
    }

    private func detailCard<Content: View>(
        title: String,
        icon: String,
        height: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        detailCard(
            title: title,
            icon: icon,
            height: height,
            titleAccessory: { EmptyView() },
            trailing: { EmptyView() },
            content: content
        )
    }

    private func detailCard<Trailing: View, Content: View>(
        title: String,
        icon: String,
        height: CGFloat? = nil,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        detailCard(
            title: title,
            icon: icon,
            height: height,
            titleAccessory: { EmptyView() },
            trailing: trailing,
            content: content
        )
    }

    private func detailCard<TitleAccessory: View, Trailing: View, Content: View>(
        title: String,
        icon: String,
        height: CGFloat? = nil,
        @ViewBuilder titleAccessory: () -> TitleAccessory,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CodexVistaTheme.dashboardAccent)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CodexVistaTheme.dashboardPrimaryText.opacity(0.92))
                titleAccessory()
                Spacer()
                trailing()
            }
            content()
        }
        .padding(13)
        .frame(
            maxWidth: .infinity,
            minHeight: height,
            maxHeight: height,
            alignment: .topLeading
        )
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
                Button(action: onClose) {
                    Text("完成")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 78, height: 28)
                        .background(
                            CodexVistaTheme.brandGradient,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color.white.opacity(0.28), lineWidth: 1)
                        }
                        .shadow(
                            color: CodexVistaTheme.dashboardAccent.opacity(0.22),
                            radius: 5,
                            y: 2
                        )
                }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
        }
        .background(CodexVistaTheme.dashboardSurfaceStrong.opacity(0.80))
    }

    private var sortedConversations: [ProjectConversationUsage] {
        let filtered = visibleConversations.filter { conversation in
            guard !conversationSearchText.isEmpty else { return true }
            return (conversation.displayTitle ?? conversation.shortThreadID)
                .localizedCaseInsensitiveContains(conversationSearchText)
                || conversation.shortThreadID.localizedCaseInsensitiveContains(conversationSearchText)
        }
        return conversationSortOrder.sorted(filtered)
    }

    private var replyRows: [ProjectReplyDetailRow] {
        let conversations = selectedReplyConversationID.map { selectedID in
            visibleConversations.filter { $0.id == selectedID }
        } ?? visibleConversations

        return conversations.flatMap { conversation in
            let title = conversation.displayTitle ?? conversation.shortThreadID
            return conversation.replies.map {
                ProjectReplyDetailRow(
                    id: "\(conversation.id)-\($0.id)",
                    conversationTitle: title,
                    reply: $0
                )
            }
        }
        .sorted {
            if $0.reply.displayAtMilliseconds != $1.reply.displayAtMilliseconds {
                return $0.reply.displayAtMilliseconds > $1.reply.displayAtMilliseconds
            }
            return $0.id < $1.id
        }
    }

    private var selectedReplyConversation: ProjectConversationUsage? {
        guard let selectedReplyConversationID else { return nil }
        return visibleConversations.first { $0.id == selectedReplyConversationID }
    }

    private var visibleConversations: [ProjectConversationUsage] {
        entry.visibleConversations
    }

    private var projectTokenBreakdown: TokenBreakdown {
        let totals = entry.conversations
            .flatMap(\.replies)
            .reduce(into: (input: 0, cached: 0, output: 0, reasoning: 0)) { result, reply in
                result.input += reply.uncachedInputTokens
                result.cached += reply.cachedInputTokens
                result.output += reply.visibleOutputTokens
                result.reasoning += reply.reasoningTokens
            }
        return TokenBreakdown(input: totals.input, cachedInput: totals.cached,
                              output: totals.output, reasoning: totals.reasoning)
    }

    private var lastActivityMilliseconds: Int64? {
        entry.lastVisibleActivityAtMilliseconds
    }

    private var trendYAxisMaximum: Int {
        max(1, Int(Double(entry.dailyUsage.map(\.tokens).max() ?? 0) * 1.08))
    }

    private var hoveredTrendPoint: ProjectDailyUsage? {
        guard let hoveredTrendDayID else { return nil }
        return entry.dailyUsage.first { $0.id == hoveredTrendDayID }
    }

    private func trendShare(for point: ProjectDailyUsage) -> Double {
        let total = entry.dailyUsage.reduce(0) { $0 + $1.tokens }
        guard total > 0 else { return 0 }
        return Double(point.tokens) / Double(total)
    }
}

struct ProjectReplyDetailList: View {
    let rows: [ProjectReplyDetailRow]
    let emptyDescription: String
    let onHover: (ProjectReplyDetailRow?) -> Void

    var body: some View {
        if rows.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText.opacity(0.68))
                Text("暂无回复记录")
                    .font(.system(size: 11, weight: .semibold))
                Text(emptyDescription)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            }
            .frame(maxWidth: .infinity, minHeight: 130)
        } else {
            LazyVStack(spacing: 7) {
                ForEach(rows) { row in
                    replyRow(row)
                }
            }
        }
    }

    private func replyRow(_ row: ProjectReplyDetailRow) -> some View {
        let status = ProjectReplyPresentation.status(row.reply.status)
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: ProjectReplyPresentation.icon(row.reply.status))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(status.color)
                .frame(width: 30, height: 30)
                .background(
                    status.color.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 7) {
                Text(row.conversationTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CodexVistaTheme.dashboardPrimaryText.opacity(0.91))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    Label(
                        ProjectUsageDateFormatter.replyTime(
                            row.reply.displayAtMilliseconds
                        ),
                        systemImage: "clock"
                    )

                    Text(status.title)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(status.color)
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(status.color.opacity(0.09), in: Capsule())

                    Label(
                        ProjectReplyPresentation.modelText(row.reply.model),
                        systemImage: "cpu"
                    )
                    .lineLimit(1)
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            }

            VStack(alignment: .trailing, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(TokenFormatter.compact(row.reply.totalTokens))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(CodexVistaTheme.dashboardPrimaryText.opacity(0.92))
                        .monospacedDigit()
                    Text("Token")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                }

                HStack(spacing: 7) {
                    Label(
                        ProjectUsageDateFormatter.duration(
                            row.reply.aiWorktimeMilliseconds
                        ),
                        systemImage: "stopwatch"
                    )
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                    .monospacedDigit()

                    replyActivityMetric(
                        title: "Skill",
                        count: row.reply.skillCallCount,
                        icon: "sparkles",
                        tint: CodexVistaTheme.dashboardInput
                    )
                    replyActivityMetric(
                        title: "工具",
                        count: row.reply.toolCallCount,
                        icon: "wrench.and.screwdriver.fill",
                        tint: CodexVistaTheme.dashboardAccentSecondary
                    )
                }
            }
            .frame(width: 210, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(
            CodexVistaTheme.dashboardControlBackground.opacity(0.34),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(CodexVistaTheme.dashboardBorder.opacity(0.72), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(row.conversationTitle)，状态 \(status.title)，"
                + "\(row.reply.totalTokens.formatted()) Token，耗时 "
                + TokenFormatter.worktime(row.reply.aiWorktimeMilliseconds)
        )
        .contentShape(Rectangle())
        .onHover { isHovering in
            onHover(isHovering ? row : nil)
        }
    }

    private func replyActivityMetric(
        title: String,
        count: Int,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 7.5, weight: .semibold))
            Text("\(title) \(count)")
                .monospacedDigit()
        }
        .font(.system(size: 8.5, weight: .semibold))
        .foregroundStyle(count > 0 ? tint : CodexVistaTheme.dashboardMutedText.opacity(0.72))
        .padding(.horizontal, 6)
        .frame(height: 20)
        .background(
            (count > 0 ? tint : CodexVistaTheme.dashboardMutedText).opacity(0.08),
            in: Capsule()
        )
    }
}

struct ProjectReplyHoverCard: View {
    let row: ProjectReplyDetailRow

    var body: some View {
        let status = ProjectReplyPresentation.status(row.reply.status)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: ProjectReplyPresentation.icon(row.reply.status))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(status.color)
                    .frame(width: 30, height: 30)
                    .background(status.color.opacity(0.10), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("回复调用详情")
                        .font(.system(size: 13, weight: .semibold))
                    Text(
                        ProjectUsageDateFormatter.replyTime(
                            row.reply.displayAtMilliseconds
                        )
                    )
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                    .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text(status.title)
                        .foregroundStyle(status.color)
                        .padding(.horizontal, 9)
                        .frame(height: 23)
                        .background(status.color.opacity(0.09), in: Capsule())
                    Label(
                        ProjectUsageDateFormatter.duration(
                            row.reply.aiWorktimeMilliseconds
                        ),
                        systemImage: "stopwatch"
                    )
                    .foregroundStyle(CodexVistaTheme.dashboardAccentSecondary)
                    .padding(.horizontal, 9)
                    .frame(height: 23)
                    .background(
                        CodexVistaTheme.dashboardAccentSecondary.opacity(0.09),
                        in: Capsule()
                    )
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "状态 \(status.title)，耗时 "
                        + TokenFormatter.worktime(row.reply.aiWorktimeMilliseconds)
                )
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("模型调用", systemImage: "cpu")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(CodexVistaTheme.dashboardAccent)
                Spacer(minLength: 8)
                Text(ProjectReplyPresentation.modelText(row.reply.model))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(CodexVistaTheme.dashboardPrimaryText.opacity(0.90))
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(
                CodexVistaTheme.dashboardAccent.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )

            ProjectTokenCostEstimateCard(
                tokenBreakdown: TokenBreakdown(
                    input: row.reply.uncachedInputTokens,
                    cachedInput: row.reply.cachedInputTokens,
                    output: row.reply.visibleOutputTokens,
                    reasoning: row.reply.reasoningTokens
                ),
                costBreakdown: row.reply.estimatedCostBreakdown,
                unpricedModelCount: row.reply.unpricedModelCount,
                referencePricedModelCount: row.reply.referencePricedModelCount,
                contextName: "本次回复",
                excludedTokenCount: 0
            )

            HStack(spacing: 9) {
                hoverSummary(
                    title: "Skills",
                    count: row.reply.skillCallCount,
                    icon: "sparkles",
                    tint: CodexVistaTheme.dashboardInput
                )
                hoverSummary(
                    title: "Tools",
                    count: row.reply.toolCallCount,
                    icon: "wrench.and.screwdriver.fill",
                    tint: CodexVistaTheme.dashboardAccentSecondary
                )
            }

            Divider()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    activitySection(
                        title: "Skills 调用",
                        icon: "sparkles",
                        tint: CodexVistaTheme.dashboardInput,
                        calls: row.reply.skillCalls
                    )
                    activitySection(
                        title: "Tools 调用",
                        icon: "wrench.and.screwdriver.fill",
                        tint: CodexVistaTheme.dashboardAccentSecondary,
                        calls: row.reply.toolCalls
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 110, maxHeight: 420)
            .scrollIndicators(.visible)
        }
        .padding(16)
        .frame(width: 410)
        .background(
            CodexVistaTheme.dashboardSurfaceOpaque,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CodexVistaTheme.dashboardBorder, lineWidth: 1)
        }
        .foregroundStyle(CodexVistaTheme.dashboardPrimaryText)
    }

    private func hoverSummary(
        title: String,
        count: Int,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            Spacer(minLength: 0)
            Text("\(count) 次")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 38)
        .background(
            tint.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private func activitySection(
        title: String,
        icon: String,
        tint: Color,
        calls: [ProjectReplyActivityCall]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint)

            if calls.isEmpty {
                Text("本次回复未调用")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            } else {
                ForEach(calls) { call in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(tint.opacity(0.72))
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)
                        Text(call.name)
                            .font(.system(size: 10, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Text("\(call.count) 次")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                            .monospacedDigit()
                            .padding(.top, 1)
                    }
                    .frame(minHeight: 20)
                }
            }
        }
    }
}

private enum ProjectDetailTab: String, CaseIterable, Identifiable {
    case overview = "概览"
    case conversations = "任务明细"
    case replies = "回复明细"

    var id: Self { self }

    var icon: String {
        switch self {
        case .overview: "rectangle.grid.2x2.fill"
        case .conversations: "list.bullet.rectangle"
        case .replies: "bubble.left.and.text.bubble.right"
        }
    }
}

struct ProjectReplyDetailRow: Identifiable {
    let id: String
    let conversationTitle: String
    let reply: ProjectReplyUsage
}

enum ProjectDetailHoverItem {
    case conversation(ProjectConversationUsage)
    case reply(ProjectReplyDetailRow)
}


private extension ProjectDailyUsage {
    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(dayStartMilliseconds) / 1_000)
    }
}

enum ProjectUsageDateFormatter {
    static func relative(_ milliseconds: Int64?) -> String {
        guard let milliseconds else { return "时间未知" }
        let date = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "'今天' HH:mm" : "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    static func replyTime(_ milliseconds: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm:ss" : "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    static func duration(_ milliseconds: Int64?) -> String {
        guard let milliseconds else { return "—" }
        if milliseconds < 1_000 { return "\(milliseconds)ms" }
        let seconds = Double(milliseconds) / 1_000
        if seconds < 60 { return String(format: "%.1fs", seconds) }
        return String(format: "%dm%02ds", Int(seconds) / 60, Int(seconds) % 60)
    }
}

enum ProjectReplyPresentation {
    static func modelText(_ model: String) -> String {
        model.isEmpty ? "模型未知" : model
    }

    static func status(
        _ status: ProjectReplyUsageStatus
    ) -> (title: String, color: Color) {
        switch status {
        case .completed: ("完成", .green)
        case .interrupted: ("中断", .orange)
        case .rolledBack: ("回滚", .orange)
        case .inProgress: ("进行中", CodexVistaTheme.dashboardAccent)
        case .unknown: ("未知", CodexVistaTheme.dashboardMutedText)
        }
    }

    static func icon(_ status: ProjectReplyUsageStatus) -> String {
        switch status {
        case .completed: "checkmark"
        case .interrupted: "exclamationmark"
        case .rolledBack: "arrow.uturn.backward"
        case .inProgress: "ellipsis"
        case .unknown: "questionmark"
        }
    }
}
