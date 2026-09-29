import Foundation
import SwiftUI

struct UsageCalendarPanel: View {
    private static let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    let usage: [DailyUsage]
    let calendar: Calendar
    let today: Date
    let isEmbedded: Bool

    @State private var showsWeeks = false
    @State private var displayedMonth: Date
    @State private var selectedUsageID: DailyUsage.ID?
    @State private var selectedLegendLevel: Int?
    @State private var isShowingModelDetails = false

    init(
        usage: [DailyUsage],
        calendar: Calendar = CodexUsageCalendar.utc,
        today: Date = Date(),
        isEmbedded: Bool = false
    ) {
        let model = UsageCalendarModel(usage: usage, calendar: calendar, today: today)
        self.usage = usage
        self.calendar = calendar
        self.today = today
        self.isEmbedded = isEmbedded
        _displayedMonth = State(initialValue: model.latestMonth)
    }

    private var model: UsageCalendarModel {
        UsageCalendarModel(usage: usage, calendar: calendar, today: today)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    }

    var body: some View {
        let month = model.clampedMonth(displayedMonth)
        let cells = model.cells(for: month)
        let weeks = model.weeks(for: month)
        let maximum = showsWeeks ? (weeks.filter { !$0.isFuture }.map(\.usage.total).max() ?? 0) : cells
            .filter { $0.isInDisplayedMonth && !$0.isFuture }
            .compactMap(\.usage?.total)
            .max() ?? 0

        Group {
            if isEmbedded {
                calendarContent(month: month, cells: cells, weeks: weeks, maximum: maximum)
            } else {
                calendarContent(month: month, cells: cells, weeks: weeks, maximum: maximum)
                    .dashboardPanel(padding: 14)
            }
        }
        .onDisappear {
            resetSelection()
        }
        .onChange(of: showsWeeks) { _, _ in
            resetSelection()
        }
        .onChange(of: usage.first?.id) { _, _ in
            displayedMonth = model.clampedMonth(displayedMonth)
        }
    }

