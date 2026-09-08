import Foundation

struct DashboardSnapshot: Sendable {
    let planName: String
    let updatedText: String
    let periods: [PeriodUsage]
    let subscriptionCycle: SubscriptionCycle?
    let quotas: [QuotaSnapshot]
    let models: [ModelUsage]
    let dailyUsage: [DailyUsage]
    let subscriptionCycleUsage: [DailyUsage]
    let activityRankings: ActivityRankingSnapshot
    let workspaceUsage: WorkspaceUsageSnapshot
    let modelUsage: ModelUsageSnapshot
    let issues: [DashboardIssue]

    init(
        planName: String,
        updatedText: String,
        periods: [PeriodUsage],
        subscriptionCycle: SubscriptionCycle? = nil,
        quotas: [QuotaSnapshot],
        models: [ModelUsage],
        dailyUsage: [DailyUsage],
        subscriptionCycleUsage: [DailyUsage] = [],
        activityRankings: ActivityRankingSnapshot = .empty,
        workspaceUsage: WorkspaceUsageSnapshot = .empty,
        modelUsage: ModelUsageSnapshot = .empty,
        issues: [DashboardIssue] = []
    ) {
        self.planName = planName
        self.updatedText = updatedText
        self.periods = periods
        self.subscriptionCycle = subscriptionCycle
        self.quotas = quotas
        self.models = models
        self.dailyUsage = dailyUsage
        self.subscriptionCycleUsage = subscriptionCycleUsage
        self.activityRankings = activityRankings
        self.workspaceUsage = workspaceUsage
        self.modelUsage = modelUsage
        self.issues = issues
    }

    var todayTokens: Int { period(id: "today").total }
    var sevenDayTokens: Int { period(id: "sevenDays").total }
    var thirtyDayTokens: Int { period(id: "thirtyDays").total }
    var totalTokens: Int { period(id: "allTime").total }

    var fiveHourQuota: QuotaSnapshot? {
        quotas.first { $0.id == "5h" }
    }

    var weeklyQuota: QuotaSnapshot? {
        quotas.first { $0.id == "7d" }
    }

    var visibleQuotas: [QuotaSnapshot] {
        [fiveHourQuota, weeklyQuota].compactMap { $0 }
    }

    var menuBarQuotaLabel: String {
        menuBarLabel(configuration: .standard)
    }

    func menuBarLabel(configuration: MenuBarLabelConfiguration) -> String {
        guard configuration.showsLivePreview else { return "CodexVista" }
        var components: [String] = []
        if configuration.showsFiveHour, let fiveHourQuota {
            components.append(fiveHourQuota.label(for: configuration.quotaDisplay))
        }
        if configuration.showsWeekly, let weeklyQuota {
            components.append(weeklyQuota.label(for: configuration.quotaDisplay))
        }
        return components.isEmpty ? "CodexVista" : components.joined(separator: " · ")
    }

    var breakdown: TokenBreakdown {
        let today = period(id: "today")
        return TokenBreakdown(
            input: today.uncachedInput,
            cachedInput: today.cachedInput,
            output: today.visibleOutput,
            reasoning: today.reasoning
        )
    }

    static func empty(updatedText: String) -> DashboardSnapshot {
        DashboardSnapshot(
            planName: "Free",
            updatedText: updatedText,
            periods: [
                zeroPeriod(id: "today", title: "今日"),
                zeroPeriod(id: "sevenDays", title: "7 日"),
                zeroPeriod(id: "thirtyDays", title: "30 日"),
                zeroPeriod(id: "allTime", title: "累计")
            ],
            quotas: [],
            models: [],
            dailyUsage: []
        )
    }

    private func period(id: String) -> PeriodUsage {
        periods.first { $0.id == id } ?? Self.zeroPeriod(id: id, title: "")
    }

    private static func zeroPeriod(id: String, title: String) -> PeriodUsage {
        PeriodUsage(
            id: id, title: title, total: 0, uncachedInput: 0,
            cachedInput: 0, output: 0, reasoning: 0
        )
    }

}

enum ActivityRange: String, CaseIterable, Identifiable, Sendable {
    case today = "今日"
    case sevenDays = "7 日"
    case thirtyDays = "30 日"
    case allTime = "累计"

    static let defaultRange: ActivityRange = .sevenDays

