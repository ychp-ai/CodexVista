import Foundation

// Handwritten examples: no local Codex files, database, task names or paths.
enum DocumentationFixture {
    static let now = ISO8601DateFormatter().date(from: "2026-09-04T08:00:00Z")!
    static let milliseconds = Int64(now.timeIntervalSince1970 * 1_000)
    static let modelNames = ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.5", "gpt-5.4", "gpt-5.3-codex", "example-model"]
    static let weights = [36, 24, 16, 12, 8, 4]

    static func cost(_ tokens: Int, model: String = "gpt-5.5") -> ModelCostBreakdown {
        ModelPricingCatalog.rule(for: model)!.estimateBreakdown(
            uncachedInputTokens: Int64(tokens / 5), cachedInputTokens: Int64(tokens * 3 / 5),
            visibleOutputTokens: Int64(tokens / 10), reasoningTokens: Int64(tokens / 10))
    }

    static func reply(_ index: Int, tokens: Int, running: Bool = false) -> ProjectReplyUsage {
        let model = modelNames[index % modelNames.count]
        let start = milliseconds - Int64(index + 1) * 1_800_000
        return ProjectReplyUsage(
            id: "example-reply-\(index)", status: running ? .inProgress : .completed,
            modelCalls: [.init(name: model, count: 1)],
            uncachedInputTokens: tokens / 5, cachedInputTokens: tokens * 3 / 5,
            visibleOutputTokens: tokens / 10, reasoningTokens: tokens / 10,
            totalTokens: tokens, estimatedCostBreakdown: cost(tokens, model: model),
            unpricedModelCount: 0, referencePricedModelCount: ModelPricingCatalog.usesReferencePricing(for: model) ? 1 : 0,
            startedAtMilliseconds: start, endedAtMilliseconds: running ? nil : start + 600_000,
            aiWorktimeMilliseconds: running ? milliseconds - start : 600_000,
            lastUsageAtMilliseconds: running ? milliseconds : start + 600_000,
            skillCalls: [.init(name: "build-web-apps:frontend-app-builder", count: 1),
                         .init(name: "build-web-apps:react-best-practices", count: 2)],
            toolCalls: [.init(name: "exec_command", count: 8), .init(name: "apply_patch", count: 3),
                        .init(name: "view_image", count: 2)])
    }

    static let workspaces: [WorkspaceUsageEntry] = {
        let titles = [["完善首页导航", "优化设置页布局"], ["补充接口示例", "整理快速入门"], ["增加筛选条件", "检查趋势图展示"]]
        let names = ["示例网站", "示例文档", "示例看板"]
        return (0..<3).map { project in
            let conversations = (0..<2).map { task in
                let index = project * 2 + task
                let tokens = 12_000 * weights[index]
                let replies = [reply(index, tokens: tokens * 3 / 5, running: index == 0),
                               reply(index + 6, tokens: tokens * 2 / 5)]
                return ProjectConversationUsage(shortThreadID: "example-task-\(index)",
                    displayTitle: titles[project][task], tokens: tokens,
                    lastMessageAtMilliseconds: replies.map(\.lastUsageAtMilliseconds).max(), replies: replies)
            }
            let total = conversations.reduce(0) { $0 + $1.tokens }
            return WorkspaceUsageEntry(id: "example-project-\(project)", name: names[project],
                rootCount: 2, isInferred: false, tokens: total, share: Double(total) / 1_200_000,
                projects: [], conversations: conversations,
                dailyUsage: (0..<7).map { offset in
                    .init(dayStartMilliseconds: milliseconds - 28_800_000 - Int64(6 - offset) * 86_400_000,
                          tokens: offset == 6 ? total : 0)
                }, configuredDirectories: [.init(id: "example-root-\(project)-1", name: "app"),
                                           .init(id: "example-root-\(project)-2", name: "docs")])
        }
    }()

    static let workspaceRanking = WorkspaceUsageRanking(entries: workspaces, totalTokens: 1_200_000,
                                                        workspaceCount: 3, projectCount: 6)
    static let activity = ActivityRanking(
        skills: [.init(name: "build-web-apps", count: 36, details: [
            .init(name: "frontend-app-builder", count: 12), .init(name: "react-best-practices", count: 24)])],
        tools: [.init(name: "exec_command", count: 96), .init(name: "apply_patch", count: 36),
                .init(name: "view_image", count: 24)])

