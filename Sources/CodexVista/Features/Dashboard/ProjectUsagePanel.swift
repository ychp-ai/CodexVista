import AppKit
import SwiftUI

struct ProjectUsagePanel: View {
    let ranking: WorkspaceUsageRanking
    let range: ActivityRange

    @State private var searchText = ""
    @State private var selectedWorkspaceID: WorkspaceUsageEntry.ID?
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
        .onChange(of: ranking.entries) { _, entries in
            guard let selectedWorkspaceID else { return }
            guard
                let index = entries.firstIndex(where: { $0.id == selectedWorkspaceID }),
                let detailWindowController
            else {
                dismissProjectDetail()
                return
            }
            detailWindowController.update(
                entry: entries[index],
                rank: index + 1,
                range: range
            )
        }
        .onDisappear {
            dismissProjectDetail()
        }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Rectangle()
                .fill(CodexVistaTheme.dashboardBorder)
                .frame(height: 1)

            if ranking.entries.isEmpty {
                emptyState
            } else {
                tableHeader
                projectList
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("项目用量排行", systemImage: "chart.bar.fill")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 12)
                headerMetadata
            }
            projectSearchField
        }
        .padding(12)
    }

    private var projectSearchField: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            TextField("搜索项目或目录", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 9)
        .frame(width: 240, height: 28)
        .background(
            CodexVistaTheme.dashboardControlBackground.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(CodexVistaTheme.dashboardBorder.opacity(0.76), lineWidth: 1)
        }
    }

    private var headerMetadata: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .center, spacing: 4) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(CodexVistaTheme.dashboardAccent)
                Text("Token 用量")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            }

            headerSeparator

            headerMetric("项目", value: "\(ranking.workspaceCount)")

            headerSeparator

            headerMetric("目录", value: "\(ranking.projectCount)")

            headerSeparator

            headerMetric("Token", value: TokenFormatter.compact(ranking.totalTokens))

            headerSeparator

            headerMetric(
                "耗时",
                value: TokenFormatter.compactWorktime(ranking.totalAIWorktimeMilliseconds)
            )
        }
        .padding(.horizontal, 9)
        .frame(height: 26, alignment: .center)
        .background(
            CodexVistaTheme.dashboardControlBackground.opacity(0.46),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(CodexVistaTheme.dashboardBorder.opacity(0.62), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "按 Token 用量排序，\(ranking.workspaceCount) 个项目，"
                + "\(ranking.projectCount) 个目录，\(ranking.totalTokens.formatted()) Token，"
                + "\(range.rawValue)耗时 "
                + TokenFormatter.worktime(ranking.totalAIWorktimeMilliseconds)
        )
        .help(
            "\(range.rawValue)耗时："
                + TokenFormatter.worktime(ranking.totalAIWorktimeMilliseconds)
        )
    }

    private var headerSeparator: some View {
        Rectangle()
            .fill(CodexVistaTheme.dashboardBorder)
            .frame(width: 1, height: 14)
    }

    private var tableHeader: some View {
        projectColumns(
            rank: "排名",
            project: "项目 / 目录",
            projectSummary: nil,
            lastActivity: "最后活动",
            conversations: "任务",
            replies: "回复",
            aiWorktime: "耗时",
            aiWorktimeHelp: "所选范围内回复生命周期累计耗时",
            share: "项目占比",
            tokens: "Token",
            action: "操作",
            isHeader: true
        )
        .padding(.horizontal, 12)
        .background(CodexVistaTheme.dashboardControlBackground.opacity(0.36))
    }

    private var projectList: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                if filteredEntries.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity, minHeight: 170)
                        .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                } else {
                    ForEach(filteredEntries) { rankedEntry in
                        Button {
                            presentProjectDetail(rankedEntry.entry, rank: rankedEntry.rank)
                        } label: {
                            projectRow(rankedEntry.entry, rank: rankedEntry.rank)
                        }
                        .buttonStyle(.plain)
                        .disabled(detailWindowController != nil)

                        if rankedEntry.entry.id != filteredEntries.last?.entry.id {
                            Rectangle()
                                .fill(CodexVistaTheme.dashboardBorder.opacity(0.62))
                                .frame(height: 1)
                                .padding(.leading, 44)
                        }
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
            "暂无项目用量",
            systemImage: "square.grid.3x3.topleft.filled",
            description: Text("使用 Codex 后会按项目汇总任务与回复的 Token 用量。")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .foregroundStyle(CodexVistaTheme.dashboardMutedText)
    }

    private func projectRow(_ entry: WorkspaceUsageEntry, rank: Int) -> some View {
        projectColumns(
            rank: "\(rank)",
            project: projectDisplayName(entry),
            projectSummary: projectSummary(entry),
            lastActivity: lastActivityText(for: entry),
            conversations: "\(entry.visibleConversations.count)",
            replies: "\(entry.visibleReplyCount)",
            aiWorktime: TokenFormatter.compactWorktime(entry.aiWorktimeMilliseconds),
            aiWorktimeHelp: "\(range.rawValue)耗时："
                + TokenFormatter.worktime(entry.aiWorktimeMilliseconds),
            share: TokenFormatter.percentage(entry.share),
            tokens: TokenFormatter.compact(entry.tokens),
            action: "查看详情",
            isHeader: false,
            shareValue: entry.share,
            isSelected: selectedWorkspaceID == entry.id
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(projectAccessibilityLabel(entry, rank: rank))
        .accessibilityHint("打开项目详情窗口")
    }

    private func projectColumns(
        rank: String,
        project: String,
        projectSummary: String?,
        lastActivity: String,
        conversations: String,
        replies: String,
        aiWorktime: String,
        aiWorktimeHelp: String,
        share: String,
        tokens: String,
        action: String,
        isHeader: Bool,
        shareValue: Double = 0,
        isSelected: Bool = false
    ) -> some View {
        let font: Font = isHeader
            ? .system(size: 12, weight: .semibold)
            : .system(size: 12, weight: .medium)
        let textColor = isHeader
            ? CodexVistaTheme.dashboardMutedText
            : CodexVistaTheme.dashboardPrimaryText.opacity(0.88)

        return HStack(spacing: 8) {
            Text(rank)
                .font(
                    isHeader
                        ? font
                        : .system(size: 10, weight: .semibold, design: .rounded)
                )
                .foregroundStyle(
                    isHeader || Int(rank, radix: 10) ?? 4 > 3
                        ? textColor
                        : CodexVistaTheme.dashboardAccent
                )
                .frame(width: 28, alignment: .center)

            HStack(spacing: 7) {
                if !isHeader {
                    Image(systemName: "square.grid.3x3.topleft.filled")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(CodexVistaTheme.dashboardAccentSecondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(project)
                        .help(project)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let projectSummary {
                        Text(projectSummary)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .frame(minWidth: 170, maxWidth: .infinity, alignment: .leading)

            Text(lastActivity)
                .monospacedDigit()
                .frame(width: 76, alignment: .leading)

            Text(conversations)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)

            Text(replies)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)

            Text(aiWorktime)
                .font(
                    isHeader
                        ? font
                        : .system(size: 12, weight: .semibold, design: .rounded)
                )
                .foregroundStyle(
                    isHeader ? textColor : CodexVistaTheme.dashboardAccentSecondary
                )
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(width: 72, alignment: .trailing)
                .help(aiWorktimeHelp)

            HStack(spacing: 7) {
                if isHeader {
                    Spacer(minLength: 0)
                } else {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(CodexVistaTheme.dashboardControlBackground)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            CodexVistaTheme.dashboardAccent,
                                            CodexVistaTheme.dashboardAccentSecondary
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(4, geometry.size.width * shareValue))
                        }
                        .frame(height: 5)
                        .frame(maxHeight: .infinity)
                    }
                }
                Text(share)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .frame(width: 60, alignment: .trailing)
            }
            .frame(width: 92)

            Text(tokens)
                .font(
                    isHeader
                        ? font
                        : .system(size: 12, weight: .semibold, design: .rounded)
                )
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)

            HStack(spacing: 3) {
                Text(action)
                if !isHeader {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                }
            }
            .foregroundStyle(isHeader ? textColor : CodexVistaTheme.dashboardAccent)
            .frame(width: 64, alignment: .trailing)
        }
        .font(font)
        .foregroundStyle(textColor)
        .frame(maxWidth: .infinity, minHeight: isHeader ? 24 : 44)
        .padding(.horizontal, 6)
        .background(
            isSelected ? CodexVistaTheme.dashboardAccent.opacity(0.09) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }

    private var filteredEntries: [RankedProjectUsageEntry] {
        ranking.entries.enumerated().compactMap { index, entry in
            let matchesProject = entry.directories.contains { directory in
                directory.name.localizedCaseInsensitiveContains(searchText)
            }
            guard searchText.isEmpty
                    || projectDisplayName(entry).localizedCaseInsensitiveContains(searchText)
                    || matchesProject else {
                return nil
            }
            return RankedProjectUsageEntry(entry: entry, rank: index + 1)
        }
    }

    @MainActor
    private func presentProjectDetail(_ entry: WorkspaceUsageEntry, rank: Int) {
        guard detailWindowController == nil, let parentWindow = NSApp.keyWindow else { return }
        selectedWorkspaceID = entry.id

        let controller = ProjectDetailWindowController(
            entry: entry,
            rank: rank,
            range: range,
            parentWindow: parentWindow
        ) {
            detailWindowController = nil
            selectedWorkspaceID = nil
        }
        detailWindowController = controller
        controller.show()
    }

    @MainActor
    private func dismissProjectDetail() {
        detailWindowController?.dismiss()
        detailWindowController = nil
        selectedWorkspaceID = nil
    }

    private func projectDisplayName(_ entry: WorkspaceUsageEntry) -> String {
        let baseName = entry.isInferred ? "\(entry.name)（推测）" : entry.name
        guard ranking.entries.filter({ $0.name == entry.name }).count > 1 else {
            return baseName
        }
        return "\(baseName) · \(entry.id.prefix(4))"
    }

    private func projectSummary(_ entry: WorkspaceUsageEntry) -> String {
        if !entry.configuredDirectories.isEmpty {
            let names = entry.configuredDirectories.prefix(3).map(\.name).joined(separator: " · ")
            let suffix = entry.configuredDirectories.count > 3 ? " 等" : ""
            return "\(entry.rootCount) 个根目录 · \(names)\(suffix)"
        }
        let names = entry.directories.prefix(3).map(\.name).joined(separator: " · ")
        let suffix = entry.directories.count > 3 ? " 等 \(entry.directories.count) 个目录" : ""
        let usageSummary = names.isEmpty ? "未识别目录" : names + suffix
        let inference = entry.isInferred ? "工作目录推测 · " : ""
        guard entry.rootCount > 0 else { return inference + usageSummary }
        return "\(inference)\(entry.rootCount) 个根目录 · 工作目录 \(usageSummary)"
    }

    private func lastActivityText(for entry: WorkspaceUsageEntry) -> String {
        ProjectUsageDateFormatter.relative(entry.lastVisibleActivityAtMilliseconds)
    }

    private func projectAccessibilityLabel(_ entry: WorkspaceUsageEntry, rank: Int) -> String {
        return "第 \(rank) 名项目，\(projectDisplayName(entry))，"
            + "\(TokenFormatter.compact(entry.tokens)) Token，"
            + "\(range.rawValue)耗时 "
            + "\(TokenFormatter.worktime(entry.aiWorktimeMilliseconds))，"
            + "占比 \(TokenFormatter.percentage(entry.share))，"
            + (entry.isInferred ? "由工作目录推测，" : "")
            + "\(entry.directories.count) 个目录，\(entry.visibleConversations.count) 个任务，"
            + "\(entry.visibleReplyCount) 次回复"
    }

    private func headerMetric(_ title: String, value: String) -> some View {
        HStack(alignment: .center, spacing: 5) {
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(CodexVistaTheme.dashboardAccent)
                .monospacedDigit()
        }
    }
}

private struct RankedProjectUsageEntry: Identifiable {
    let entry: WorkspaceUsageEntry
    let rank: Int

    var id: WorkspaceUsageEntry.ID { entry.id }
}