    var id: Self { self }
}

struct ActivityRankingDetail: Identifiable, Equatable, Sendable {
    let name: String
    let count: Int

    var id: String { name }
}

struct ActivityRankingEntry: Identifiable, Equatable, Sendable {
    let name: String
    let count: Int
    let details: [ActivityRankingDetail]

    init(name: String, count: Int, details: [ActivityRankingDetail] = []) {
        self.name = name
        self.count = count
        self.details = details
    }

    var id: String { name }
}

struct ActivityRanking: Equatable, Sendable {
    let skills: [ActivityRankingEntry]
    let tools: [ActivityRankingEntry]

    static let empty = ActivityRanking(skills: [], tools: [])
}

struct ActivityRankingSnapshot: Equatable, Sendable {
    let today: ActivityRanking
    let sevenDays: ActivityRanking
    let thirtyDays: ActivityRanking
    let allTime: ActivityRanking

    static let empty = ActivityRankingSnapshot(
        today: .empty,
        sevenDays: .empty,
        thirtyDays: .empty,
        allTime: .empty
    )

    func ranking(for range: ActivityRange) -> ActivityRanking {
        switch range {
        case .today: today
        case .sevenDays: sevenDays
        case .thirtyDays: thirtyDays
        case .allTime: allTime
        }
    }
}

struct WorkspaceUsageEntry: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let rootCount: Int
    let isInferred: Bool
    let tokens: Int
    let share: Double
    let projects: [WorkspaceProjectUsageEntry]
    let conversations: [ProjectConversationUsage]
    let dailyUsage: [ProjectDailyUsage]
    var configuredDirectories: [WorkspaceDirectory] = []

    var directories: [WorkspaceDirectory] {
        if !configuredDirectories.isEmpty { return configuredDirectories }
        return projects.map { WorkspaceDirectory(id: $0.id, name: $0.name) }
    }

    var visibleConversations: [ProjectConversationUsage] {
        conversations.filter(\.isIncludedInTaskMetrics)
    }

    var visibleReplyCount: Int {
        visibleConversations.reduce(0) { $0 + $1.replies.count }
    }

    var aiWorktimeMilliseconds: Int64 {
        visibleConversations.reduce(into: Int64(0)) { total, conversation in
            total = Self.saturatingAdd(total, conversation.aiWorktimeMilliseconds)
        }
    }

    var lastVisibleActivityAtMilliseconds: Int64? {
        visibleConversations.compactMap(\.lastMessageAtMilliseconds).max()
    }

    private static func saturatingAdd(_ left: Int64, _ right: Int64) -> Int64 {
        let (result, overflow) = left.addingReportingOverflow(right)
        return overflow ? Int64.max : result
    }
}

struct WorkspaceProjectUsageEntry: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let tokens: Int
    let share: Double
    let conversationCount: Int
    let replyCount: Int
    let lastActivityAtMilliseconds: Int64?
}

struct ProjectDailyUsage: Identifiable, Equatable, Sendable {
    let dayStartMilliseconds: Int64
    let tokens: Int

    var id: Int64 { dayStartMilliseconds }
}

struct ProjectConversationUsage: Identifiable, Equatable, Sendable {
    let shortThreadID: String
    let displayTitle: String?
    let tokens: Int
    let lastMessageAtMilliseconds: Int64?
    let replies: [ProjectReplyUsage]
    let unattributedTokens: Int

    init(
        shortThreadID: String,
        displayTitle: String?,
        tokens: Int,
        lastMessageAtMilliseconds: Int64?,
        replies: [ProjectReplyUsage] = [],
        unattributedTokens: Int = 0
    ) {
        self.shortThreadID = shortThreadID
        self.displayTitle = displayTitle
        self.tokens = tokens
        self.lastMessageAtMilliseconds = lastMessageAtMilliseconds
        self.replies = replies
        self.unattributedTokens = unattributedTokens
    }

    var id: String { shortThreadID }