    static func ranking(total: Int) -> ModelUsageRanking {
        let entries = modelNames.enumerated().map { index, model in
            let tokens = total * weights[index] / 100
            return ModelUsageEntry(model: model, totalTokens: tokens,
                uncachedInputTokens: tokens / 5, cachedInputTokens: tokens * 3 / 5,
                visibleOutputTokens: tokens / 10, reasoningTokens: tokens / 10,
                share: Double(weights[index]) / 100, estimatedCostUSD: cost(tokens, model: model).totalUSD)
        }
        return .init(entries: entries, totalTokens: total,
                     estimatedCostUSD: entries.compactMap(\.estimatedCostUSD).reduce(0, +),
                     unpricedModelCount: 0,
                     referencePricedModelCount: entries.filter { ModelPricingCatalog.usesReferencePricing(for: $0.model) }.count)
    }

    static let daily: [DailyUsage] = (0..<30).map { index in
        let date = now.addingTimeInterval(Double(index - 29) * 86_400)
        let day = ISO8601DateFormatter().string(from: date).prefix(10)
        // Examples contain an intentionally quiet week before today's tasks.
        let tokens = index == 29 ? 1_200_000 : (index >= 23 ? 0 : (index % 5 + 1) * 120_000)
        return .init(id: String(day), day: String(day.suffix(5)), total: tokens,
                     uncachedInput: tokens / 5, cachedInput: tokens * 3 / 5,
                     output: tokens / 10, reasoning: tokens / 10,
                     estimatedCostUSD: ranking(total: tokens).estimatedCostUSD,
                     referencePricedModelCount: tokens > 0 ? ranking(total: tokens).referencePricedModelCount : 0,
                     modelEntries: tokens > 0 ? ranking(total: tokens).entries : [])
    }

    static let snapshot: DashboardSnapshot = {
        let monthly = daily.reduce(0) { $0 + $1.total }
        let totals = [("today", "今日", 1_200_000), ("sevenDays", "7 日", 1_200_000),
                      ("thirtyDays", "30 日", monthly), ("allTime", "累计", monthly),
                      ("subscriptionCycle", "当前订阅周期", monthly)]
        let periods = totals.map { id, title, total in
            PeriodUsage(id: id, title: title, total: total, uncachedInput: total / 5,
                        cachedInput: total * 3 / 5, output: total / 5, reasoning: total / 10)
        }
        return DashboardSnapshot(planName: "Pro 5x", updatedText: "刚刚刷新", periods: periods,
            subscriptionCycle: SubscriptionCycle(start: now.addingTimeInterval(-29 * 86_400),
                                                  end: now.addingTimeInterval(2 * 86_400)),
            quotas: [.init(id: "7d", title: "7 天额度", remaining: 0.68, resetText: "2 天后",
                           resetsAt: now.addingTimeInterval(2 * 86_400), observedAt: now)],
            models: [], dailyUsage: daily,
            activityRankings: .init(today: activity, sevenDays: activity, thirtyDays: activity, allTime: activity),
            workspaceUsage: .init(today: workspaceRanking, sevenDays: workspaceRanking,
                                  thirtyDays: workspaceRanking, allTime: workspaceRanking),
            modelUsage: .init(today: ranking(total: 1_200_000), sevenDays: ranking(total: 1_200_000),
                              thirtyDays: ranking(total: monthly), subscriptionCycle: ranking(total: monthly),
                              allTime: ranking(total: monthly)))
    }()
}

struct DocumentationDataClient: DashboardDataClient {
    func loadCached() async throws -> DashboardDataResult { result }
    func refreshUsage() async throws -> DashboardDataResult { result }
    func backfillHistory() async throws -> DashboardDataResult { result }
    func rebuildFromLocalData(progress: @escaping CodexImportProgressHandler) async throws -> DashboardDataResult { result }
    var result: DashboardDataResult { .loaded(DocumentationFixture.snapshot, Self.summary) }
    static let summary = SourceSummary(cli: .connected, desktop: .connected, index: .connected,
                                       lastSuccessfulRefresh: DocumentationFixture.now)
}

@MainActor
final class DocumentationNotifications: UsageNotificationClient {
    func authorizationStatus() async -> UsageReminderAuthorizationStatus { .authorized }
    func requestAuthorization() async throws -> Bool { false }
    func deliver(_ notification: UsageReminderNotification) async throws {}
}

struct DocumentationUpdates: AppReleaseProviding {
    func latestRelease() async throws -> AppRelease { throw CancellationError() }
    func downloadInstaller(for release: AppRelease) async throws -> URL { throw CancellationError() }
}
