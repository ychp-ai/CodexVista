import Foundation
import SwiftUI

struct UsageCalendarCell: Identifiable {
    let id: String
    let date: Date
    let dayNumber: Int
    let isInDisplayedMonth: Bool
    let isFuture: Bool
    let isToday: Bool
    let usage: DailyUsage?
}

struct UsageCalendarModel {
    let calendar: Calendar
    let today: Date
    let earliestMonth: Date
    let latestMonth: Date

    private let usageByID: [String: DailyUsage]

    init(usage: [DailyUsage], calendar: Calendar = .current, today: Date = Date()) {
        var normalizedCalendar = calendar
        normalizedCalendar.firstWeekday = 2
        self.calendar = normalizedCalendar
        self.today = normalizedCalendar.startOfDay(for: today)

        var indexedUsage: [String: DailyUsage] = [:]
        for item in usage {
            indexedUsage[item.id] = item
        }
        usageByID = indexedUsage

        let currentMonth = Self.monthStart(for: today, calendar: normalizedCalendar)
        latestMonth = currentMonth
        let earliestUsageDate = usage
            .filter { $0.total > 0 }
            .compactMap { Self.date(forID: $0.id, calendar: normalizedCalendar) }
            .min()
        let candidate = earliestUsageDate.map {
            Self.monthStart(for: $0, calendar: normalizedCalendar)
        } ?? currentMonth
        earliestMonth = min(candidate, currentMonth)
    }