    var modelCalls: [ProjectReplyActivityCall] {
        Self.mergedCalls(replies.flatMap(\.modelCalls))
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    var skillCalls: [ProjectReplyActivityCall] {
        Self.mergedCalls(replies.flatMap(\.skillCalls))
    }

    var toolCalls: [ProjectReplyActivityCall] {
        Self.mergedCalls(replies.flatMap(\.toolCalls))
    }

    var estimatedCostBreakdown: ModelCostBreakdown? {
        var total = ModelCostBreakdown()
        var hasPricedUsage = false

        for reply in replies {
            guard let breakdown = reply.estimatedCostBreakdown else { continue }
            total.add(breakdown)
            hasPricedUsage = true
        }

        return hasPricedUsage ? total : nil
    }

    var estimatedCostUSD: Double? {
        estimatedCostBreakdown?.totalUSD
    }

    var aiWorktimeMilliseconds: Int64 {
        replies.reduce(into: Int64(0)) { total, reply in
            let (result, overflow) = total.addingReportingOverflow(
                reply.aiWorktimeMilliseconds
            )
            total = overflow ? Int64.max : result
        }
    }

    var unpricedModelCount: Int {
        modelCalls.count { ModelPricingCatalog.rule(for: $0.name) == nil }
    }

    var referencePricedModelCount: Int {
        modelCalls.count { ModelPricingCatalog.usesReferencePricing(for: $0.name) }
    }

    var isIncludedInTaskMetrics: Bool {
        Self.isIncludedInTaskMetrics(displayTitle: displayTitle)
    }

    static func isIncludedInTaskMetrics(displayTitle: String?) -> Bool {
        let normalizedTitle = displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedTitle != "命令权限检查"
    }

    private static func mergedCalls(
        _ calls: [ProjectReplyActivityCall]
    ) -> [ProjectReplyActivityCall] {
        Dictionary(grouping: calls, by: \.name)
            .map { name, calls in
                ProjectReplyActivityCall(
                    name: name,
                    count: calls.reduce(0) { $0 + $1.count }
                )
            }
            .sorted { left, right in
                if left.count != right.count { return left.count > right.count }
                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }
    }
}

enum ProjectReplyUsageStatus: String, Equatable, Sendable {
    case completed
    case interrupted
    case rolledBack
    case inProgress
    case unknown
}

struct ProjectReplyUsage: Identifiable, Equatable, Sendable {
    let id: String
    let status: ProjectReplyUsageStatus
    let modelCalls: [ProjectReplyActivityCall]
    let uncachedInputTokens: Int
    let cachedInputTokens: Int
    let visibleOutputTokens: Int
    let reasoningTokens: Int
    let totalTokens: Int
    let estimatedCostBreakdown: ModelCostBreakdown?
    let unpricedModelCount: Int
    let referencePricedModelCount: Int
    let startedAtMilliseconds: Int64?
    let endedAtMilliseconds: Int64?
    let aiWorktimeMilliseconds: Int64
    let lastUsageAtMilliseconds: Int64
    let skillCalls: [ProjectReplyActivityCall]
    let toolCalls: [ProjectReplyActivityCall]

    var model: String {
        modelCalls.map { "\($0.name) ×\($0.count)" }.joined(separator: " · ")
    }

    var estimatedCostUSD: Double? {
        estimatedCostBreakdown?.totalUSD
    }

    var displayAtMilliseconds: Int64 {
        endedAtMilliseconds ?? lastUsageAtMilliseconds
    }

    var durationMilliseconds: Int64? {
        guard let startedAtMilliseconds, let endedAtMilliseconds else { return nil }
        return max(0, endedAtMilliseconds - startedAtMilliseconds)
    }

    var skillCallCount: Int {
        skillCalls.reduce(0) { $0 + $1.count }
    }

    var toolCallCount: Int {
        toolCalls.reduce(0) { $0 + $1.count }
    }
}

struct ProjectReplyActivityCall: Identifiable, Equatable, Sendable {
    let name: String
    let count: Int

    var id: String { name }
}

enum ProjectConversationSortOrder: String, CaseIterable, Identifiable, Sendable {
    case recent = "最近消息"
    case usage = "用量"

    static let defaultOrder: ProjectConversationSortOrder = .recent

    var id: Self { self }

