import SwiftUI

struct ActivityRankingPanel: View {
    let ranking: ActivityRanking
    @State private var hoveredSkillID: ActivityRankingEntry.ID?
    @State private var pinnedSkillID: ActivityRankingEntry.ID?

    var body: some View {
        HStack(spacing: 12) {
            rankingList(
                title: "Skills 排行",
                systemImage: "sparkles",
                entries: ranking.skills
            )
            rankingList(
                title: "Tools 排行",
                systemImage: "hammer",
                entries: ranking.tools
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func rankingList(
        title: String,
        systemImage: String,
        entries: [ActivityRankingEntry]
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CodexVistaTheme.dashboardAccent)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("调用次数")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            }
            .frame(height: 28)
            .padding(.horizontal, 12)

            Rectangle()
                .fill(CodexVistaTheme.dashboardBorder)
                .frame(height: 1)

            if entries.isEmpty {
                compactEmptyState(title: title)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            rankingRow(
                                entry,
                                rank: index + 1,
                                maximum: entries.first?.count ?? 0
                            )
                            if index < entries.count - 1 {
                                Rectangle()
                                    .fill(CodexVistaTheme.dashboardBorder.opacity(0.72))
                                    .frame(height: 1)
                                    .padding(.leading, 38)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .scrollIndicators(.visible)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    }

    private func rankingRow(
        _ entry: ActivityRankingEntry,
        rank: Int,
        maximum: Int
    ) -> some View {
        Button {
            guard !entry.details.isEmpty else { return }
            pinnedSkillID = pinnedSkillID == entry.id ? nil : entry.id
        } label: {
            HStack(spacing: 10) {
                Text("\(rank)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(entry.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(CodexVistaTheme.dashboardPrimaryText)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        if !entry.details.isEmpty {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(CodexVistaTheme.dashboardAccent)
                        }
                        Spacer(minLength: 0)
                        Text("\(entry.count) 次")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .fixedSize()
                    }
                    GeometryReader { geometry in
                        Capsule().fill(CodexVistaTheme.dashboardControlBackground)
                            .overlay(alignment: .leading) {
                                Capsule().fill(CodexVistaTheme.dashboardAccent)
                                    .frame(width: barWidth(available: geometry.size.width, count: entry.count, maximum: maximum))
                            }
                    }
                    .frame(height: 4)
                }
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 29)
        .contentShape(Rectangle())
        .onHover { isHovered in
            guard !entry.details.isEmpty, pinnedSkillID == nil else { return }
            if isHovered {
                hoveredSkillID = entry.id
            } else if hoveredSkillID == entry.id {
                hoveredSkillID = nil
            }
        }
        .popover(
            isPresented: hoverBinding(for: entry),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            VStack(alignment: .trailing, spacing: 6) {
                Button(pinnedSkillID == entry.id ? "关闭明细" : "固定明细") {
                    if pinnedSkillID == entry.id {
                        pinnedSkillID = nil
                        hoveredSkillID = nil
                    } else { pinnedSkillID = entry.id }
                }
                .buttonStyle(.plain)
                .foregroundStyle(CodexVistaTheme.dashboardAccent)
                SkillBreakdownPopover(entry: entry)
            }
            .padding(8)
        }
        .help(
            entry.details.isEmpty
                ? entry.name
                : "点击或悬浮查看 \(entry.name) 的细分 Skill 用量"
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(rank) 名，\(entry.name)，调用 \(entry.count) 次")
        .accessibilityHint(
            entry.details.isEmpty
                ? ""
                : "按下可查看 \(entry.details.count) 个细分 Skill"
        )
    }

    private func compactEmptyState(title: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(CodexVistaTheme.dashboardAccent.opacity(0.62))
            Text("暂无调用记录")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("\(title)暂无调用记录")
    }

    private func barWidth(available: CGFloat, count: Int, maximum: Int) -> CGFloat {
        guard maximum > 0, count > 0 else { return 0 }
        return max(5, available * CGFloat(count) / CGFloat(maximum))
    }

    private func hoverBinding(for entry: ActivityRankingEntry) -> Binding<Bool> {
        Binding(
            get: { !entry.details.isEmpty && (hoveredSkillID == entry.id || pinnedSkillID == entry.id) },
            set: { isPresented in
                if !isPresented {
                    if hoveredSkillID == entry.id { hoveredSkillID = nil }
                    if pinnedSkillID == entry.id { pinnedSkillID = nil }
                }
            }
        )
    }
}

private struct SkillBreakdownPopover: View {
    let entry: ActivityRankingEntry

    private var maximum: Int {
        entry.details.map(\.count).max() ?? 0
    }

    private var listHeight: CGFloat {
        min(max(CGFloat(entry.details.count) * 34, 34), 272)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(CodexVistaTheme.dashboardAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(entry.details.count) 个细分 Skill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                }
                Spacer(minLength: 12)
                Text("\(entry.count) 次")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            Rectangle()
                .fill(CodexVistaTheme.dashboardBorder)
                .frame(height: 1)

            ScrollView(.vertical) {
                LazyVStack(spacing: 8) {
                    ForEach(entry.details) { detail in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(detail.name)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help("\(entry.name):\(detail.name)")
                                Spacer(minLength: 8)
                                Text("\(detail.count) 次")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                            }

                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(CodexVistaTheme.dashboardControlBackground)
                                    Capsule()
                                        .fill(CodexVistaTheme.dashboardAccent)
                                        .frame(
                                            width: maximum > 0
                                                ? geometry.size.width
                                                    * CGFloat(detail.count)
                                                    / CGFloat(maximum)
                                                : 0
                                        )
                                }
                            }
                            .frame(height: 4)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(detail.name)，调用 \(detail.count) 次")
                    }
                }
            }
            .scrollIndicators(entry.details.count > 8 ? .visible : .hidden)
            .frame(height: listHeight)
        }
        .padding(12)
        .frame(width: 270)
        .background {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            shape
                .fill(CodexVistaTheme.dashboardSurfaceStrong)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CodexVistaTheme.dashboardBorder)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(entry.name) 细分 Skill 用量")
    }
}
