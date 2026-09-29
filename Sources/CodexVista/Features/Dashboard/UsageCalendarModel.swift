import Foundation

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

    init(usage: [DailyUsage], calendar: Calendar = CodexUsageCalendar.utc, today: Date = Date()) {
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

struct UsageCalendarWeek: Identifiable {
    let id: String
    let startID: String
    let endID: String
    let isFuture: Bool
    let isCurrentWeek: Bool
    let usage: DailyUsage

    var dateRangeText: String {
        "\(startID.suffix(5)) – \(endID.suffix(5))"
    }

    var detailTitle: String {
        "\(startID) 至 \(endID) · UTC\(isCurrentWeek ? " · 截至今日" : "")"
    }
}

extension UsageCalendarModel {
    func weeks(for month: Date) -> [UsageCalendarWeek] {
        let days = cells(for: month)
        return stride(from: 0, to: days.count, by: 7).compactMap { offset in
            let week = Array(days[offset..<min(offset + 7, days.count)])
            guard week.contains(where: \.isInDisplayedMonth),
                  let first = week.first, let last = week.last else { return nil }
            let id = "week-\(first.id)"
            return UsageCalendarWeek(
                id: id, startID: first.id, endID: last.id,
                isFuture: first.isFuture,
                isCurrentWeek: week.contains(where: \.isToday),
                usage: Self.summarize(week.filter { !$0.isFuture }.compactMap(\.usage), id: id)
            )
        }
    }

    private static func summarize(_ days: [DailyUsage], id: String) -> DailyUsage {
        // Daily counts are already normalized. Sum disjoint categories without repricing.
        func sum(_ values: [Int]) -> Int {
            values.reduce(0) { partial, value in
                let (result, overflow) = partial.addingReportingOverflow(value)
                return overflow ? Int.max : result
            }
        }
        let total = sum(days.map(\.total))
        let groupedEntries = Dictionary(grouping: days.flatMap(\.modelEntries), by: \.model)
        let entries: [ModelUsageEntry] = groupedEntries.map { (model: String, values: [ModelUsageEntry]) -> ModelUsageEntry in
            let tokens = sum(values.map(\.totalTokens))
            let costs = values.compactMap(\.estimatedCostUSD)
            return ModelUsageEntry(
                model: model, totalTokens: tokens,
                uncachedInputTokens: sum(values.map(\.uncachedInputTokens)),
                cachedInputTokens: sum(values.map(\.cachedInputTokens)),
                visibleOutputTokens: sum(values.map(\.visibleOutputTokens)),
                reasoningTokens: sum(values.map(\.reasoningTokens)),
                share: total > 0 ? Double(tokens) / Double(total) : 0,
                estimatedCostUSD: costs.isEmpty ? nil : costs.reduce(0, +)
            )
        }.sorted {
            $0.totalTokens == $1.totalTokens ? $0.model < $1.model : $0.totalTokens > $1.totalTokens
        }
        let costs = days.compactMap(\.estimatedCostUSD)
        var result = DailyUsage(
            id: id, day: id, total: total,
            uncachedInput: sum(days.map(\.uncachedInput)),
            cachedInput: sum(days.map(\.cachedInput)),
            output: sum(days.map(\.output)),
            reasoning: sum(days.map(\.reasoning)),
            estimatedCostUSD: costs.isEmpty ? nil : costs.reduce(0, +),
            unpricedModelCount: entries.filter { $0.estimatedCostUSD == nil }.count,
            referencePricedModelCount: entries.filter {
                $0.estimatedCostUSD != nil && ModelPricingCatalog.usesReferencePricing(for: $0.model)
            }.count,
            modelEntries: entries
        )
        let statistics = days.compactMap(\.quotaStatistics)
        if !statistics.isEmpty {
            // Combine only validated daily intervals; never infer a new interval across days or resets.
            result.quotaStatistics = DailyQuotaStatistics(
                changes: statistics.flatMap(\.changes).sorted { $0.observedAt < $1.observedAt },
                consumedPercentagePoints: statistics.reduce(0) { $0 + $1.consumedPercentagePoints },
                matchedTokens: statistics.reduce(0) { $0 + $1.matchedTokens }
            )
        }
        return result
    }
}