    func sorted(_ conversations: [ProjectConversationUsage]) -> [ProjectConversationUsage] {
        conversations.sorted { left, right in
            switch self {
            case .recent:
                let leftTime = left.lastMessageAtMilliseconds ?? Int64.min
                let rightTime = right.lastMessageAtMilliseconds ?? Int64.min
                if leftTime != rightTime { return leftTime > rightTime }
                if left.tokens != right.tokens { return left.tokens > right.tokens }
            case .usage:
                if left.tokens != right.tokens { return left.tokens > right.tokens }
                let leftTime = left.lastMessageAtMilliseconds ?? Int64.min
                let rightTime = right.lastMessageAtMilliseconds ?? Int64.min
                if leftTime != rightTime { return leftTime > rightTime }
            }
            return left.shortThreadID < right.shortThreadID
        }
    }
}

struct WorkspaceUsageRanking: Equatable, Sendable {
    let entries: [WorkspaceUsageEntry]
    let totalTokens: Int
    let workspaceCount: Int
    let projectCount: Int

    static let empty = WorkspaceUsageRanking(
        entries: [],
        totalTokens: 0,
        workspaceCount: 0,
        projectCount: 0
    )

    var totalAIWorktimeMilliseconds: Int64 {
        entries.reduce(into: Int64(0)) { total, entry in
            let (result, overflow) = total.addingReportingOverflow(
                entry.aiWorktimeMilliseconds
            )
            total = overflow ? Int64.max : result
        }
    }

    var todayTasks: [TodayTaskUsageEntry] {
        entries.flatMap { workspace in
            workspace.visibleConversations.map { conversation in
                TodayTaskUsageEntry(workspace: workspace, conversation: conversation)
            }
        }
        .sorted { left, right in
            if left.status.sortPriority != right.status.sortPriority {
                return left.status.sortPriority < right.status.sortPriority
            }
            if left.lastUpdatedAtMilliseconds != right.lastUpdatedAtMilliseconds {
                return left.lastUpdatedAtMilliseconds > right.lastUpdatedAtMilliseconds
            }
            if left.title != right.title {
                return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
            }
            return left.id < right.id
        }
    }
}

struct TodayTaskUsageEntry: Identifiable, Equatable, Sendable {
    let workspace: WorkspaceUsageEntry
    let conversation: ProjectConversationUsage

    var id: String { "\(workspace.id)::\(conversation.id)" }

    var title: String {
        conversation.displayTitle ?? conversation.shortThreadID
    }

    var status: ProjectReplyUsageStatus {
        if conversation.replies.contains(where: { $0.status == .inProgress }) {
            return .inProgress
        }
        return conversation.replies.max {
            if $0.displayAtMilliseconds != $1.displayAtMilliseconds {
                return $0.displayAtMilliseconds < $1.displayAtMilliseconds
            }
            return $0.id > $1.id
        }?.status ?? .unknown
    }

    var lastUpdatedAtMilliseconds: Int64 {
        max(
            conversation.lastMessageAtMilliseconds ?? Int64.min,
            conversation.replies.map(\.displayAtMilliseconds).max() ?? Int64.min
        )
    }

    var tokenBreakdown: TokenBreakdown {
        conversation.replies.reduce(
            into: TokenBreakdown(input: 0, cachedInput: 0, output: 0, reasoning: 0)
        ) { result, reply in
            result = TokenBreakdown(
                input: result.input + reply.uncachedInputTokens,
                cachedInput: result.cachedInput + reply.cachedInputTokens,
                output: result.output + reply.visibleOutputTokens,
                reasoning: result.reasoning + reply.reasoningTokens
            )
        }
    }

    var unattributedTokens: Int {
        max(0, conversation.tokens - tokenBreakdown.total)
    }

    var aiWorktimeMilliseconds: Int64 {
        conversation.aiWorktimeMilliseconds
    }
}

private extension ProjectReplyUsageStatus {
    var sortPriority: Int {
        switch self {
        case .inProgress: 0
        case .completed: 1
        case .interrupted: 2
        case .rolledBack: 3
        case .unknown: 4
        }
    }
}

struct WorkspaceUsageSnapshot: Equatable, Sendable {
    let today: WorkspaceUsageRanking
    let sevenDays: WorkspaceUsageRanking
    let thirtyDays: WorkspaceUsageRanking
    let allTime: WorkspaceUsageRanking

    static let empty = WorkspaceUsageSnapshot(
        today: .empty,
        sevenDays: .empty,
        thirtyDays: .empty,
        allTime: .empty
    )