    private func calendarContent(
        month: Date,
        cells: [UsageCalendarCell],
        weeks: [UsageCalendarWeek],
        maximum: Int
    ) -> some View {
        VStack(spacing: 7) {
            calendarHeader(month)
            if showsWeeks {
                Text("周一至周日 · UTC · 跨月按整周汇总")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                    .frame(height: 14)
                VStack(spacing: 4) {
                    ForEach(weeks) { week in
                        weekRow(week, maximum: maximum)
                    }
                }
                .frame(height: 182, alignment: .top)
            } else {
                weekdayHeader
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(cells) { cell in
                        dayCell(cell, maximum: maximum)
                    }
                }
            }

            heatLegend(maximum: maximum)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func calendarHeader(_ month: Date) -> some View {
        HStack(spacing: 6) {
            Label("用量日历", systemImage: "calendar")
                .font(CodexVistaTheme.headingFont(size: 14))

            Picker("统计维度", selection: $showsWeeks) {
                Text("日").tag(false)
                Text("周").tag(true)
            }
            .pickerStyle(.segmented)
            .controlSize(.mini)
            .labelsHidden()
            .frame(width: 64)

            Spacer(minLength: 0)

            monthButton(systemImage: "chevron.left", offset: -1, month: month)

            Text(monthTitle(month))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(CodexVistaTheme.dashboardPrimaryText.opacity(0.88))
                .monospacedDigit()
                .frame(minWidth: 72)

            monthButton(systemImage: "chevron.right", offset: 1, month: month)
        }
        .frame(height: 26)
    }

    private func monthButton(systemImage: String, offset: Int, month: Date) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                resetSelection()
                displayedMonth = model.movingMonth(month, by: offset)
            }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(CodexVistaTheme.dashboardMutedText)
        .disabled(!model.canMoveMonth(month, by: offset))
        .opacity(model.canMoveMonth(month, by: offset) ? 1 : 0.32)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Self.weekdays, id: \.self) { weekday in
                Text(weekday)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("星期一到星期日")
    }

    @ViewBuilder
    private func dayCell(_ cell: UsageCalendarCell, maximum: Int) -> some View {
        let level = UsageCalendarModel.intensity(total: cell.usage?.total ?? 0, maximum: maximum)
        let base = Text("\(cell.dayNumber)")
            .font(.system(size: 10, weight: cell.isToday ? .semibold : .medium, design: .rounded))
            .foregroundStyle(dayTextColor(for: cell, level: level))
            .monospacedDigit()
            .frame(maxWidth: .infinity, minHeight: 27, maxHeight: 27)
            .background(
                dayFillColor(for: cell, level: level),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        cell.isToday
                            ? (level >= 3 ? Color.white.opacity(0.94) : CodexVistaTheme.dashboardAccent)
                            : CodexVistaTheme.dashboardBorder.opacity(0.55),
                        lineWidth: cell.isToday ? 1.5 : 0.7
                    )
            }

        if cell.isInDisplayedMonth,
           !cell.isFuture,
           let item = cell.usage {
            Button {
                selectUsage(item.id)
            } label: {
                base.contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
                .buttonStyle(UsageCalendarButtonStyle(isSelected: selectedUsageID == item.id))
                .popover(
                    isPresented: selectionBinding(for: item.id),
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .bottom
                ) {
                    DailyUsageHoverCard(usage: item, dateText: item.id, showsModelDetails: $isShowingModelDetails)
                        .padding(4)
                }
                .accessibilityLabel("\(item.id)，Token \(item.total)")
                .accessibilityHint("点击查看用量明细，点击外部关闭")
        } else {
            base
                .accessibilityLabel(cell.isFuture ? "\(cell.dayNumber)日，未来日期" : "\(cell.dayNumber)日")
        }
    }

    private func weekRow(_ week: UsageCalendarWeek, maximum: Int) -> some View {
        let level = UsageCalendarModel.intensity(total: week.usage.total, maximum: maximum)
        return Button {
            selectUsage(week.id)
        } label: {
            HStack(spacing: 6) {
                Text(week.dateRangeText)
                if week.isCurrentWeek {
                    Text("本周 · 截至今日")
                        .font(.system(size: 8))
                }
                Spacer(minLength: 0)
                Text(week.isFuture ? "未开始" : TokenFormatter.compact(week.usage.total))
                    .fontWeight(.semibold)
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .monospacedDigit()
            .padding(.horizontal, 8)
            .frame(height: 27)
            .foregroundStyle(week.isFuture ? CodexVistaTheme.dashboardMutedText :
                (level == 4 ? CodexVistaTheme.heatmapText : CodexVistaTheme.dashboardPrimaryText))
            .background(level > 0 ? heatColor(level: level) : CodexVistaTheme.dashboardAccent.opacity(0.055),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(week.isCurrentWeek ? CodexVistaTheme.dashboardAccent : CodexVistaTheme.dashboardBorder,
                            lineWidth: week.isCurrentWeek ? 1.5 : 0.7)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(UsageCalendarButtonStyle(isSelected: selectedUsageID == week.id))
        .disabled(week.isFuture)
        .popover(isPresented: selectionBinding(for: week.id), attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            DailyUsageHoverCard(usage: week.usage, dateText: week.detailTitle, showsModelDetails: $isShowingModelDetails)
                .padding(4)
        }
        .accessibilityLabel("\(week.detailTitle)，\(week.isFuture ? "未来日期" : "Token \(week.usage.total)")")
        .accessibilityHint(week.isFuture ? "" : "点击查看周用量明细，点击外部关闭")
    }

    private func resetSelection() {
        selectedUsageID = nil
        selectedLegendLevel = nil
        isShowingModelDetails = false
    }

    private func heatLegend(maximum: Int) -> some View {
        HStack(spacing: 7) {
            Spacer()
            Text("低")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)

            ForEach(1...4, id: \.self) { level in
                Button {
                    resetSelection()
                    selectedLegendLevel = level
                } label: {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(heatColor(level: level))
                        .frame(width: 16, height: 10)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(UsageCalendarButtonStyle(
                        isSelected: selectedLegendLevel == level,
                        cornerRadius: 3
                    ))
                    .popover(
                        isPresented: legendSelectionBinding(for: level),
                        attachmentAnchor: .rect(.bounds),
                        arrowEdge: .bottom
                    ) {
                        UsageHeatLegendHoverCard(
                            level: level,
                            range: UsageCalendarModel.intensityRange(level: level, maximum: maximum),
                            maximum: maximum,
                            unit: showsWeeks ? "周" : "日",
                            color: heatColor(level: level)
                        )
                        .padding(4)
                    }
                    .accessibilityLabel(legendAccessibilityLabel(level: level, maximum: maximum))
                    .accessibilityHint("点击查看用量区间")
            }

            Text("高")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            Spacer()
        }
        .frame(height: 14)
        .accessibilityElement(children: .contain)
    }

    private func dayFillColor(for cell: UsageCalendarCell, level: Int) -> Color {
        guard cell.isInDisplayedMonth else {
            return CodexVistaTheme.dashboardControlBackground.opacity(0.28)
        }
        guard !cell.isFuture else {
            return CodexVistaTheme.dashboardControlBackground.opacity(0.42)
        }
        guard level > 0 else {
            return CodexVistaTheme.dashboardAccent.opacity(0.055)
        }
        return heatColor(level: level)
    }

    private func dayTextColor(for cell: UsageCalendarCell, level: Int) -> Color {
        if !cell.isInDisplayedMonth || cell.isFuture {
            return CodexVistaTheme.dashboardMutedText.opacity(0.48)
        }
        return level == 4 ? CodexVistaTheme.heatmapText : CodexVistaTheme.dashboardPrimaryText
    }

    private func heatColor(level: Int) -> Color {
        CodexVistaTheme.dashboardAccent.opacity(CodexVistaTheme.skin.calendarOpacity(for: level))
    }

    private func selectUsage(_ id: DailyUsage.ID) {
        resetSelection()
        selectedUsageID = id
    }

    private func selectionBinding(for id: DailyUsage.ID) -> Binding<Bool> {
        Binding(
            get: { selectedUsageID == id },
            set: { isPresented in
                if !isPresented, selectedUsageID == id {
                    isShowingModelDetails = false
                    selectedUsageID = nil
                }
            }
        )
    }

    private func legendSelectionBinding(for level: Int) -> Binding<Bool> {
        Binding(
            get: { selectedLegendLevel == level },
            set: { isPresented in
                if !isPresented, selectedLegendLevel == level {
                    selectedLegendLevel = nil
                }
            }
        )
    }

    private func legendAccessibilityLabel(level: Int, maximum: Int) -> String {
        guard let range = UsageCalendarModel.intensityRange(level: level, maximum: maximum) else {
            return "用量等级 \(level)，本月暂无对应区间"
        }
        return "用量等级 \(level)，\(range.lowerBound) 到 \(range.upperBound) Token"
    }

    private func monthTitle(_ month: Date) -> String {
        let components = model.calendar.dateComponents([.year, .month], from: month)
        return "\(components.year ?? 0)年\(components.month ?? 0)月"
    }
}

private struct UsageCalendarButtonStyle: ButtonStyle {
    let isSelected: Bool
    var cornerRadius: CGFloat = 6

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        let isHighlighted = isEnabled && (isHovered || isSelected || configuration.isPressed)
        configuration.label
            .brightness(isEnabled && configuration.isPressed ? -0.08 : 0)
            .overlay {
                // A light inner edge and dark outer edge stay visible on every heatmap color.
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.8), lineWidth: 3)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .inset(by: 1.5)
                        .strokeBorder(Color.white, lineWidth: 1.5)
                }
                    .opacity(isHighlighted ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .onHover { isHovered = $0 }
    }
}

private struct UsageHeatLegendHoverCard: View {
    let level: Int
    let range: ClosedRange<Int>?
    let maximum: Int
    var unit: String = "日"
    let color: Color

    private var rangeText: String {
        guard let range else { return "本月暂无对应区间" }
        if range.lowerBound == range.upperBound {
            return "\(TokenFormatter.compact(range.lowerBound)) Token"
        }
        return "\(TokenFormatter.compact(range.lowerBound)) – \(TokenFormatter.compact(range.upperBound)) Token"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color)
                    .frame(width: 16, height: 10)
                Text("用量区间")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CodexVistaTheme.dashboardPrimaryText)
            }

            Text(rangeText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(CodexVistaTheme.dashboardAccent)
                .monospacedDigit()

            Text(maximum > 0
                 ? "本月\(unit)峰值 \(TokenFormatter.compact(maximum)) · 平衡分级"
                 : "本月暂无 Token 用量")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
        }
        .frame(width: 168, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            CodexVistaTheme.dashboardSurface,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(CodexVistaTheme.dashboardBorder)
        }
        .shadow(color: CodexVistaTheme.dashboardShadow, radius: 7, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("用量等级 \(level)，\(rangeText)")
    }
}