    func cells(for month: Date) -> [UsageCalendarCell] {
        let displayedMonth = clampedMonth(month)
        let weekday = calendar.component(.weekday, from: displayedMonth)
        let leadingDays = (weekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(
            byAdding: .day,
            value: -leadingDays,
            to: displayedMonth
        ) else {
            return []
        }

        let displayedComponents = calendar.dateComponents([.year, .month], from: displayedMonth)
        return (0..<42).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
                return nil
            }
            let day = calendar.startOfDay(for: date)
            let components = calendar.dateComponents([.year, .month, .day], from: day)
            guard let dayNumber = components.day else { return nil }
            let id = Self.dayID(for: day, calendar: calendar)
            return UsageCalendarCell(
                id: id,
                date: day,
                dayNumber: dayNumber,
                isInDisplayedMonth: components.year == displayedComponents.year
                    && components.month == displayedComponents.month,
                isFuture: calendar.compare(day, to: today, toGranularity: .day) == .orderedDescending,
                isToday: calendar.isDate(day, inSameDayAs: today),
                usage: usageByID[id]
            )
        }
    }

    func clampedMonth(_ month: Date) -> Date {
        let start = Self.monthStart(for: month, calendar: calendar)
        return min(max(start, earliestMonth), latestMonth)
    }

    func movingMonth(_ month: Date, by offset: Int) -> Date {
        guard let candidate = calendar.date(
            byAdding: .month,
            value: offset,
            to: Self.monthStart(for: month, calendar: calendar)
        ) else {
            return clampedMonth(month)
        }
        return clampedMonth(candidate)
    }

    func canMoveMonth(_ month: Date, by offset: Int) -> Bool {
        let current = Self.monthStart(for: month, calendar: calendar)
        guard let candidate = calendar.date(byAdding: .month, value: offset, to: current) else {
            return false
        }
        return candidate >= earliestMonth && candidate <= latestMonth
    }

    static func intensity(total: Int, maximum: Int) -> Int {
        guard total > 0, maximum > 0 else { return 0 }
        let normalized = sqrt(Double(total) / Double(maximum))
        switch normalized {
        case ..<0.25: return 1
        case ..<0.50: return 2
        case ..<0.75: return 3
        default: return 4
        }
    }

    static func intensityRange(level: Int, maximum: Int) -> ClosedRange<Int>? {
        guard (1...4).contains(level), maximum > 0 else { return nil }

        func firstTotal(atLeast targetLevel: Int) -> Int {
            var lower = 1
            var upper = maximum
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if intensity(total: middle, maximum: maximum) >= targetLevel {
                    upper = middle
                } else {
                    lower = middle + 1
                }
            }
            return lower
        }

        let lowerBound = firstTotal(atLeast: level)
        guard intensity(total: lowerBound, maximum: maximum) == level else {
            return nil
        }

        let upperBound = level == 4
            ? maximum
            : firstTotal(atLeast: level + 1) - 1
        guard lowerBound <= upperBound else { return nil }
        return lowerBound...upperBound
    }

    static func date(forID id: String, calendar: Calendar) -> Date? {
        let parts = id.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        guard let date = calendar.date(from: components) else { return nil }
        return calendar.startOfDay(for: date)
    }

    static func monthStart(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        var startComponents = DateComponents()
        startComponents.calendar = calendar
        startComponents.timeZone = calendar.timeZone
        startComponents.year = components.year
        startComponents.month = components.month
        startComponents.day = 1
        startComponents.hour = 12
        let midday = calendar.date(from: startComponents) ?? date
        return calendar.startOfDay(for: midday)
    }

    private static func dayID(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

struct UsageCalendarPanel: View {
    private static let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    let usage: [DailyUsage]
    let calendar: Calendar
    let today: Date
    let isEmbedded: Bool

    @State private var displayedMonth: Date
    @State private var hoveredUsageID: DailyUsage.ID?
    @State private var hoverDismissTask: Task<Void, Never>?
    @State private var hoveredLegendLevel: Int?

    init(
        usage: [DailyUsage],
        calendar: Calendar = .current,
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
        let maximum = cells
            .filter { $0.isInDisplayedMonth && !$0.isFuture }
            .compactMap(\.usage?.total)
            .max() ?? 0

        Group {
            if isEmbedded {
                calendarContent(month: month, cells: cells, maximum: maximum)
            } else {
                calendarContent(month: month, cells: cells, maximum: maximum)
                    .dashboardPanel(padding: 14)
            }
        }
        .onChange(of: usage.first?.id) { _, _ in
            displayedMonth = model.clampedMonth(displayedMonth)
        }
    }

    private func calendarContent(
        month: Date,
        cells: [UsageCalendarCell],
        maximum: Int
    ) -> some View {
        VStack(spacing: 7) {
            calendarHeader(month)
            weekdayHeader

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(cells) { cell in
                    dayCell(cell, maximum: maximum)
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

            Spacer(minLength: 4)

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
                hoveredUsageID = nil
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
            base
                .onHover { active in
                    updateUsageHover(active, id: item.id)
                }
                .popover(
                    isPresented: hoverBinding(for: item.id),
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .bottom
                ) {
                    DailyUsageHoverCard(usage: item, dateText: item.id)
                        .padding(4)
                        .onHover { updateUsageHover($0, id: item.id) }
                }
                .accessibilityLabel("\(item.id)，Token \(item.total)")
        } else {
            base
                .accessibilityLabel(cell.isFuture ? "\(cell.dayNumber)日，未来日期" : "\(cell.dayNumber)日")
        }
    }

    private func heatLegend(maximum: Int) -> some View {
        HStack(spacing: 7) {
            Spacer()
            Text("低")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)

            ForEach(1...4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(heatColor(level: level))
                    .frame(width: 16, height: 10)
                    .contentShape(Rectangle())
                    .onHover { active in
                        if active {
                            hoveredLegendLevel = level
                        } else if hoveredLegendLevel == level {
                            hoveredLegendLevel = nil
                        }
                    }
                    .popover(
                        isPresented: legendHoverBinding(for: level),
                        attachmentAnchor: .rect(.bounds),
                        arrowEdge: .bottom
                    ) {
                        UsageHeatLegendHoverCard(
                            level: level,
                            range: UsageCalendarModel.intensityRange(level: level, maximum: maximum),
                            maximum: maximum,
                            color: heatColor(level: level)
                        )
                        .padding(4)
                    }
                    .accessibilityLabel(legendAccessibilityLabel(level: level, maximum: maximum))
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

    private func updateUsageHover(_ active: Bool, id: DailyUsage.ID) {
        hoverDismissTask?.cancel()
        if active {
            hoveredUsageID = id
        } else {
            hoverDismissTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
                if hoveredUsageID == id { hoveredUsageID = nil }
            }
        }
    }

    private func hoverBinding(for id: DailyUsage.ID) -> Binding<Bool> {
        Binding(
            get: { hoveredUsageID == id },
            set: { isPresented in
                if !isPresented, hoveredUsageID == id {
                    hoveredUsageID = nil
                }
            }
        )
    }

    private func legendHoverBinding(for level: Int) -> Binding<Bool> {
        Binding(
            get: { hoveredLegendLevel == level },
            set: { isPresented in
                if !isPresented, hoveredLegendLevel == level {
                    hoveredLegendLevel = nil
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

private struct UsageHeatLegendHoverCard: View {
    let level: Int
    let range: ClosedRange<Int>?
    let maximum: Int
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
                 ? "本月峰值 \(TokenFormatter.compact(maximum)) · 平衡分级"
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

struct DailyUsageHoverCard: View {
    let usage: DailyUsage
    let dateText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(dateText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)

                Spacer(minLength: 8)

                Text("总 Token")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                Text(TokenFormatter.compact(usage.total))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(CodexVistaTheme.dashboardPrimaryText)
                    .monospacedDigit()
            }

            Rectangle()
                .fill(CodexVistaTheme.dashboardBorder.opacity(0.8))
                .frame(height: 1)

            TokenCompositionView(
                breakdown: TokenBreakdown(input: usage.uncachedInput, cachedInput: usage.cachedInput,
                                          output: usage.output, reasoning: usage.reasoning),
                total: usage.total, compact: true
            )
            .padding(.vertical, 5)

            if let estimatedCostUSD = usage.estimatedCostUSD {
                Rectangle()
                    .fill(CodexVistaTheme.dashboardBorder.opacity(0.8))
                    .frame(height: 1)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("API 等值预计花费")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(CodexVistaTheme.dashboardMutedText)

                    Spacer(minLength: 8)

                    Text(ModelCostFormatter.usd(
                        estimatedCostUSD,
                        approximate: usage.referencePricedModelCount > 0
                    ))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(CodexVistaTheme.dashboardAccent)
                        .monospacedDigit()
                }

                if usage.unpricedModelCount > 0 {
                    Text("部分估算 · \(usage.unpricedModelCount) 个模型未定价")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                } else if usage.referencePricedModelCount > 0 {
                    Text("参考估算 · \(usage.referencePricedModelCount) 个模型按 GPT-5.5 参考价")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                }
            }
            if !usage.modelEntries.isEmpty {
                Divider()
                Text("模型用量 · \(usage.modelEntries.count)")
                    .font(.system(size: 10, weight: .semibold))
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(usage.modelEntries) { entry in
                            modelSection(entry)
                        }
                    }
                    .padding(.vertical, 5)
                }
                .frame(height: min(CGFloat(usage.modelEntries.count) * 150, 300))
                .scrollIndicators(.visible)
                Text("API 等值估算，不代表 Codex 实际账单。")
                    .font(.system(size: 8.5))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            }
        }
        .frame(width: usage.modelEntries.isEmpty ? 250 : 310)
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(dateText)，总 Token \(usage.total)，输入 \(usage.uncachedInput)（\(tokenShare(usage.uncachedInput))），缓存 \(usage.cachedInput)（\(tokenShare(usage.cachedInput))），输出 \(usage.output)（\(tokenShare(usage.output))），推理 \(usage.reasoning)（\(tokenShare(usage.reasoning))）\(costAccessibilityDescription)"
        )
    }

    private func modelSection(_ entry: ModelUsageEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.model)
                    .font(.system(size: 10, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(TokenFormatter.compact(entry.totalTokens))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            TokenCompositionView(
                breakdown: TokenBreakdown(
                    input: entry.uncachedInputTokens, cachedInput: entry.cachedInputTokens,
                    output: entry.visibleOutputTokens, reasoning: entry.reasoningTokens
                ),
                total: entry.totalTokens, compact: true
            )
            HStack {
                Text("API 等值预计花费")
                Spacer()
                Text(entry.estimatedCostUSD.map {
                    ModelCostFormatter.usd($0, approximate: ModelPricingCatalog.usesReferencePricing(for: entry.model))
                } ?? "未定价")
                    .foregroundStyle(CodexVistaTheme.dashboardAccent)
                    .monospacedDigit()
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            Divider()
        }
    }

    private var costAccessibilityDescription: String {
        guard let estimatedCostUSD = usage.estimatedCostUSD else { return "" }
        let unpricedDescription = usage.unpricedModelCount > 0
            ? "，\(usage.unpricedModelCount) 个模型未定价"
            : ""
        let referenceDescription = usage.referencePricedModelCount > 0
            ? "，\(usage.referencePricedModelCount) 个模型采用 GPT-5.5 参考价"
            : ""
        let cost = ModelCostFormatter.usd(
            estimatedCostUSD,
            approximate: usage.referencePricedModelCount > 0
        )
        return "，API 等值预计花费 \(cost)\(unpricedDescription)\(referenceDescription)"
    }

    private func tokenShare(_ value: Int) -> String {
        TokenFormatter.percentage(usage.total > 0 ? Double(value) / Double(usage.total) : 0)
    }

}