    func ranking(for range: ActivityRange) -> WorkspaceUsageRanking {
        switch range {
        case .today: today
        case .sevenDays: sevenDays
        case .thirtyDays: thirtyDays
        case .allTime: allTime
        }
    }
}

enum DashboardIssue: Hashable, Sendable {
    case expiredQuota(id: String)
    case invalidQuota(id: String)
}

enum TrendRange: String, CaseIterable, Identifiable, Sendable {
    case sevenDays = "7 天"
    case thirtyDays = "30 天"
    case subscriptionCycles = "周期"

    static let defaultRange: TrendRange = .sevenDays

    var id: Self { self }

    var showsXAxis: Bool {
        self == .sevenDays
    }

    func select(
        from usage: [DailyUsage],
        subscriptionCycleUsage: [DailyUsage] = []
    ) -> [DailyUsage] {
        switch self {
        case .sevenDays:
            return Array(usage.suffix(7))
        case .thirtyDays:
            return Array(usage.suffix(30))
        case .subscriptionCycles:
            return subscriptionCycleUsage
        }
    }
}

struct PeriodUsage: Identifiable, Sendable {
    let id: String
    let title: String
    let total: Int
    let uncachedInput: Int
    let cachedInput: Int
    let output: Int
    let reasoning: Int

    var visibleOutput: Int { max(0, output - reasoning) }

    func share(of value: Int) -> Double {
        guard total > 0 else { return 0 }
        return min(max(Double(value) / Double(total), 0), 1)
    }
}

struct QuotaSnapshot: Identifiable, Sendable {
    let id: String
    let title: String
    let remaining: Double
    let resetText: String
    let resetsAt: Date?
    let observedAt: Date?

    init(
        id: String,
        title: String,
        remaining: Double,
        resetText: String,
        resetsAt: Date? = nil,
        observedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.remaining = remaining
        self.resetText = resetText
        self.resetsAt = resetsAt
        self.observedAt = observedAt
    }

    var remainingPercent: Int { Int((remaining * 100).rounded()) }

    var compactTitle: String {
        switch id {
        case "5h": "5H"
        case "7d": "7d"
        default: title
        }
    }

    var remainingLabel: String {
        "\(compactTitle) \(remainingPercent)%"
    }

    func label(for preference: QuotaDisplayPreference) -> String {
        let percent: Int
        switch preference {
        case .used:
            percent = Int(((1 - remaining) * 100).rounded())
        case .remaining:
            percent = remainingPercent
        }
        return "\(compactTitle) \(percent)%"
    }

    func resetCountdown(now: Date = Date()) -> String? {
        resetInterval(now: now).map { "\($0.amount)\($0.compactUnit)" }
    }

    func resetDescription(now: Date = Date()) -> String? {
        resetInterval(now: now).map { "\($0.amount) \($0.chineseUnit)后重置" }
    }

    func detailedResetDescription(now: Date = Date()) -> String? {
        guard let seconds = resetSeconds(now: now) else { return nil }
        let totalMinutes = max(1, Int(ceil(seconds / 60)))
        let days = totalMinutes / (24 * 60)
        let hours = totalMinutes % (24 * 60) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            if hours > 0 {
                return "\(days) 天 \(hours) 小时后重置"
            }
            if minutes > 0 {
                return "\(days) 天 \(minutes) 分钟后重置"
            }
            return "\(days) 天后重置"
        }
        if hours > 0 {
            if minutes > 0 {
                return "\(hours) 小时 \(minutes) 分钟后重置"
            }
            return "\(hours) 小时后重置"
        }
        return "\(totalMinutes) 分钟后重置"
    }

    func observationDescription(now: Date = Date()) -> String? {
        guard let observedAt else { return nil }
        let seconds = max(now.timeIntervalSince(observedAt), 0)
        if seconds < 60 { return "刚刚观测" }
        if seconds < 3_600 { return "\(max(1, Int(seconds / 60))) 分钟前观测" }
        if seconds < 86_400 { return "\(max(1, Int(seconds / 3_600))) 小时前观测" }
        return "\(max(1, Int(seconds / 86_400))) 天前观测"
    }

    private func resetInterval(now: Date) -> (amount: Int, compactUnit: String, chineseUnit: String)? {
        guard let seconds = resetSeconds(now: now) else { return nil }

        if seconds < 3_600 {
            return (max(1, Int(ceil(seconds / 60))), "m", "分钟")
        }
        if seconds < 86_400 {
            return (max(1, Int(ceil(seconds / 3_600))), "h", "小时")
        }
        return (max(1, Int(ceil(seconds / 86_400))), "d", "天")
    }

    private func resetSeconds(now: Date) -> TimeInterval? {
        guard let resetsAt else { return nil }
        let seconds = resetsAt.timeIntervalSince(now)
        return seconds > 0 ? seconds : nil
    }
}

struct TokenBreakdown: Sendable {
    let input: Int
    let cachedInput: Int
    let output: Int
    let reasoning: Int

    var total: Int {
        [input, cachedInput, output, reasoning].reduce(0) { partial, value in
            let (sum, overflow) = partial.addingReportingOverflow(value)
            return overflow ? Int.max : sum
        }
    }
}

struct ModelUsage: Identifiable, Sendable {
    let id: String
    let name: String
    let share: Double
}

struct ModelUsageEntry: Identifiable, Equatable, Sendable {
    let model: String
    let totalTokens: Int
    let uncachedInputTokens: Int
    let cachedInputTokens: Int
    let visibleOutputTokens: Int
    let reasoningTokens: Int
    let share: Double
    let estimatedCostUSD: Double?

    var id: String { model }
}

struct ModelUsageRanking: Equatable, Sendable {
    let entries: [ModelUsageEntry]
    let totalTokens: Int
    let estimatedCostUSD: Double
    let unpricedModelCount: Int
    let referencePricedModelCount: Int

    static let empty = ModelUsageRanking(
        entries: [],
        totalTokens: 0,
        estimatedCostUSD: 0,
        unpricedModelCount: 0,
        referencePricedModelCount: 0
    )
}

struct ModelUsageSnapshot: Equatable, Sendable {
    let today: ModelUsageRanking
    let sevenDays: ModelUsageRanking
    let thirtyDays: ModelUsageRanking
    let subscriptionCycle: ModelUsageRanking
    let allTime: ModelUsageRanking

    init(
        today: ModelUsageRanking,
        sevenDays: ModelUsageRanking,
        thirtyDays: ModelUsageRanking,
        subscriptionCycle: ModelUsageRanking = .empty,
        allTime: ModelUsageRanking
    ) {
        self.today = today
        self.sevenDays = sevenDays
        self.thirtyDays = thirtyDays
        self.subscriptionCycle = subscriptionCycle
        self.allTime = allTime
    }

    static let empty = ModelUsageSnapshot(
        today: .empty,
        sevenDays: .empty,
        thirtyDays: .empty,
        subscriptionCycle: .empty,
        allTime: .empty
    )

    func ranking(for range: ActivityRange) -> ModelUsageRanking {
        switch range {
        case .today: today
        case .sevenDays: sevenDays
        case .thirtyDays: thirtyDays
        case .allTime: allTime
        }
    }

    func ranking(forPeriodID periodID: String) -> ModelUsageRanking {
        switch periodID {
        case "today": today
        case "sevenDays": sevenDays
        case "thirtyDays": thirtyDays
        case "subscriptionCycle": subscriptionCycle
        case "allTime": allTime
        default: .empty
        }
    }
}

struct DailyUsage: Identifiable, Sendable {
    let id: String
    let day: String
    let total: Int
    let uncachedInput: Int
    let cachedInput: Int
    let output: Int
    let reasoning: Int
    let estimatedCostUSD: Double?
    let unpricedModelCount: Int
    let referencePricedModelCount: Int
    let modelEntries: [ModelUsageEntry]

    init(
        id: String,
        day: String,
        total: Int,
        uncachedInput: Int = 0,
        cachedInput: Int = 0,
        output: Int = 0,
        reasoning: Int = 0,
        estimatedCostUSD: Double? = nil,
        unpricedModelCount: Int = 0,
        referencePricedModelCount: Int = 0,
        modelEntries: [ModelUsageEntry] = []
    ) {
        self.id = id
        self.day = day
        self.total = total
        self.uncachedInput = uncachedInput
        self.cachedInput = cachedInput
        self.output = output
        self.reasoning = reasoning
        self.estimatedCostUSD = estimatedCostUSD
        self.unpricedModelCount = unpricedModelCount
        self.referencePricedModelCount = referencePricedModelCount
        self.modelEntries = modelEntries
    }
}
