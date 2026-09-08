import Foundation
import XCTest
@testable import CodexVista

final class DashboardQueryServiceTests: XCTestCase {
    func testSubscriptionCycleClampsMonthEndAnchorsWithoutDrifting() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let cases: [(first: DateComponents, expectedNext: DateComponents)] = [
            (
                DateComponents(year: 2025, month: 1, day: 31, hour: 9, minute: 30),
                DateComponents(year: 2025, month: 2, day: 28, hour: 9, minute: 30)
            ),
            (
                DateComponents(year: 2024, month: 1, day: 31, hour: 9, minute: 30),
                DateComponents(year: 2024, month: 2, day: 29, hour: 9, minute: 30)
            ),
            (
                DateComponents(year: 2026, month: 3, day: 31, hour: 9, minute: 30),
                DateComponents(year: 2026, month: 4, day: 30, hour: 9, minute: 30)
            )
        ]

        for testCase in cases {
            let firstSubscribedAt = try XCTUnwrap(calendar.date(from: testCase.first))
            let nextBoundary = try XCTUnwrap(calendar.date(from: testCase.expectedNext))
            let cycle = try XCTUnwrap(SubscriptionCycleCalculator.cycle(
                containing: nextBoundary.addingTimeInterval(-0.001),
                firstSubscribedAt: firstSubscribedAt,
                calendar: calendar
            ))

            XCTAssertEqual(cycle.start, firstSubscribedAt)
            XCTAssertEqual(cycle.end, nextBoundary)
        }
    }

    func testSubscriptionCycleUsesFirstSubscriptionTimeAsMonthlyAnchor() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let firstSubscribedAt = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 1, day: 31, hour: 9, minute: 30
        )))
        let marchStart = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 3, day: 31, hour: 9, minute: 30
        )))
        let beforeMarchStart = marchStart.addingTimeInterval(-0.001)

        let februaryCycle = try XCTUnwrap(SubscriptionCycleCalculator.cycle(
            containing: beforeMarchStart,
            firstSubscribedAt: firstSubscribedAt,
            calendar: calendar
        ))
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day, .hour, .minute], from: februaryCycle.start),
            DateComponents(year: 2026, month: 2, day: 28, hour: 9, minute: 30)
        )
        XCTAssertEqual(februaryCycle.end, marchStart)

        let marchCycle = try XCTUnwrap(SubscriptionCycleCalculator.cycle(
            containing: marchStart,
            firstSubscribedAt: firstSubscribedAt,
            calendar: calendar
        ))
        XCTAssertEqual(marchCycle.start, marchStart)
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day, .hour, .minute], from: marchCycle.end),
            DateComponents(year: 2026, month: 4, day: 30, hour: 9, minute: 30)
        )
        XCTAssertNil(SubscriptionCycleCalculator.cycle(
            containing: firstSubscribedAt.addingTimeInterval(-1),
            firstSubscribedAt: firstSubscribedAt,
            calendar: calendar
        ))
    }

    func testSnapshotAddsCurrentSubscriptionCycleUsageWithoutReplacingStandardPeriods() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let firstSubscribedAt = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 5, day: 10, hour: 8, minute: 30
        )))
        let cycleStart = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 10, hour: 8, minute: 30
        )))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 19, hour: 12
        )))
        let store = try makeStore()
        try store.commit(batch(
            events: [
                usage(
                    "before-cycle",
                    at: cycleStart.addingTimeInterval(-0.001),
                    total: 90,
                    model: "before-cycle-model"
                ),
                usage(
                    "cycle-start",
                    at: cycleStart,
                    total: 100,
                    model: "gpt-5.6-sol"
                ),
                usage(
                    "cycle-latest",
                    at: now,
                    total: 20,
                    model: "codex-auto-review"
                )
            ],
            quotas: []
        ))

        let snapshot = try DashboardQueryService(store: store).snapshot(
            now: now,
            calendar: calendar,
            firstSubscriptionDate: firstSubscribedAt
        )

        XCTAssertEqual(
            snapshot.periods.map(\.id),
            ["today", "sevenDays", "thirtyDays", "subscriptionCycle", "allTime"]
        )
        XCTAssertEqual(snapshot.periods.first { $0.id == "subscriptionCycle" }?.title, "当前订阅周期")
        XCTAssertEqual(snapshot.periods.first { $0.id == "subscriptionCycle" }?.total, 120)
        XCTAssertEqual(snapshot.subscriptionCycle?.start, cycleStart)
        XCTAssertEqual(
            snapshot.subscriptionCycle?.end,
            calendar.date(byAdding: .month, value: 4, to: firstSubscribedAt)
        )
        XCTAssertEqual(
            snapshot.modelUsage.subscriptionCycle.entries.map(\.model),
            ["gpt-5.6-sol", "codex-auto-review"]
        )
        XCTAssertEqual(snapshot.modelUsage.subscriptionCycle.totalTokens, 120)
    }

    func testWorkspaceUsageAggregatesAIWorktimeByRangeAndClampsLifecycle() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 19, hour: 12
        )))
        let store = try makeStore()

        try store.commit(batch(
            events: [
                usage(
                    "recent-1", at: now.addingTimeInterval(-5_400),
                    total: 10, threadID: "work", turnID: "turn-1"
                ),
                usage(
                    "recent-2", at: now.addingTimeInterval(-900),
                    total: 10, threadID: "work", turnID: "turn-2"
                ),
                usage(
                    "recent-3", at: now.addingTimeInterval(-300),
                    total: 10, threadID: "work", turnID: "turn-3"
                ),
                usage(
                    "old", at: now.addingTimeInterval(-40 * 86_400),
                    total: 10, threadID: "work", turnID: "old-turn"
                )
            ],
            quotas: [],
            stateEvents: [
                lifecycle(
                    "recent-1-start", threadID: "work", turnID: "turn-1",
                    kind: .started, at: now.addingTimeInterval(-7_200)
                ),
                lifecycle(
                    "recent-1-end", threadID: "work", turnID: "turn-1",
                    kind: .completed, at: now.addingTimeInterval(-5_400)
                ),
                lifecycle(
                    "recent-2-start", threadID: "work", turnID: "turn-2",
                    kind: .started, at: now.addingTimeInterval(-2_700)
                ),
                lifecycle(
                    "recent-2-end", threadID: "work", turnID: "turn-2",
                    kind: .completed, at: now.addingTimeInterval(-900)
                ),
                lifecycle(
                    "recent-3-start", threadID: "work", turnID: "turn-3",
                    kind: .started, at: now.addingTimeInterval(-300)
                ),
                lifecycle(
                    "old-start", threadID: "work", turnID: "old-turn",
                    kind: .started, at: now.addingTimeInterval(-(40 * 86_400 + 1_200))
                ),
                lifecycle(
                    "old-end", threadID: "work", turnID: "old-turn",
                    kind: .completed, at: now.addingTimeInterval(-40 * 86_400)
                )
            ],
            sessions: [
                session(
                    threadID: "work",
                    updatedAtMilliseconds: Int64((now.timeIntervalSince1970 * 1_000).rounded()),
                    activity: .running,
                    activeTurnID: "turn-3"
                )
            ]
        ))

        let snapshot = try DashboardQueryService(store: store).snapshot(
            now: now,
            calendar: calendar
        )

        let rankings = [
            snapshot.workspaceUsage.today,
            snapshot.workspaceUsage.sevenDays,
            snapshot.workspaceUsage.thirtyDays,
            snapshot.workspaceUsage.allTime
        ]
        XCTAssertEqual(
            rankings.map(\.totalAIWorktimeMilliseconds),
            [3_900_000, 3_900_000, 3_900_000, 5_100_000]
        )
        XCTAssertEqual(
            rankings.map { $0.entries.first?.aiWorktimeMilliseconds },
            [3_900_000, 3_900_000, 3_900_000, 5_100_000]
        )
        XCTAssertEqual(
            snapshot.workspaceUsage.today.todayTasks.map(\.aiWorktimeMilliseconds),
            [3_900_000]
        )
        XCTAssertEqual(
            snapshot.workspaceUsage.today.todayTasks.first?.conversation.replies
                .map(\.aiWorktimeMilliseconds)
                .reduce(0, +),
            3_900_000
        )
    }

    func testAllTimeWorktimeSumsSeparateLifecycleSegmentsWithoutCountingTheGap() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.commit(batch(
            events: [
                usage(
                    "reply", at: now.addingTimeInterval(-10), total: 10,
                    threadID: "reused-thread", turnID: "reused-turn"
                )
            ],
            quotas: [],
            stateEvents: [
                lifecycle(
                    "first-start", threadID: "reused-thread", turnID: "reused-turn",
                    kind: .started, at: now.addingTimeInterval(-120)
                ),
                lifecycle(
                    "first-end", threadID: "reused-thread", turnID: "reused-turn",
                    kind: .completed, at: now.addingTimeInterval(-110)
                ),
                lifecycle(
                    "second-start", threadID: "reused-thread", turnID: "reused-turn",
                    kind: .started, at: now.addingTimeInterval(-30)
                ),
                lifecycle(
                    "second-end", threadID: "reused-thread", turnID: "reused-turn",
                    kind: .completed, at: now.addingTimeInterval(-10)
                )
            ]
        ))

        let ranking = try DashboardQueryService(store: store)
            .snapshot(now: now, calendar: .current)
            .workspaceUsage.allTime

        XCTAssertEqual(ranking.totalAIWorktimeMilliseconds, 30_000)
        XCTAssertEqual(ranking.entries.first?.aiWorktimeMilliseconds, 30_000)
    }

    func testAllTimeWorktimeOnlyExtendsUnfinishedLifecycleForTheActiveTurn() throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let store = try makeStore()
        try store.commit(batch(
            events: [
                usage(
                    "stale", at: now.addingTimeInterval(-290), total: 10,
                    threadID: "stale-thread", turnID: "stale-turn"
                ),
                usage(
                    "active", at: now.addingTimeInterval(-20), total: 10,
                    threadID: "active-thread", turnID: "active-turn"
                )
            ],
            quotas: [],
            stateEvents: [
                lifecycle(
                    "stale-start", threadID: "stale-thread", turnID: "stale-turn",
                    kind: .started, at: now.addingTimeInterval(-300)
                ),
                lifecycle(
                    "active-start", threadID: "active-thread", turnID: "active-turn",
                    kind: .started, at: now.addingTimeInterval(-30)
                )
            ],
            sessions: [
                session(
                    threadID: "stale-thread",
                    updatedAtMilliseconds: Int64((now.addingTimeInterval(-290).timeIntervalSince1970 * 1_000).rounded())
                ),
                session(
                    threadID: "active-thread",
                    updatedAtMilliseconds: Int64((now.addingTimeInterval(-20).timeIntervalSince1970 * 1_000).rounded()),
                    activity: .running,
                    activeTurnID: "active-turn"
                )
            ]
        ))

        let ranking = try DashboardQueryService(store: store)
            .snapshot(now: now, calendar: .current)
            .workspaceUsage.allTime

        XCTAssertEqual(ranking.totalAIWorktimeMilliseconds, 30_000)
        let replies = ranking.entries.flatMap(\.conversations).flatMap(\.replies)
        XCTAssertEqual(replies.first { $0.id == "stale-turn" }?.aiWorktimeMilliseconds, 0)
        XCTAssertEqual(replies.first { $0.id == "active-turn" }?.aiWorktimeMilliseconds, 30_000)
    }

    func testSnapshotGroupsUsageIntoAnchoredSubscriptionCycleTrend() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let firstSubscribedAt = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 1, day: 31, hour: 9, minute: 30
        )))
        let februaryBoundary = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 2, day: 28, hour: 9, minute: 30
        )))
        let marchBoundary = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 3, day: 31, hour: 9, minute: 30
        )))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 4, day: 15, hour: 12
        )))
        let store = try makeStore()
        try store.commit(batch(
            events: [
                usage("before-subscription", at: firstSubscribedAt.addingTimeInterval(-1), total: 90),
                usage("first-cycle", at: firstSubscribedAt, total: 100),
                usage("second-cycle-boundary", at: februaryBoundary, total: 200),
                usage("second-cycle-latest", at: marchBoundary.addingTimeInterval(-1), total: 300),
                usage("third-cycle-boundary", at: marchBoundary, total: 400),
                usage("third-cycle-current", at: now, total: 500),
                usage("future", at: now.addingTimeInterval(1), total: 600)
            ],
            quotas: []
        ))

        let snapshot = try DashboardQueryService(store: store).snapshot(
            now: now,
            calendar: calendar,
            firstSubscriptionDate: firstSubscribedAt
        )

        XCTAssertEqual(
            snapshot.subscriptionCycleUsage.map(\.id),
            ["2026-01-31T09:30", "2026-02-28T09:30", "2026-03-31T09:30"]
        )
        XCTAssertEqual(
            snapshot.subscriptionCycleUsage.map(\.day),
            ["1/31–2/28", "2/28–3/31", "3/31–4/30"]
        )
        XCTAssertEqual(snapshot.subscriptionCycleUsage.map(\.total), [100, 500, 900])
    }

    func testSubscriptionCycleTrendIncludesGPT55ReferencePricedModels() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let firstSubscribedAt = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 1, hour: 9
        )))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 15, hour: 12
        )))
        let store = try makeStore()
        try store.commit(batch(events: [
            usage(
                "sol-cycle-cost",
                at: firstSubscribedAt.addingTimeInterval(60),
                total: 10_000_000,
                usage: .init(
                    uncachedInput: 1_000_000,
                    cachedInput: 2_000_000,
                    visibleOutput: 3_000_000,
                    reasoning: 4_000_000
                ),
                model: "gpt-5.6-sol"
            ),
            usage(
                "terra-cycle-cost",
                at: firstSubscribedAt.addingTimeInterval(120),
                total: 4_000_000,
                usage: .init(
                    uncachedInput: 1_000_000,
                    cachedInput: 1_000_000,
                    visibleOutput: 1_000_000,
                    reasoning: 1_000_000
                ),
                model: "gpt-5.6-terra"
            ),
            usage(
                "unpriced-cycle-cost",
                at: firstSubscribedAt.addingTimeInterval(180),
                total: 100,
                model: "codex-auto-review"
            )
        ], quotas: []))

        let cycle = try XCTUnwrap(
            DashboardQueryService(store: store).snapshot(
                now: now,
                calendar: calendar,
                firstSubscriptionDate: firstSubscribedAt
            ).subscriptionCycleUsage.first
        )

        XCTAssertEqual(try XCTUnwrap(cycle.estimatedCostUSD), 171.0005, accuracy: 0.000_001)
        XCTAssertEqual(cycle.unpricedModelCount, 0)
        XCTAssertEqual(cycle.referencePricedModelCount, 1)
        XCTAssertEqual(cycle.modelEntries.count, 3)
        XCTAssertEqual(cycle.modelEntries.reduce(0) { $0 + $1.totalTokens }, cycle.total)
        XCTAssertEqual(cycle.modelEntries.reduce(0) { $0 + ($1.estimatedCostUSD ?? 0) },
                       try XCTUnwrap(cycle.estimatedCostUSD), accuracy: 0.000_001)
        XCTAssertEqual(cycle.modelEntries.first?.model, "gpt-5.6-sol")
    }

    func testModelTrendSeriesKeepsDatesAndFillsMissingModelDaysWithZero() throws {
        let entry = ModelUsageEntry(model: "gpt-5.6-sol", totalTokens: 100,
                                    uncachedInputTokens: 40, cachedInputTokens: 30,
                                    visibleOutputTokens: 20, reasoningTokens: 10,
                                    share: 1, estimatedCostUSD: 0.000772)
        let days = [
            DailyUsage(id: "2026-07-11", day: "7/11", total: 100, modelEntries: [entry]),
            DailyUsage(id: "2026-07-12", day: "7/12", total: 0)
        ]
        let series = UsageTrendSeries.make(from: days)
        XCTAssertEqual(series.map(\.id), ["total", "model:gpt-5.6-sol"])
        let model = try XCTUnwrap(series.last)
        XCTAssertEqual(model.points.map(\.id), days.map(\.id))
        XCTAssertEqual(model.points.map(\.total), [100, 0])
        XCTAssertEqual(model.points[0].uncachedInput, 40)
        XCTAssertEqual(model.points[0].cachedInput, 30)
        XCTAssertEqual(model.points[0].output, 20)
        XCTAssertEqual(model.points[0].reasoning, 10)
        XCTAssertEqual(model.points[0].estimatedCostUSD, entry.estimatedCostUSD)
        XCTAssertEqual(model.points[1].estimatedCostUSD, 0)
        XCTAssertTrue(model.points.allSatisfy { $0.modelEntries.isEmpty })
        XCTAssertEqual(UsageTrendSeries.make(from: []).count, 1)
    }

    func testTrendHoverChoosesNearestDateThenNearestVisibleSeries() {
        let targets = [
            UsageTrendHitTarget(selection: .init(seriesID: "total", dayID: "day-a"), position: CGPoint(x: 10, y: 20)),
            UsageTrendHitTarget(selection: .init(seriesID: "model:a", dayID: "day-a"), position: CGPoint(x: 10, y: 80)),
            UsageTrendHitTarget(selection: .init(seriesID: "total", dayID: "day-b"), position: CGPoint(x: 30, y: 80))
        ]
        XCTAssertEqual(UsageTrendHitTarget.nearest(to: CGPoint(x: 12, y: 75), in: targets),
                       UsageTrendSelection(seriesID: "model:a", dayID: "day-a"))
        XCTAssertEqual(UsageTrendHitTarget.nearest(to: CGPoint(x: 12, y: 25), in: targets),
                       UsageTrendSelection(seriesID: "total", dayID: "day-a"))
        XCTAssertEqual(UsageTrendHitTarget.nearest(to: CGPoint(x: 29, y: 20), in: targets),
                       UsageTrendSelection(seriesID: "total", dayID: "day-b"))
        XCTAssertNil(UsageTrendHitTarget.nearest(to: .zero, in: []))
    }

    func testDailyModelBreakdownAggregatesRepeatedModelsAndReferenceCosts() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-12T12:00:00Z"))
        let store = try makeStore()
        try store.commit(batch(events: [
            usage("sol-a", at: now.addingTimeInterval(-60), total: 100,
                  usage: .init(uncachedInput: 40, cachedInput: 30, visibleOutput: 20, reasoning: 10),
                  model: "gpt-5.6-sol"),
            usage("sol-b", at: now, total: 100,
                  usage: .init(uncachedInput: 10, cachedInput: 20, visibleOutput: 30, reasoning: 40),
                  model: "gpt-5.6-sol"),
            usage("reference", at: now, total: 100, model: "unknown-daily-model"),
            usage("previous-day", at: now.addingTimeInterval(-86_400), total: 500, model: "gpt-5.6-terra")
        ], quotas: []))
        let snapshot = try DashboardQueryService(store: store).snapshot(
            now: now, calendar: CodexUsageCalendar.utc, usageCalendar: CodexUsageCalendar.utc
        )
        let day = try XCTUnwrap(snapshot.dailyUsage.first { $0.id == "2026-07-12" })
        XCTAssertEqual(day.modelEntries.map(\.model), ["gpt-5.6-sol", "unknown-daily-model"])
        let sol = try XCTUnwrap(day.modelEntries.first)
        XCTAssertEqual(sol.totalTokens, 200)
        XCTAssertEqual(sol.uncachedInputTokens, 50)
        XCTAssertEqual(sol.cachedInputTokens, 50)
        XCTAssertEqual(sol.visibleOutputTokens, 50)
        XCTAssertEqual(sol.reasoningTokens, 50)
        XCTAssertEqual(sol.share, 2.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(sol.estimatedCostUSD), 0.00222, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(day.estimatedCostUSD), 0.00272, accuracy: 0.000_001)
        XCTAssertEqual(day.referencePricedModelCount, 1)
        XCTAssertEqual(day.unpricedModelCount, 0)
        XCTAssertEqual(day.modelEntries.reduce(0) { $0 + $1.totalTokens }, day.total)
        XCTAssertTrue(snapshot.dailyUsage.filter { $0.total == 0 }.allSatisfy {
            $0.modelEntries.isEmpty && $0.estimatedCostUSD == 0 && $0.referencePricedModelCount == 0
        })
    }

    func testDailyUsageUsesCodexUTCDateWithoutChangingLocalTodayWindow() throws {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(localCalendar.date(from: DateComponents(
            year: 2026, month: 7, day: 12, hour: 12
        )))
        let eventDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-11T16:05:00Z"))
        let store = try makeStore()
        try store.commit(batch(events: [usage("utc-boundary", at: eventDate, total: 100)], quotas: []))

        let snapshot = try DashboardQueryService(store: store).snapshot(
            now: now,
            calendar: localCalendar,
            usageCalendar: CodexUsageCalendar.utc
        )

        XCTAssertEqual(snapshot.periods.first?.total, 100, "北京时间仍属于 7 月 12 日的今日用量")
        XCTAssertEqual(snapshot.dailyUsage.first { $0.id == "2026-07-11" }?.total, 100)
        XCTAssertEqual(snapshot.dailyUsage.first { $0.id == "2026-07-12" }?.total, 0)
        XCTAssertEqual(CodexUsageCalendar.utc.timeZone.secondsFromGMT(), 0)
    }

    func testBuildsLocalDayPeriodsTrendModelsQuotasAndDeterministicPlan() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 14, hour: 12
        )))
        let todayStart = calendar.startOfDay(for: now)
        let sevenDayStart = try XCTUnwrap(calendar.date(byAdding: .day, value: -6, to: todayStart))
        let thirtyDayStart = try XCTUnwrap(calendar.date(byAdding: .day, value: -29, to: todayStart))
        let store = try makeStore()

        let events = [
            usage("today", at: todayStart.addingTimeInterval(60), total: 160,
                  usage: .init(uncachedInput: 100, cachedInput: 20, visibleOutput: 30, reasoning: 10)),
            usage("before-today", at: todayStart.addingTimeInterval(-1), total: 200),
            usage("seven-start", at: sevenDayStart, total: 300),
            usage("before-seven", at: sevenDayStart.addingTimeInterval(-1), total: 400),
            usage("thirty-start", at: thirtyDayStart, total: 500),
            usage("before-thirty", at: thirtyDayStart.addingTimeInterval(-1), total: 600),
            usage("latest-a", at: now.addingTimeInterval(-1), total: 1, model: "model-a", planRaw: "free"),
            usage("latest-z", at: now.addingTimeInterval(-1), total: 1, model: "model-z", planRaw: "plus")
        ]
        try store.commit(batch(
            events: events,
            quotas: [
                quota("5h", kind: .fiveHour, now: now, reset: now.addingTimeInterval(2 * 3_600)),
                quota("7d", kind: .weekly, now: now, reset: now.addingTimeInterval(7 * 86_400))
            ]
        ))

        let snapshot = try DashboardQueryService(store: store).snapshot(now: now, calendar: calendar)

        XCTAssertEqual(snapshot.periods.map(\.id), ["today", "sevenDays", "thirtyDays", "allTime"])
        XCTAssertEqual(snapshot.periods.map(\.title), ["今日", "7 日", "30 日", "累计"])
        XCTAssertEqual(snapshot.periods.map(\.total), [162, 662, 1_562, 2_162])
        XCTAssertEqual(snapshot.breakdown.input, 102)
        XCTAssertEqual(snapshot.breakdown.cachedInput, 20)
        XCTAssertEqual(snapshot.breakdown.output, 30)
        XCTAssertEqual(snapshot.breakdown.reasoning, 10)
        XCTAssertEqual(snapshot.periods.first?.output, 40, "PeriodUsage.output remains raw output")
        XCTAssertEqual(snapshot.visibleQuotas.map(\.id), ["7d"])
        XCTAssertEqual(snapshot.visibleQuotas.map(\.resetText), ["07-21"])
        XCTAssertEqual(snapshot.planName, "Plus")
        XCTAssertTrue(snapshot.issues.isEmpty)
        XCTAssertEqual(snapshot.dailyUsage.count, 31)
        XCTAssertEqual(snapshot.dailyUsage.map(\.id), snapshot.dailyUsage.map(\.id).sorted())
        XCTAssertTrue(snapshot.dailyUsage.contains { $0.total == 0 })
        let todayUsage = try XCTUnwrap(snapshot.dailyUsage.first { $0.id == "2026-07-14" })
        XCTAssertEqual(todayUsage.total, 162)
        XCTAssertEqual(todayUsage.uncachedInput, 102)
        XCTAssertEqual(todayUsage.cachedInput, 20)
        XCTAssertEqual(todayUsage.output, 30)
        XCTAssertEqual(todayUsage.reasoning, 10)
        XCTAssertTrue(snapshot.dailyUsage.filter { $0.total == 0 }.allSatisfy {
            $0.uncachedInput == 0
                && $0.cachedInput == 0
                && $0.output == 0
                && $0.reasoning == 0
        })
        XCTAssertEqual(snapshot.models.first?.name, "test-model")
        XCTAssertEqual(snapshot.models.reduce(0) { $0 + $1.share }, 1, accuracy: 0.000_001)
        XCTAssertTrue(snapshot.models.allSatisfy { $0.share.isFinite && $0.share >= 0 })
    }

    func testQuotaResetFormatterShowsTimeOnlyOnResetDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 21, hour: 23, minute: 30
        )))
        let sameDayReset = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 21, hour: 23, minute: 58
        )))
        let nextDayReset = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 22, hour: 0, minute: 8
        )))

        XCTAssertEqual(
            QuotaResetFormatter.string(
                resetsAtMilliseconds: Int64(sameDayReset.timeIntervalSince1970 * 1_000),
                now: now,
                calendar: calendar
            ),
            "23:58"
        )
        XCTAssertEqual(
            QuotaResetFormatter.string(
                resetsAtMilliseconds: Int64(nextDayReset.timeIntervalSince1970 * 1_000),
                now: now,
                calendar: calendar
            ),
            "07-22"
        )
    }

    func testIgnoresFiveHourQuotaAndReportsInvalidWeeklyQuota() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.commit(batch(
            events: [],
            quotas: [
                quota("expired", kind: .fiveHour, now: now, reset: now.addingTimeInterval(-1)),
                quota("missing-reset", kind: .weekly, now: now, reset: nil)
            ]
        ))

        let snapshot = try DashboardQueryService(store: store).snapshot(now: now, calendar: calendar)

        XCTAssertTrue(snapshot.visibleQuotas.isEmpty)
        XCTAssertEqual(Set(snapshot.issues), [.invalidQuota(id: "7d")])
    }

    func testReturnsFourZeroPeriodsWhenStoreHasNoUsage() throws {
        let snapshot = try DashboardQueryService(store: makeStore()).snapshot(
            now: Date(timeIntervalSince1970: 1_000),
            calendar: .current
        )

        XCTAssertEqual(snapshot.periods.count, 4)
        XCTAssertTrue(snapshot.periods.allSatisfy { $0.total == 0 })
        XCTAssertTrue(snapshot.quotas.isEmpty)
        XCTAssertTrue(snapshot.models.isEmpty)
        XCTAssertTrue(snapshot.dailyUsage.isEmpty)
        XCTAssertEqual(snapshot.planName, "Free")
        XCTAssertEqual(snapshot.activityRankings, .empty)
        XCTAssertEqual(snapshot.workspaceUsage, .empty)
    }

    func testBuildsWorkspaceUsageForTodaySevenThirtyAndAllTimeRanges() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 14, hour: 12
        )))
        let todayStart = calendar.startOfDay(for: now)
        let sevenDayStart = try XCTUnwrap(calendar.date(byAdding: .day, value: -6, to: todayStart))
        let thirtyDayStart = try XCTUnwrap(calendar.date(byAdding: .day, value: -29, to: todayStart))
        let projectA = ProjectIdentity(id: "project-a", name: "CodexVista")
        let projectB = ProjectIdentity(id: "project-b", name: "Website")
        let sameNameDifferentPath = ProjectIdentity(id: "project-c", name: "CodexVista")
        let legacy = ProjectIdentity(id: "project-legacy", name: "Legacy")
        let future = ProjectIdentity(id: "project-future", name: "Future")
        let store = try makeStore()
        try store.commit(batch(events: [
            usage("a-today", at: todayStart.addingTimeInterval(60), total: 100, project: projectA),
            usage("a-seven-edge", at: sevenDayStart, total: 20, project: projectA),
            usage("b-before-seven", at: sevenDayStart.addingTimeInterval(-1), total: 80, project: projectB),
            usage("same-name", at: thirtyDayStart, total: 30, project: sameNameDifferentPath),
            usage("legacy", at: thirtyDayStart.addingTimeInterval(-1), total: 50, project: legacy),
            usage("future", at: now.addingTimeInterval(86_400), total: 1_000, project: future)
        ], quotas: []))

        let snapshot = try DashboardQueryService(store: store).snapshot(now: now, calendar: calendar)
        let today = snapshot.workspaceUsage.ranking(for: .today)
        let sevenDays = snapshot.workspaceUsage.ranking(for: .sevenDays)
        let thirtyDays = snapshot.workspaceUsage.ranking(for: .thirtyDays)
        let allTime = snapshot.workspaceUsage.ranking(for: .allTime)

        XCTAssertEqual(today.entries.map(\.id), ["workspace-project-a"])
        XCTAssertEqual(today.workspaceCount, 1)
        XCTAssertEqual(today.projectCount, 1)
        XCTAssertEqual(today.totalTokens, 100)
        XCTAssertEqual(today.entries.first?.dailyUsage.count, 7)
        XCTAssertEqual(today.entries.first?.dailyUsage.map(\.tokens), [20, 0, 0, 0, 0, 0, 100])
        XCTAssertEqual(sevenDays.entries.map(\.id), ["workspace-project-a"])
        XCTAssertEqual(sevenDays.totalTokens, 120)
        XCTAssertEqual(sevenDays.entries.first?.share, 1)
        XCTAssertEqual(thirtyDays.entries.map(\.tokens), [120, 80, 30])
        XCTAssertEqual(thirtyDays.workspaceCount, 3)
        XCTAssertEqual(thirtyDays.projectCount, 3)
        XCTAssertEqual(allTime.totalTokens, 280)
        XCTAssertEqual(allTime.workspaceCount, 4)
        XCTAssertEqual(allTime.projectCount, 4)
        XCTAssertEqual(allTime.entries.filter { $0.name == "CodexVista" }.count, 2,
                       "Same leaf names from different project paths remain distinct")
        XCTAssertFalse(allTime.entries.contains { $0.id == "workspace-project-future" })
    }

    func testProjectUsageIncludesConversationsSortedByLastMessageWithUsageSortAvailable() throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let recentMessageAt = Int64((now.addingTimeInterval(-60).timeIntervalSince1970 * 1_000).rounded())
        let olderMessageAt = Int64((now.addingTimeInterval(-120).timeIntervalSince1970 * 1_000).rounded())
        let project = ProjectIdentity(id: "project-a", name: "CodexVista")
        let store = try makeStore()
        try store.commit(batch(
            events: [
                usage(
                    "recent-a", at: now.addingTimeInterval(-30), total: 30,
                    usage: .init(
                        uncachedInput: 10,
                        cachedInput: 5,
                        visibleOutput: 10,
                        reasoning: 5
                    ),
                    project: project, threadID: "recent-thread", turnID: "recent-turn-1"
                ),
                usage(
                    "recent-b", at: now.addingTimeInterval(-20), total: 20,
                    project: project, threadID: "recent-thread", turnID: "recent-turn-2"
                ),
                usage(
                    "older", at: now.addingTimeInterval(-10), total: 100,
                    project: project, threadID: "older-thread"
                )
            ],
            quotas: [],
            stateEvents: [
                lifecycle(
                    "recent-start-1", threadID: "recent-thread", turnID: "recent-turn-1",
                    kind: .started, at: now.addingTimeInterval(-40)
                ),
                lifecycle(
                    "recent-complete-1", threadID: "recent-thread", turnID: "recent-turn-1",
                    kind: .completed, at: now.addingTimeInterval(-25)
                ),
                lifecycle(
                    "recent-start-2", threadID: "recent-thread", turnID: "recent-turn-2",
                    kind: .started, at: now.addingTimeInterval(-22)
                )
            ],
            activityEvents: [
                activity(
                    "recent-skill", kind: .skill, name: "build-macos-apps:swiftui-patterns",
                    at: now.addingTimeInterval(-38),
                    threadID: "recent-thread", turnID: "recent-turn-1"
                ),
                activity(
                    "recent-tool-1", kind: .tool, name: "exec_command",
                    at: now.addingTimeInterval(-37),
                    threadID: "recent-thread", turnID: "recent-turn-1"
                ),
                activity(
                    "recent-tool-2", kind: .tool, name: "exec_command",
                    at: now.addingTimeInterval(-36),
                    threadID: "recent-thread", turnID: "recent-turn-1"
                ),
                activity(
                    "recent-tool-3", kind: .tool, name: "view_image",
                    at: now.addingTimeInterval(-35),
                    threadID: "recent-thread", turnID: "recent-turn-1"
                ),
                activity(
                    "unattributed-tool", kind: .tool, name: "ignored",
                    at: now.addingTimeInterval(-34),
                    threadID: "recent-thread", turnID: nil
                )
            ],
            sessions: [
                session(
                    threadID: "recent-thread",
                    updatedAtMilliseconds: recentMessageAt,
                    activity: .running,
                    activeTurnID: "recent-turn-2"
                ),
                session(threadID: "older-thread", updatedAtMilliseconds: olderMessageAt)
            ]
        ))

        let ranking = try DashboardQueryService(store: store)
            .snapshot(
                now: now,
                calendar: .current,
                threadTitlesByThreadID: ["recent-thread": "工作区用量对话名称"]
            )
            .workspaceUsage
            .ranking(for: .allTime)
        let entry = try XCTUnwrap(ranking.entries.first)

        XCTAssertEqual(entry.conversations.map(\.tokens), [50, 100])
        XCTAssertEqual(
            entry.conversations.map(\.lastMessageAtMilliseconds),
            [recentMessageAt, olderMessageAt]
        )
        XCTAssertTrue(entry.conversations.allSatisfy { $0.shortThreadID.hasPrefix("thread-") })
        XCTAssertFalse(entry.conversations.contains { $0.shortThreadID == "recent-thread" })
        XCTAssertEqual(entry.conversations.map(\.displayTitle), ["工作区用量对话名称", nil])
        let recentReplies = entry.conversations[0].replies
        XCTAssertEqual(recentReplies.map(\.id), ["recent-turn-2", "recent-turn-1"])
        XCTAssertEqual(recentReplies.map(\.status), [.inProgress, .completed])
        XCTAssertEqual(recentReplies[1].uncachedInputTokens, 10)
        XCTAssertEqual(recentReplies[1].cachedInputTokens, 5)
        XCTAssertEqual(recentReplies[1].visibleOutputTokens, 10)
        XCTAssertEqual(recentReplies[1].reasoningTokens, 5)
        XCTAssertEqual(recentReplies[1].durationMilliseconds, 15_000)
        XCTAssertEqual(recentReplies.map(\.aiWorktimeMilliseconds), [22_000, 15_000])
        XCTAssertEqual(entry.aiWorktimeMilliseconds, 37_000)
        XCTAssertEqual(
            recentReplies[1].skillCalls,
            [ProjectReplyActivityCall(
                name: "build-macos-apps:swiftui-patterns",
                count: 1
            )]
        )
        XCTAssertEqual(
            recentReplies[1].toolCalls,
            [
                ProjectReplyActivityCall(name: "exec_command", count: 2),
                ProjectReplyActivityCall(name: "view_image", count: 1)
            ]
        )
        XCTAssertEqual(recentReplies[1].skillCallCount, 1)
        XCTAssertEqual(recentReplies[1].toolCallCount, 3)
        XCTAssertTrue(recentReplies[0].skillCalls.isEmpty)
        XCTAssertTrue(recentReplies[0].toolCalls.isEmpty)
        XCTAssertEqual(entry.conversations[1].unattributedTokens, 100)
        XCTAssertEqual(
            ProjectConversationSortOrder.usage.sorted(entry.conversations).map(\.tokens),
            [100, 50]
        )
    }

    func testTodayTasksPrioritizeRunningThenSortSameStatusByLatestUpdate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 24, hour: 16
        )))
        let project = ProjectIdentity(id: "project-a", name: "CodexVista")
        let store = try makeStore()
        try store.commit(batch(
            events: [
                usage(
                    "running", at: now.addingTimeInterval(-40), total: 40,
                    usage: .init(
                        uncachedInput: 10,
                        cachedInput: 15,
                        visibleOutput: 9,
                        reasoning: 6
                    ),
                    project: project, threadID: "running-thread", turnID: "running-turn"
                ),
                usage(
                    "completed-new", at: now.addingTimeInterval(-30), total: 30,
                    project: project, threadID: "completed-new-thread", turnID: "completed-new-turn"
                ),
                usage(
                    "completed-old", at: now.addingTimeInterval(-20), total: 20,
                    project: project, threadID: "completed-old-thread", turnID: "completed-old-turn"
                )
            ],
            quotas: [],
            stateEvents: [
                lifecycle(
                    "running-start", threadID: "running-thread", turnID: "running-turn",
                    kind: .started, at: now.addingTimeInterval(-45)
                ),
                lifecycle(
                    "completed-new-start", threadID: "completed-new-thread",
                    turnID: "completed-new-turn", kind: .started,
                    at: now.addingTimeInterval(-40)
                ),
                lifecycle(
                    "completed-new-end", threadID: "completed-new-thread",
                    turnID: "completed-new-turn", kind: .completed,
                    at: now.addingTimeInterval(-25)
                ),
                lifecycle(
                    "completed-old-start", threadID: "completed-old-thread",
                    turnID: "completed-old-turn", kind: .started,
                    at: now.addingTimeInterval(-35)
                ),
                lifecycle(
                    "completed-old-end", threadID: "completed-old-thread",
                    turnID: "completed-old-turn", kind: .completed,
                    at: now.addingTimeInterval(-15)
                )
            ],
            sessions: [
                session(
                    threadID: "running-thread",
                    updatedAtMilliseconds: Int64((now.addingTimeInterval(-10).timeIntervalSince1970 * 1_000).rounded()),
                    activity: .running,
                    activeTurnID: "running-turn"
                ),
                session(
                    threadID: "completed-new-thread",
                    updatedAtMilliseconds: Int64((now.addingTimeInterval(-5).timeIntervalSince1970 * 1_000).rounded())
                ),
                session(
                    threadID: "completed-old-thread",
                    updatedAtMilliseconds: Int64((now.addingTimeInterval(-15).timeIntervalSince1970 * 1_000).rounded())
                )
            ]
        ))

        let tasks = try DashboardQueryService(store: store)
            .snapshot(
                now: now,
                calendar: calendar,
                threadTitlesByThreadID: [
                    "running-thread": "进行中的任务",
                    "completed-new-thread": "最近完成的任务",
                    "completed-old-thread": "较早完成的任务"
                ]
            )
            .workspaceUsage.today.todayTasks

        XCTAssertEqual(tasks.map(\.title), ["进行中的任务", "最近完成的任务", "较早完成的任务"])
        XCTAssertEqual(tasks.map(\.status), [.inProgress, .completed, .completed])
        XCTAssertEqual(tasks.first?.workspace.name, "CodexVista")
        XCTAssertEqual(tasks.first?.conversation.tokens, 40)
        XCTAssertEqual(tasks.first?.tokenBreakdown.input, 10)
        XCTAssertEqual(tasks.first?.tokenBreakdown.cachedInput, 15)
        XCTAssertEqual(tasks.first?.tokenBreakdown.output, 9)
        XCTAssertEqual(tasks.first?.tokenBreakdown.reasoning, 6)
        XCTAssertEqual(tasks.first?.unattributedTokens, 0)
        XCTAssertEqual(tasks.map(\.aiWorktimeMilliseconds), [45_000, 15_000, 20_000])
    }

    func testSubagentUsageMergesIntoReplyThatSpawnedIt() throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let project = ProjectIdentity(id: "project-a", name: "CodexVista")
        let store = try makeStore()
        try store.commit(batch(
            events: [
                usage(
                    "parent-shared", at: now.addingTimeInterval(-40), total: 30,
                    model: "parent-model", project: project,
                    threadID: "parent-thread", turnID: "shared-turn"
                ),
                usage(
                    "child-shared", at: now.addingTimeInterval(-30), total: 20,
                    model: "child-model", project: project,
                    threadID: "child-thread", turnID: "child-turn"
                ),
                usage(
                    "child-shared-later-snapshot", at: now.addingTimeInterval(-25), total: 5,
                    model: "child-model", project: project,
                    threadID: "child-thread", turnID: "child-turn"
                ),
                usage(
                    "parent-other", at: now.addingTimeInterval(-10), total: 10,
                    model: "parent-model", project: project,
                    threadID: "parent-thread", turnID: "other-turn"
                )
            ],
            quotas: [],
            stateEvents: [
                lifecycle(
                    "parent-start", threadID: "parent-thread", turnID: "shared-turn",
                    kind: .started, at: now.addingTimeInterval(-50)
                ),
                lifecycle(
                    "child-start", threadID: "child-thread", turnID: "child-turn",
                    kind: .started, at: now.addingTimeInterval(-34)
                ),
                lifecycle(
                    "child-complete", threadID: "child-thread", turnID: "child-turn",
                    kind: .completed, at: now.addingTimeInterval(-20)
                ),
                lifecycle(
                    "parent-complete", threadID: "parent-thread", turnID: "shared-turn",
                    kind: .completed, at: now.addingTimeInterval(-5)
                )
            ],
            activityEvents: [
                activity(
                    "parent-spawn", kind: .tool, name: "spawn_agent",
                    at: now.addingTimeInterval(-35),
                    threadID: "parent-thread", turnID: "shared-turn"
                ),
                activity(
                    "child-tool", kind: .tool, name: "exec_command",
                    at: now.addingTimeInterval(-25),
                    threadID: "child-thread", turnID: "shared-turn"
                ),
                activity(
                    "child-skill", kind: .skill, name: "ai-code-review",
                    at: now.addingTimeInterval(-24),
                    threadID: "child-thread", turnID: "shared-turn"
                )
            ],
            sessions: [
                session(threadID: "parent-thread", updatedAtMilliseconds: 19_900_000),
                session(
                    threadID: "child-thread",
                    createdAtMilliseconds: 19_965_100,
                    updatedAtMilliseconds: 19_980_000
                )
            ]
        ))

        let entry = try XCTUnwrap(
            DashboardQueryService(store: store)
                .snapshot(
                    now: now,
                    calendar: .current,
                    threadTitlesByThreadID: [
                        "parent-thread": "主任务",
                        "child-thread": "Codex 子任务 · Ada"
                    ],
                    parentThreadIDsByChildThreadID: ["child-thread": "parent-thread"]
                )
                .workspaceUsage
                .ranking(for: .allTime)
                .entries
                .first
        )
        let projectEntry = try XCTUnwrap(entry.projects.first)

        XCTAssertEqual(entry.conversations.count, 1)
        let conversation = try XCTUnwrap(entry.conversations.first)
        XCTAssertEqual(conversation.displayTitle, "主任务")
        XCTAssertEqual(conversation.tokens, 65)
        XCTAssertEqual(conversation.aiWorktimeMilliseconds, 45_000)
        XCTAssertEqual(entry.aiWorktimeMilliseconds, 45_000)
        XCTAssertEqual(conversation.lastMessageAtMilliseconds, 19_980_000)
        XCTAssertEqual(conversation.replies.count, 2)
        XCTAssertEqual(
            conversation.modelCalls,
            [
                ProjectReplyActivityCall(name: "child-model", count: 1),
                ProjectReplyActivityCall(name: "parent-model", count: 2)
            ]
        )
        XCTAssertEqual(
            conversation.skillCalls,
            [ProjectReplyActivityCall(name: "ai-code-review", count: 1)]
        )
        XCTAssertEqual(
            conversation.toolCalls,
            [
                ProjectReplyActivityCall(name: "exec_command", count: 1),
                ProjectReplyActivityCall(name: "spawn_agent", count: 1)
            ]
        )
        XCTAssertEqual(projectEntry.conversationCount, 1)
        XCTAssertEqual(projectEntry.replyCount, 2)

        let sharedReply = try XCTUnwrap(conversation.replies.first { $0.id == "shared-turn" })
        XCTAssertEqual(sharedReply.totalTokens, 55)
        XCTAssertEqual(sharedReply.model, "child-model ×1 · parent-model ×1")
        XCTAssertEqual(sharedReply.status, .completed)
        XCTAssertEqual(sharedReply.durationMilliseconds, 45_000)
        XCTAssertEqual(sharedReply.aiWorktimeMilliseconds, 45_000)
        XCTAssertEqual(
            sharedReply.skillCalls,
            [ProjectReplyActivityCall(name: "ai-code-review", count: 1)]
        )
        XCTAssertEqual(
            sharedReply.toolCalls,
            [
                ProjectReplyActivityCall(name: "exec_command", count: 1),
                ProjectReplyActivityCall(name: "spawn_agent", count: 1)
            ]
        )
    }

    func testSubagentUsageFallsBackToActiveParentReplyWithoutSpawnActivity() throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let project = ProjectIdentity(id: "project-a", name: "CodexVista")
        let store = try makeStore()
        try store.commit(batch(
            events: [
                usage(
                    "parent", at: now.addingTimeInterval(-40), total: 30,
                    project: project, threadID: "parent-thread", turnID: "parent-turn"
                ),
                usage(
                    "child", at: now.addingTimeInterval(-20), total: 20,
                    project: project, threadID: "child-thread", turnID: "child-turn"
                )
            ],
            quotas: [],
            stateEvents: [
                lifecycle(
                    "parent-start", threadID: "parent-thread", turnID: "parent-turn",
                    kind: .started, at: now.addingTimeInterval(-50)
                ),
                lifecycle(
                    "child-complete", threadID: "child-thread", turnID: "child-turn",
                    kind: .completed, at: now.addingTimeInterval(-10)
                )
            ],
            sessions: [
                session(threadID: "parent-thread", updatedAtMilliseconds: 19_990_000),
                session(
                    threadID: "child-thread",
                    createdAtMilliseconds: 19_965_000,
                    updatedAtMilliseconds: 19_995_000
                )
            ]
        ))

        let conversation = try XCTUnwrap(
            DashboardQueryService(store: store)
                .snapshot(
                    now: now,
                    calendar: .current,
                    threadTitlesByThreadID: [
                        "parent-thread": "主任务",
                        "child-thread": "Codex 子任务"
                    ],
                    parentThreadIDsByChildThreadID: ["child-thread": "parent-thread"]
                )
                .workspaceUsage
                .ranking(for: .allTime)
                .entries.first?
                .conversations.first
        )

        XCTAssertEqual(conversation.replies.map(\.id), ["parent-turn"])
        XCTAssertEqual(conversation.replies.first?.totalTokens, 50)
    }

    func testSubagentReplyWorktimeBelongsToRootWorkspaceWithoutDoubleCounting() throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let parentProject = ProjectIdentity(id: "parent-project", name: "Parent")
        let childProject = ProjectIdentity(id: "child-project", name: "Child")
        let store = try makeStore()
        try store.commit(batch(
            events: [
                usage(
                    "parent", at: now.addingTimeInterval(-40), total: 30,
                    project: parentProject, threadID: "parent-thread", turnID: "parent-turn"
                ),
                usage(
                    "child", at: now.addingTimeInterval(-20), total: 20,
                    project: childProject, threadID: "child-thread", turnID: "child-turn"
                )
            ],
            quotas: [],
            stateEvents: [
                lifecycle(
                    "parent-start", threadID: "parent-thread", turnID: "parent-turn",
                    kind: .started, at: now.addingTimeInterval(-50)
                ),
                lifecycle(
                    "parent-end", threadID: "parent-thread", turnID: "parent-turn",
                    kind: .completed, at: now.addingTimeInterval(-5)
                )
            ],
            sessions: [
                session(threadID: "parent-thread", updatedAtMilliseconds: 19_990_000),
                session(
                    threadID: "child-thread",
                    createdAtMilliseconds: 19_965_000,
                    updatedAtMilliseconds: 19_995_000
                )
            ]
        ))

        let ranking = try DashboardQueryService(store: store)
            .snapshot(
                now: now,
                calendar: .current,
                threadTitlesByThreadID: [
                    "parent-thread": "主任务",
                    "child-thread": "子任务"
                ],
                parentThreadIDsByChildThreadID: ["child-thread": "parent-thread"]
            )
            .workspaceUsage.allTime

        XCTAssertEqual(ranking.totalAIWorktimeMilliseconds, 45_000)
        XCTAssertEqual(
            ranking.entries.first { $0.name == "Parent" }?.aiWorktimeMilliseconds,
            45_000
        )
        XCTAssertEqual(
            ranking.entries.first { $0.name == "Child" }?.aiWorktimeMilliseconds,
            0
        )
    }

    func testCompletedChildDoesNotCompleteRunningParentTask() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 24, hour: 16
        )))
        let project = ProjectIdentity(id: "project-a", name: "CodexVista")
        let store = try makeStore()
        try store.commit(batch(
            events: [
                usage(
                    "parent", at: now.addingTimeInterval(-40), total: 30,
                    project: project, threadID: "parent-thread", turnID: "parent-turn"
                ),
                usage(
                    "child", at: now.addingTimeInterval(-20), total: 20,
                    project: project, threadID: "child-thread", turnID: "child-turn"
                )
            ],
            quotas: [],
            stateEvents: [
                lifecycle(
                    "parent-start", threadID: "parent-thread", turnID: "parent-turn",
                    kind: .started, at: now.addingTimeInterval(-50)
                ),
                lifecycle(
                    "child-complete", threadID: "child-thread", turnID: "child-turn",
                    kind: .completed, at: now.addingTimeInterval(-10)
                )
            ],
            sessions: [
                session(
                    threadID: "parent-thread",
                    updatedAtMilliseconds: Int64((now.timeIntervalSince1970 * 1_000).rounded()),
                    activity: .running,
                    activeTurnID: "parent-turn"
                ),
                session(
                    threadID: "child-thread",
                    createdAtMilliseconds: Int64(
                        (now.addingTimeInterval(-30).timeIntervalSince1970 * 1_000).rounded()
                    ),
                    updatedAtMilliseconds: Int64(
                        (now.addingTimeInterval(-10).timeIntervalSince1970 * 1_000).rounded()
                    )
                )
            ]
        ))

        let task = try XCTUnwrap(
            DashboardQueryService(store: store)
                .snapshot(
                    now: now,
                    calendar: calendar,
                    threadTitlesByThreadID: [
                        "parent-thread": "仍在运行的主任务",
                        "child-thread": "已完成的子任务"
                    ],
                    parentThreadIDsByChildThreadID: ["child-thread": "parent-thread"]
                )
                .workspaceUsage.today.todayTasks.first
        )

        XCTAssertEqual(task.title, "仍在运行的主任务")
        XCTAssertEqual(task.status, .inProgress)
        XCTAssertEqual(task.aiWorktimeMilliseconds, 50_000)
    }

    func testGuardianUsageKeepsTokensButIsExcludedFromEveryTaskAndReplyMetric() throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let project = ProjectIdentity(id: "project-a", name: "CodexVista")
        let store = try makeStore()
        try store.commit(batch(
            events: [
                usage(
                    "visible", at: now.addingTimeInterval(-20), total: 30,
                    project: project, threadID: "visible-thread", turnID: "visible-turn"
                ),
                usage(
                    "guardian", at: now.addingTimeInterval(-10), total: 70,
                    project: project, threadID: "guardian-thread", turnID: "guardian-turn"
                )
            ],
            quotas: [],
            stateEvents: [
                lifecycle(
                    "visible-start", threadID: "visible-thread", turnID: "visible-turn",
                    kind: .started, at: now.addingTimeInterval(-30)
                ),
                lifecycle(
                    "visible-end", threadID: "visible-thread", turnID: "visible-turn",
                    kind: .completed, at: now.addingTimeInterval(-20)
                ),
                lifecycle(
                    "guardian-start", threadID: "guardian-thread", turnID: "guardian-turn",
                    kind: .started, at: now.addingTimeInterval(-18)
                ),
                lifecycle(
                    "guardian-end", threadID: "guardian-thread", turnID: "guardian-turn",
                    kind: .completed, at: now.addingTimeInterval(-10)
                )
            ],
            sessions: [
                session(threadID: "visible-thread", updatedAtMilliseconds: 10_000),
                session(threadID: "guardian-thread", updatedAtMilliseconds: 19_000)
            ]
        ))

        let entry = try XCTUnwrap(
            DashboardQueryService(store: store)
                .snapshot(
                    now: now,
                    calendar: .current,
                    threadTitlesByThreadID: [
                        "visible-thread": "可见任务",
                        "guardian-thread": "命令权限检查"
                    ],
                    parentThreadIDsByChildThreadID: [
                        "guardian-thread": "visible-thread"
                    ]
                )
                .workspaceUsage
                .ranking(for: .allTime)
                .entries
                .first
        )
        let projectEntry = try XCTUnwrap(entry.projects.first)

        XCTAssertEqual(entry.tokens, 100, "Internal checks still contribute to actual usage")
        XCTAssertEqual(entry.conversations.count, 2, "Raw conversations remain available for usage")
        XCTAssertEqual(entry.visibleConversations.map(\.displayTitle), ["可见任务"])
        XCTAssertEqual(entry.visibleReplyCount, 1)
        XCTAssertEqual(entry.aiWorktimeMilliseconds, 10_000)
        XCTAssertEqual(entry.lastVisibleActivityAtMilliseconds, 10_000)
        XCTAssertEqual(projectEntry.conversationCount, 1)
        XCTAssertEqual(projectEntry.replyCount, 1)
        XCTAssertEqual(projectEntry.lastActivityAtMilliseconds, 10_000)
    }

    func testBuildsModelUsageRankingWithPublishedAndReferencePrices() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 14, hour: 12
        )))
        let todayStart = calendar.startOfDay(for: now)
        let store = try makeStore()
        try store.commit(batch(events: [
            usage(
                "sol",
                at: todayStart.addingTimeInterval(60),
                total: 10_000_000,
                usage: .init(
                    uncachedInput: 1_000_000,
                    cachedInput: 2_000_000,
                    visibleOutput: 3_000_000,
                    reasoning: 4_000_000
                ),
                model: "gpt-5.6-sol"
            ),
            usage(
                "terra",
                at: todayStart.addingTimeInterval(120),
                total: 4_000_000,
                usage: .init(
                    uncachedInput: 1_000_000,
                    cachedInput: 1_000_000,
                    visibleOutput: 1_000_000,
                    reasoning: 1_000_000
                ),
                model: "gpt-5.6-terra"
            ),
            usage(
                "internal-review",
                at: todayStart.addingTimeInterval(180),
                total: 100,
                model: "codex-auto-review"
            )
        ], quotas: []))

        let ranking = try DashboardQueryService(store: store)
            .snapshot(now: now, calendar: calendar)
            .modelUsage
            .ranking(for: .today)

        XCTAssertEqual(ranking.entries.map(\.model), [
            "gpt-5.6-sol", "gpt-5.6-terra", "codex-auto-review"
        ])
        XCTAssertEqual(ranking.totalTokens, 14_000_100)
        XCTAssertEqual(ranking.entries.first?.uncachedInputTokens, 1_000_000)
        XCTAssertEqual(ranking.entries.first?.cachedInputTokens, 2_000_000)
        XCTAssertEqual(ranking.entries.first?.visibleOutputTokens, 3_000_000)
        XCTAssertEqual(ranking.entries.first?.reasoningTokens, 4_000_000)
        XCTAssertEqual(
            try XCTUnwrap(ranking.entries.first?.estimatedCostUSD),
            144.8,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(ranking.entries[1].estimatedCostUSD),
            26.2,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(ranking.entries.last?.estimatedCostUSD),
            0.0005,
            accuracy: 0.000_001
        )
        XCTAssertEqual(ranking.estimatedCostUSD, 171.0005, accuracy: 0.000_001)
        XCTAssertEqual(ranking.unpricedModelCount, 0)
        XCTAssertEqual(ranking.referencePricedModelCount, 1)
    }

    func testModelPricingCatalogUsesPublishedRatesAndGPT55ReferenceFallback() throws {
        let sol = try XCTUnwrap(ModelPricingCatalog.rule(for: "gpt-5.6-sol"))
        let expectedRates: [(String, Double, Double, Double)] = [
            ("gpt-6-astra", 10, 1, 50),
            ("gpt-5.6-sol", 4, 0.4, 20),
            ("gpt-5.6-terra", 2, 0.2, 12),
            ("gpt-5.6-luna", 0.2, 0.02, 1.2),
            ("gpt-5.5", 5, 0.5, 30),
            ("gpt-5.4", 2.5, 0.25, 15),
            ("gpt-5.4-mini", 0.75, 0.075, 4.5)
        ]
        XCTAssertEqual(ModelPricingCatalog.publishedRules.map(\.modelID), expectedRates.map { $0.0 })
        XCTAssertEqual(
            ModelPricingCatalog.listedModelIDs,
            expectedRates.map { $0.0 } + ["gpt-5.3-codex-spark"]
        )
        for (modelID, input, cached, output) in expectedRates {
            let rule = try XCTUnwrap(ModelPricingCatalog.rule(for: modelID))
            XCTAssertEqual(rule.inputPerMillionUSD, input, modelID)
            XCTAssertEqual(rule.cachedInputPerMillionUSD, cached, modelID)
            XCTAssertEqual(rule.outputPerMillionUSD, output, modelID)
            XCTAssertFalse(ModelPricingCatalog.usesReferencePricing(for: modelID), modelID)
        }
        XCTAssertEqual(ModelPricingCatalog.rule(for: "gpt-5.6"), sol)
        XCTAssertEqual(ModelPricingCatalog.rule(for: "  GPT-5.6-LUNA\n")?.modelID, "gpt-5.6-luna")
        XCTAssertEqual(ModelPricingCatalog.rule(for: "  GPT-6-ASTRA\n")?.modelID, "gpt-6-astra")
        for modelID in ["gpt-5.3-codex-spark", "Unknown Model", "gpt-reserve", "gpt-5.6-unknown", "gpt-6-unknown"] {
            XCTAssertTrue(ModelPricingCatalog.usesReferencePricing(for: modelID), modelID)
            XCTAssertEqual(ModelPricingCatalog.rule(for: modelID)?.modelID, "gpt-5.5", modelID)
        }
        XCTAssertEqual(ModelCostFormatter.rate(0.075), "$0.075")
        XCTAssertEqual(ModelCostFormatter.rate(0.02), "$0.02")
        XCTAssertEqual(ModelCostFormatter.rate(4.5), "$4.50")
        let autoReview = try XCTUnwrap(ModelPricingCatalog.rule(for: "codex-auto-review"))
        XCTAssertEqual(autoReview.modelID, "gpt-5.5")
        XCTAssertFalse(ModelPricingCatalog.usesReferencePricing(for: "gpt-5.5"))
        XCTAssertFalse(ModelPricingCatalog.usesReferencePricing(for: "gpt-5.6"))
        XCTAssertTrue(ModelPricingCatalog.usesReferencePricing(for: "codex-auto-review"))
        XCTAssertEqual(ModelCostFormatter.usd(0.0005, approximate: true), "≈$0.0005")
        XCTAssertEqual(
            autoReview.estimate(
                uncachedInputTokens: 1_000_000,
                cachedInputTokens: 1_000_000,
                visibleOutputTokens: 1_000_000,
                reasoningTokens: 1_000_000
            ),
            65.5,
            accuracy: 0.000_001
        )
    }

    func testAstraStandardEstimateIsConsistentAcrossRankingReplyTaskAndSubscriptionCycle() throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let store = try makeStore()
        try store.commit(batch(events: [usage(
            "astra-cost",
            at: now.addingTimeInterval(-1),
            total: 10_000_000,
            usage: .init(
                uncachedInput: 1_000_000,
                cachedInput: 2_000_000,
                visibleOutput: 3_000_000,
                reasoning: 4_000_000
            ),
            model: "gpt-6-astra",
            turnID: "turn-astra"
        )], quotas: []))

        let snapshot = try DashboardQueryService(store: store).snapshot(
            now: now,
            calendar: .current,
            firstSubscriptionDate: now.addingTimeInterval(-3_600)
        )
        let ranking = snapshot.modelUsage.ranking(for: .allTime)
        // 1M × $10 + 2M × $1 + (3M + 4M) × $50 = $362.
        // Aggregate input above 272K must not trigger a request-level multiplier.
        XCTAssertEqual(ranking.estimatedCostUSD, 362, accuracy: 0.000_001)
        XCTAssertEqual(ranking.referencePricedModelCount, 0)
        let conversation = try XCTUnwrap(
            snapshot.workspaceUsage.ranking(for: .allTime).entries.first?.conversations.first
        )
        let reply = try XCTUnwrap(conversation.replies.first)
        let breakdown = try XCTUnwrap(reply.estimatedCostBreakdown)
        XCTAssertEqual(breakdown.uncachedInputUSD, 10, accuracy: 0.000_001)
        XCTAssertEqual(breakdown.cachedInputUSD, 2, accuracy: 0.000_001)
        XCTAssertEqual(breakdown.visibleOutputUSD, 150, accuracy: 0.000_001)
        XCTAssertEqual(breakdown.reasoningUSD, 200, accuracy: 0.000_001)
        XCTAssertEqual(breakdown.totalUSD, 362, accuracy: 0.000_001)
        XCTAssertEqual(reply.referencePricedModelCount, 0)
        XCTAssertEqual(try XCTUnwrap(conversation.estimatedCostBreakdown).totalUSD, 362, accuracy: 0.000_001)
        XCTAssertEqual(conversation.referencePricedModelCount, 0)
        let cycle = try XCTUnwrap(snapshot.subscriptionCycleUsage.first)
        XCTAssertEqual(try XCTUnwrap(cycle.estimatedCostUSD), 362, accuracy: 0.000_001)
        XCTAssertEqual(cycle.referencePricedModelCount, 0)
    }

    func testModelRankingUsesMiniPublishedPriceWithoutReferenceMarker() throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let store = try makeStore()
        try store.commit(batch(events: [usage(
            "mini-cached-input",
            at: now.addingTimeInterval(-1),
            total: 1_000_000,
            usage: .init(uncachedInput: 0, cachedInput: 1_000_000, visibleOutput: 0, reasoning: 0),
            model: "gpt-5.4-mini"
        )], quotas: []))

        let ranking = try DashboardQueryService(store: store)
            .snapshot(now: now, calendar: .current).modelUsage.ranking(for: .allTime)
        XCTAssertEqual(ranking.estimatedCostUSD, 0.075, accuracy: 0.000_001)
        XCTAssertEqual(ranking.referencePricedModelCount, 0)
    }

    func testReplyCostEstimateUsesTokenAttributionForEachModel() throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let store = try makeStore()
        try store.commit(batch(events: [
            usage(
                "reply-sol",
                at: now.addingTimeInterval(-3),
                total: 10_000_000,
                usage: TokenUsageDelta(
                    uncachedInput: 1_000_000,
                    cachedInput: 2_000_000,
                    visibleOutput: 3_000_000,
                    reasoning: 4_000_000
                ),
                model: "gpt-5.6-sol",
                turnID: "turn-1"
            ),
            usage(
                "reply-terra",
                at: now.addingTimeInterval(-2),
                total: 4_000_000,
                usage: TokenUsageDelta(
                    uncachedInput: 1_000_000,
                    cachedInput: 1_000_000,
                    visibleOutput: 1_000_000,
                    reasoning: 1_000_000
                ),
                model: "gpt-5.6-terra",
                turnID: "turn-1"
            ),
            usage(
                "reply-unpriced",
                at: now.addingTimeInterval(-1),
                total: 100,
                model: "codex-auto-review",
                turnID: "turn-1"
            )
        ], quotas: []))

        let conversation = try XCTUnwrap(
            DashboardQueryService(store: store)
                .snapshot(now: now, calendar: .current)
                .workspaceUsage
                .ranking(for: .allTime)
                .entries
                .first?
                .conversations
                .first
        )
        let reply = try XCTUnwrap(conversation.replies.first)

        XCTAssertEqual(reply.totalTokens, 14_000_100)
        let cost = try XCTUnwrap(reply.estimatedCostBreakdown)
        XCTAssertEqual(cost.cachedInputUSD, 1, accuracy: 0.000_001)
        XCTAssertEqual(cost.visibleOutputUSD, 72, accuracy: 0.000_001)
        XCTAssertEqual(cost.reasoningUSD, 92, accuracy: 0.000_001)
        XCTAssertEqual(cost.uncachedInputUSD, 6.0005, accuracy: 0.000_001)
        XCTAssertEqual(cost.totalUSD, 171.0005, accuracy: 0.000_001)
        XCTAssertEqual(reply.unpricedModelCount, 0)
        XCTAssertEqual(reply.referencePricedModelCount, 1)

        let taskCost = try XCTUnwrap(conversation.estimatedCostBreakdown)
        XCTAssertEqual(taskCost.cachedInputUSD, 1, accuracy: 0.000_001)
        XCTAssertEqual(taskCost.visibleOutputUSD, 72, accuracy: 0.000_001)
        XCTAssertEqual(taskCost.reasoningUSD, 92, accuracy: 0.000_001)
        XCTAssertEqual(taskCost.uncachedInputUSD, 6.0005, accuracy: 0.000_001)
        XCTAssertEqual(taskCost.totalUSD, 171.0005, accuracy: 0.000_001)
        XCTAssertEqual(conversation.unpricedModelCount, 0)
        XCTAssertEqual(conversation.referencePricedModelCount, 1)
    }

    func testWorkspaceUsageReturnsEveryWorkspaceInSelectedRange() throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let store = try makeStore()
        let events = (0..<25).map { index in
            usage(
                "project-\(index)",
                at: now.addingTimeInterval(-1),
                total: Int64(index + 1),
                project: ProjectIdentity(id: "project-id-\(index)", name: "project-\(index)")
            )
        }
        try store.commit(batch(events: events, quotas: []))

        let snapshot = try DashboardQueryService(store: store).snapshot(
            now: now,
            calendar: .current
        )
        let allTime = snapshot.workspaceUsage.ranking(for: .allTime)

        XCTAssertEqual(allTime.workspaceCount, 25)
        XCTAssertEqual(allTime.projectCount, 25)
        XCTAssertEqual(allTime.entries.count, 25)
        XCTAssertEqual(allTime.entries.first?.tokens, 25)
        XCTAssertEqual(allTime.entries.last?.tokens, 1)
    }

    func testWorkspaceUsageGroupsChildDirectoriesByNameThenGitRepositoryIdentity() throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let observedAt = now.addingTimeInterval(-1)
        let store = try makeStore()
        let workspace = WorkspaceIdentity(id: "workspace-shop", name: "Shop workspace", rootCount: 4)
        try store.commit(batch(events: [
            usage(
                "same-repo-a",
                at: observedAt,
                total: 100,
                project: ProjectIdentity(id: "path-a", name: "Shop", repositoryID: "repo-1"),
                workspace: workspace
            ),
            usage(
                "same-repo-b",
                at: observedAt,
                total: 50,
                project: ProjectIdentity(id: "path-b", name: "Shop", repositoryID: "repo-1"),
                workspace: workspace
            ),
            usage(
                "same-path-changed-remote",
                at: observedAt,
                total: 10,
                project: ProjectIdentity(id: "path-a", name: "Shop", repositoryID: "repo-3"),
                workspace: workspace
            ),
            usage(
                "different-repo",
                at: observedAt,
                total: 30,
                project: ProjectIdentity(id: "path-c", name: "Shop", repositoryID: "repo-2"),
                workspace: workspace
            ),
            usage(
                "different-name",
                at: observedAt,
                total: 20,
                project: ProjectIdentity(id: "path-d", name: "ShopCopy", repositoryID: "repo-1"),
                workspace: workspace
            )
        ], quotas: []))

        let ranking = try DashboardQueryService(store: store).snapshot(now: now, calendar: .current)
            .workspaceUsage.ranking(for: .allTime)

        XCTAssertEqual(ranking.workspaceCount, 1)
        XCTAssertEqual(ranking.projectCount, 3)
        let entry = try XCTUnwrap(ranking.entries.first)
        XCTAssertEqual(entry.name, "Shop workspace")
        XCTAssertEqual(entry.tokens, 210)
        XCTAssertEqual(entry.projects.filter { $0.name == "Shop" }.map(\.tokens), [160, 30])
        XCTAssertEqual(entry.projects.first { $0.tokens == 160 }?.id, "path-a")
        XCTAssertEqual(entry.projects.first { $0.name == "ShopCopy" }?.tokens, 20)
    }

    func testDirectoryListIncludesAllConfiguredRootsRegardlessOfUsage() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let store = try makeStore()
        try store.commit(batch(events: [
            usage("public-usage", at: now.addingTimeInterval(-1), total: 120,
                  project: ProjectIdentity(id: "public-path", name: "public-project"),
                  workspace: WorkspaceIdentity(id: "two-roots", name: "Project", rootCount: 2))
        ], quotas: []))
        try store.upsertWorkspaceConfiguration(
            StoredWorkspaceConfiguration(
                id: "configured-project", name: "Project",
                directories: [
                    WorkspaceDirectory(id: "public-path", name: "public-project"),
                    WorkspaceDirectory(id: "private-path", name: "private-project")
                ], updatedAtMilliseconds: 2000
            ), matchingWorkspaceIDs: ["two-roots"], isCurrent: true
        )

        let snapshot = try DashboardQueryService(store: store).snapshot(now: now, calendar: .current)
        for ranking in [snapshot.workspaceUsage.today, snapshot.workspaceUsage.sevenDays,
                        snapshot.workspaceUsage.thirtyDays, snapshot.workspaceUsage.allTime] {
            let entry = try XCTUnwrap(ranking.entries.first)
            XCTAssertEqual(entry.directories.map(\.name), ["public-project", "private-project"])
            XCTAssertEqual(entry.directories.map(\.id), ["public-path", "private-path"])
            XCTAssertEqual(ranking.projectCount, 2)
            XCTAssertEqual(entry.projects.count, 1)
            XCTAssertEqual(entry.tokens, 120)
        }
    }

    func testConfiguredWorkspacesWithSameNameRemainSeparateAcrossAllRanges() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let store = try makeStore()
        let project = ProjectIdentity(id: "shared-cwd", name: "shared")
        try store.commit(batch(events: [
            usage("old-a", at: now.addingTimeInterval(-3), total: 40, project: project,
                  workspace: WorkspaceIdentity(id: "old-roots-a", name: "Same name", rootCount: 1)),
            usage("new-a", at: now.addingTimeInterval(-2), total: 20, project: project,
                  workspace: WorkspaceIdentity(id: "new-roots-a", name: "Same name", rootCount: 2)),
            usage("b", at: now.addingTimeInterval(-1), total: 30, project: project,
                  workspace: WorkspaceIdentity(id: "roots-b", name: "Same name", rootCount: 1))
        ], quotas: []))
        try store.upsertWorkspaceConfiguration(
            StoredWorkspaceConfiguration(
                id: "configuration-a", name: "Same name",
                directories: [WorkspaceDirectory(id: "a", name: "Latest A")], updatedAtMilliseconds: 2000
            ),
            matchingWorkspaceIDs: ["old-roots-a", "new-roots-a"], isCurrent: true
        )
        try store.upsertWorkspaceConfiguration(
            StoredWorkspaceConfiguration(
                id: "configuration-b", name: "Same name",
                directories: [WorkspaceDirectory(id: "b", name: "Latest B")], updatedAtMilliseconds: 2000
            ),
            matchingWorkspaceIDs: ["roots-b"], isCurrent: true
        )

        let snapshot = try DashboardQueryService(store: store).snapshot(now: now, calendar: .current)

        for ranking in [snapshot.workspaceUsage.today, snapshot.workspaceUsage.sevenDays,
                        snapshot.workspaceUsage.thirtyDays, snapshot.workspaceUsage.allTime] {
            XCTAssertEqual(ranking.workspaceCount, 2)
            XCTAssertEqual(ranking.entries.map(\.id), ["configuration-a", "configuration-b"])
            XCTAssertEqual(ranking.entries.map(\.tokens), [60, 30])
            XCTAssertEqual(ranking.entries.map(\.rootCount), [1, 1])
            XCTAssertEqual(ranking.entries.map { $0.configuredDirectories.map(\.name) }, [["Latest A"], ["Latest B"]])
            XCTAssertEqual(ranking.entries.map { $0.directories.map(\.name) }, [["Latest A"], ["Latest B"]])
            XCTAssertEqual(ranking.projectCount, 2)
        }
        XCTAssertEqual(try store.totalUsage(), 90)
        XCTAssertEqual(try store.usageEventCount(), 3)
    }

    func testExplicitAliasCanTargetLatestConfigurationWithoutNewUsage() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let store = try makeStore()
        try store.commit(batch(events: [
            usage("temporary", at: now.addingTimeInterval(-1), total: 40,
                  workspace: WorkspaceIdentity(id: "temporary", name: "Temporary", rootCount: 1))
        ], quotas: []))
        try store.upsertWorkspaceConfiguration(
            StoredWorkspaceConfiguration(
                id: "configured-project", name: "Target",
                directories: [WorkspaceDirectory(id: "target-directory", name: "Current root")],
                updatedAtMilliseconds: 2000
            ),
            matchingWorkspaceIDs: ["old-target-roots"], isCurrent: true
        )
        try store.setWorkspaceAlias(sourceWorkspaceID: "temporary", targetWorkspaceID: "old-target-roots")

        let entry = try XCTUnwrap(DashboardQueryService(store: store)
            .snapshot(now: now, calendar: .current).workspaceUsage.allTime.entries.first)

        XCTAssertEqual(entry.id, "configured-project")
        XCTAssertEqual(entry.name, "Target")
        XCTAssertEqual(entry.configuredDirectories.map(\.name), ["Current root"])
        XCTAssertEqual(entry.tokens, 40)
    }

    func testSameDirectoryUsageIsSeparatedByWorkspaceIdentity() throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let retailSales = ProjectIdentity(id: "retail-path", name: "retail-sales")
        let retailOnly = WorkspaceIdentity(
            id: "workspace-retail-only", name: "retail-sales", rootCount: 1
        )
        let openAPI = WorkspaceIdentity(
            id: "workspace-open-api",
            name: "guide-performance + retail-sales",
            rootCount: 2
        )
        let store = try makeStore()
        try store.commit(batch(events: [
            usage(
                "retail-only", at: now.addingTimeInterval(-2), total: 10,
                project: retailSales, workspace: retailOnly,
                threadID: "retail-thread", turnID: "retail-turn"
            ),
            usage(
                "open-api", at: now.addingTimeInterval(-1), total: 90,
                project: retailSales, workspace: openAPI,
                threadID: "open-api-thread", turnID: "open-api-turn"
            )
        ], quotas: []))

        let ranking = try DashboardQueryService(store: store).snapshot(now: now, calendar: .current)
            .workspaceUsage.ranking(for: .allTime)

        XCTAssertEqual(ranking.workspaceCount, 2)
        XCTAssertEqual(ranking.projectCount, 2)
        XCTAssertEqual(ranking.totalTokens, 100)
        XCTAssertEqual(ranking.entries.map(\.id), ["workspace-open-api", "workspace-retail-only"])
        XCTAssertEqual(ranking.entries.map(\.tokens), [90, 10])
        XCTAssertTrue(ranking.entries.allSatisfy { $0.projects.map(\.name) == ["retail-sales"] })
        XCTAssertTrue(ranking.entries.allSatisfy { $0.directories.map(\.name) == ["retail-sales"] })
        XCTAssertEqual(ranking.entries.map { $0.conversations.count }, [1, 1])
    }

    func testSameNamedSingletonWorkspaceMergesPathAndRepositoryIdentities() throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let projectPath = "shared-project-path"
        let pathBackedWorkspace = WorkspaceIdentity(
            id: "workspace-path-backed", name: "data-work", rootCount: 1
        )
        let repositoryBackedWorkspace = WorkspaceIdentity(
            id: "workspace-repository-backed", name: "data-work", rootCount: 1
        )
        let store = try makeStore()
        try store.commit(batch(events: [
            usage(
                "path-backed", at: now.addingTimeInterval(-2), total: 40,
                project: ProjectIdentity(id: projectPath, name: "data-work"),
                workspace: pathBackedWorkspace,
                threadID: "path-thread", turnID: "path-turn"
            ),
            usage(
                "repository-backed", at: now.addingTimeInterval(-1), total: 60,
                project: ProjectIdentity(
                    id: projectPath,
                    name: "data-work",
                    repositoryID: "shared-repository"
                ),
                workspace: repositoryBackedWorkspace,
                threadID: "repository-thread", turnID: "repository-turn"
            )
        ], quotas: []))

        let ranking = try DashboardQueryService(store: store).snapshot(now: now, calendar: .current)
            .workspaceUsage.ranking(for: .allTime)

        XCTAssertEqual(ranking.workspaceCount, 1)
        XCTAssertEqual(ranking.projectCount, 1)
        XCTAssertEqual(ranking.totalTokens, 100)
        let entry = try XCTUnwrap(ranking.entries.first)
        XCTAssertEqual(entry.id, repositoryBackedWorkspace.id)
        XCTAssertEqual(entry.name, "data-work")
        XCTAssertEqual(entry.tokens, 100)
        XCTAssertEqual(entry.projects.map(\.tokens), [100])
        XCTAssertEqual(entry.conversations.count, 2)
    }

    func testSameNamedSingletonWorkspacesWithDifferentProjectsRemainSeparate() throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let store = try makeStore()
        try store.commit(batch(events: [
            usage(
                "first-copy", at: now.addingTimeInterval(-2), total: 40,
                project: ProjectIdentity(id: "first-path", name: "website"),
                workspace: WorkspaceIdentity(
                    id: "first-workspace", name: "website", rootCount: 1
                ),
                threadID: "first-thread"
            ),
            usage(
                "second-copy", at: now.addingTimeInterval(-1), total: 60,
                project: ProjectIdentity(id: "second-path", name: "website"),
                workspace: WorkspaceIdentity(
                    id: "second-workspace", name: "website", rootCount: 1
                ),
                threadID: "second-thread"
            )
        ], quotas: []))

        let ranking = try DashboardQueryService(store: store).snapshot(now: now, calendar: .current)
            .workspaceUsage.ranking(for: .allTime)

        XCTAssertEqual(ranking.workspaceCount, 2)
        XCTAssertEqual(ranking.projectCount, 2)
        XCTAssertEqual(ranking.entries.map(\.name), ["website", "website"])
        XCTAssertEqual(ranking.entries.map(\.tokens), [60, 40])
    }

    func testExplicitWorkspaceAliasMergesDifferentNamesIntoChosenTarget() throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let temporaryWorkspace = WorkspaceIdentity(
            id: "temporary-new-chat", name: "new-chat", rootCount: 1
        )
        let targetWorkspace = WorkspaceIdentity(
            id: "expectant-father-workspace", name: "expectant-father", rootCount: 1
        )
        let store = try makeStore()
        try store.setWorkspaceAlias(
            sourceWorkspaceID: temporaryWorkspace.id,
            targetWorkspaceID: targetWorkspace.id
        )
        try store.commit(batch(events: [
            usage(
                "temporary-task", at: now.addingTimeInterval(-2), total: 40,
                project: ProjectIdentity(id: "temporary-path", name: "new-chat"),
                workspace: temporaryWorkspace,
                threadID: "temporary-thread"
            ),
            usage(
                "target-task", at: now.addingTimeInterval(-1), total: 60,
                project: ProjectIdentity(id: "target-path", name: "expectant-father"),
                workspace: targetWorkspace,
                threadID: "target-thread"
            )
        ], quotas: []))

        let ranking = try DashboardQueryService(store: store).snapshot(now: now, calendar: .current)
            .workspaceUsage.ranking(for: .allTime)

        XCTAssertEqual(ranking.workspaceCount, 1)
        XCTAssertEqual(ranking.projectCount, 2)
        XCTAssertEqual(ranking.totalTokens, 100)
        let entry = try XCTUnwrap(ranking.entries.first)
        XCTAssertEqual(entry.id, targetWorkspace.id)
        XCTAssertEqual(entry.name, targetWorkspace.name)
        XCTAssertEqual(entry.tokens, 100)
        XCTAssertEqual(entry.conversations.count, 2)
        XCTAssertEqual(Set(entry.projects.map(\.name)), ["new-chat", "expectant-father"])
    }

    func testInferredWorkspaceRemainsSeparateFromConfirmedSingletonWorkspace() throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let project = ProjectIdentity(id: "expectant-path", name: "expectant-father")
        let inferred = try XCTUnwrap(WorkspaceIdentity.inferFromProject(project))
        let confirmed = WorkspaceIdentity(
            id: "confirmed-expectant", name: "expectant-father", rootCount: 1
        )
        let store = try makeStore()
        try store.commit(batch(events: [
            usage(
                "inferred", at: now.addingTimeInterval(-2), total: 70,
                project: project, workspace: inferred, threadID: "inferred-thread"
            ),
            usage(
                "confirmed", at: now.addingTimeInterval(-1), total: 30,
                project: project, workspace: confirmed, threadID: "confirmed-thread"
            )
        ], quotas: []))

        let ranking = try DashboardQueryService(store: store).snapshot(now: now, calendar: .current)
            .workspaceUsage.ranking(for: .allTime)

        XCTAssertEqual(ranking.workspaceCount, 2)
        XCTAssertEqual(ranking.entries.map(\.name), ["expectant-father", "expectant-father"])
        XCTAssertEqual(ranking.entries.map(\.isInferred), [true, false])
        XCTAssertNotEqual(ranking.entries[0].id, ranking.entries[1].id)
    }

    func testBuildsActivityRankingsForTodaySevenThirtyAndAllTimeLocalDayBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 14, hour: 12
        )))
        let todayStart = calendar.startOfDay(for: now)
        let sevenDayStart = try XCTUnwrap(calendar.date(byAdding: .day, value: -6, to: todayStart))
        let thirtyDayStart = try XCTUnwrap(calendar.date(byAdding: .day, value: -29, to: todayStart))
        let store = try makeStore()
        var activityEvents = [
            activity("skill-today", kind: .skill, name: "swiftui-patterns", at: todayStart.addingTimeInterval(60)),
            activity("skill-seven-edge", kind: .skill, name: "swiftui-patterns", at: sevenDayStart),
            activity("skill-before-seven", kind: .skill, name: "imagegen", at: sevenDayStart.addingTimeInterval(-1)),
            activity("skill-thirty-edge", kind: .skill, name: "imagegen", at: thirtyDayStart),
            activity("skill-before-thirty", kind: .skill, name: "legacy-skill", at: thirtyDayStart.addingTimeInterval(-1)),
            activity("tool-a-1", kind: .tool, name: "alpha", at: todayStart.addingTimeInterval(1)),
            activity("tool-a-2", kind: .tool, name: "alpha", at: todayStart.addingTimeInterval(2)),
            activity("tool-b", kind: .tool, name: "beta", at: todayStart.addingTimeInterval(3)),
            activity("tool-c", kind: .tool, name: "charlie", at: todayStart.addingTimeInterval(4)),
            activity("tool-d", kind: .tool, name: "delta", at: todayStart.addingTimeInterval(5)),
            activity("tool-e", kind: .tool, name: "echo", at: todayStart.addingTimeInterval(6)),
            activity("tool-f", kind: .tool, name: "foxtrot", at: todayStart.addingTimeInterval(7)),
            activity("tool-g", kind: .tool, name: "golf", at: todayStart.addingTimeInterval(8)),
            activity("tool-future", kind: .tool, name: "future", at: calendar.date(byAdding: .day, value: 1, to: todayStart)!)
        ]
        activityEvents += (0..<14).map { index in
            activity(
                "tool-extra-\(index)",
                kind: .tool,
                name: String(format: "tool-%02d", index),
                at: todayStart.addingTimeInterval(TimeInterval(20 + index))
            )
        }
        try store.commit(batch(events: [], quotas: [], activityEvents: activityEvents))

        let snapshot = try DashboardQueryService(store: store).snapshot(now: now, calendar: calendar)
        let today = snapshot.activityRankings.ranking(for: .today)
        let sevenDays = snapshot.activityRankings.ranking(for: .sevenDays)
        let thirtyDays = snapshot.activityRankings.ranking(for: .thirtyDays)
        let allTime = snapshot.activityRankings.ranking(for: .allTime)

        XCTAssertEqual(today.skills.map(\.name), ["swiftui-patterns"])
        XCTAssertEqual(today.skills.map(\.count), [1])
        XCTAssertEqual(today.tools.count, 20)
        XCTAssertFalse(today.tools.contains { $0.name == "future" })
        XCTAssertEqual(sevenDays.skills.map(\.name), ["swiftui-patterns"])
        XCTAssertEqual(sevenDays.skills.map(\.count), [2])
        XCTAssertEqual(thirtyDays.skills.map(\.name), ["imagegen", "swiftui-patterns"],
                       "Ties use ascending normalized names")
        XCTAssertEqual(thirtyDays.skills.map(\.count), [2, 2])
        XCTAssertEqual(allTime.skills.map(\.name), ["imagegen", "swiftui-patterns", "legacy-skill"])
        XCTAssertEqual(allTime.skills.map(\.count), [2, 2, 1])
        XCTAssertEqual(sevenDays.tools.count, 20, "Skills and Tools rankings are capped at Top 20")
        XCTAssertEqual(sevenDays.tools.first?.name, "alpha")
        XCTAssertEqual(sevenDays.tools.first?.count, 2)
        XCTAssertTrue(sevenDays.tools.contains { $0.name == "golf" })
        XCTAssertFalse(sevenDays.tools.contains { $0.name == "tool-13" },
                       "The stable alphabetical tie break determines the twentieth item")
        XCTAssertFalse(sevenDays.tools.contains { $0.name == "future" })
    }

    func testSkillRankingGroupsNamespacesBeforeApplyingTopTwenty() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 7, hour: 12
        )))
        var events = (0..<25).map { index in
            let detailName: String
            switch index {
            case 0: detailName = "appkit-interop"
            case 1: detailName = "build-run-debug"
            case 2: detailName = "swiftui-patterns"
            default: detailName = String(format: "detail-%02d", index)
            }
            return activity(
                "grouped-skill-\(index)",
                kind: .skill,
                name: "build-macos-apps:\(detailName)",
                at: now.addingTimeInterval(-1)
            )
        }
        events += (0..<19).flatMap { index in
            (0..<2).map { invocation in
                activity(
                    "standalone-\(index)-\(invocation)",
                    kind: .skill,
                    name: String(format: "standalone-%02d", index),
                    at: now.addingTimeInterval(-1)
                )
            }
        }
        events.append(activity(
            "namespaced-tool",
            kind: .tool,
            name: "server:call",
            at: now.addingTimeInterval(-1)
        ))
        let store = try makeStore()
        try store.commit(batch(events: [], quotas: [], activityEvents: events))

        let ranking = try DashboardQueryService(store: store)
            .snapshot(now: now, calendar: calendar)
            .activityRankings
            .ranking(for: .today)

        XCTAssertEqual(ranking.skills.count, 20)
        XCTAssertEqual(ranking.skills.first?.name, "build-macos-apps")
        XCTAssertEqual(ranking.skills.first?.count, 25)
        XCTAssertEqual(ranking.skills.first?.details.count, 25,
                       "Every sub-skill must contribute before the grouped Top 20 is selected")
        XCTAssertEqual(ranking.skills.first?.details.map(\.count), Array(repeating: 1, count: 25))
        XCTAssertTrue(ranking.skills.first?.details.contains {
            $0.name == "swiftui-patterns"
        } == true)
        XCTAssertEqual(ranking.tools.first?.name, "server:call",
                       "Tools remain ungrouped even when their names contain a namespace")
        XCTAssertTrue(ranking.tools.first?.details.isEmpty == true)
    }

    func testDisplaysProLiteAsPro5xAndProAsPro20x() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let store = try makeStore()
        try store.commit(batch(
            events: [
                usage("pro-5x", at: now.addingTimeInterval(-1), total: 1, planRaw: "prolite"),
                usage("pro-20x", at: now, total: 1, planRaw: "pro")
            ],
            quotas: []
        ))

        let snapshot = try DashboardQueryService(store: store).snapshot(
            now: now,
            calendar: .current
        )

        XCTAssertEqual(snapshot.planName, "Pro 20x")
    }

    func testLegacyProStorageKindUsesRawPlanToRecoverPro20x() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let store = try makeStore()
        let legacyEvent = StoredUsageEvent(
            fingerprint: "legacy-pro-20x",
            observedAtMilliseconds: 10_000_000,
            threadID: "thread-1",
            sourceKind: .desktop,
            model: "test-model",
            plan: PlanResolution(kind: .proLite, rawValue: "pro", isInferred: false),
            usage: .init(uncachedInput: 1, cachedInput: 0, visibleOutput: 0, reasoning: 0),
            sourceFileID: "file-1",
            sourceOffset: 1
        )
        try store.commit(batch(events: [legacyEvent], quotas: []))

        let snapshot = try DashboardQueryService(store: store).snapshot(
            now: now,
            calendar: .current
        )

        XCTAssertEqual(snapshot.planName, "Pro 20x")
    }

    func testAggregateOverflowThrowsInsteadOfWrapping() throws {
        let store = try makeStore()
        try store.commit(batch(
            events: [
                usage("max", at: Date(timeIntervalSince1970: 0), total: Int64.max),
                usage("one", at: Date(timeIntervalSince1970: 3_600), total: 1)
            ],
            quotas: []
        ))

        XCTAssertThrowsError(try DashboardQueryService(store: store).snapshot(
            now: Date(timeIntervalSince1970: 7_200), calendar: .current
        )) { error in
            guard case DashboardQueryError.tokenOverflow = error else {
                return XCTFail("Expected controlled token overflow, got \(error)")
            }
        }
    }

    func testLocalDayBoundariesFollowSpringAndFallDSTTransitions() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let cases = [
            (DateComponents(year: 2026, month: 3, day: 8, hour: 12), 23.0),
            (DateComponents(year: 2026, month: 11, day: 1, hour: 12), 25.0)
        ]

        for (components, expectedDayHours) in cases {
            let now = try XCTUnwrap(calendar.date(from: components))
            let start = calendar.startOfDay(for: now)
            let nextStart = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start))
            XCTAssertEqual(nextStart.timeIntervalSince(start) / 3_600, expectedDayHours)
            let store = try makeStore()
            try store.commit(batch(
                events: [
                    usage("inside", at: start, total: 1),
                    usage("outside", at: start.addingTimeInterval(-0.001), total: 9)
                ],
                quotas: []
            ))

            let snapshot = try DashboardQueryService(store: store).snapshot(
                now: now, calendar: calendar
            )

            XCTAssertEqual(snapshot.todayTokens, 1)
        }
    }

    func testEmptyAndMalformedSnapshotsUseStableIDLookupWithoutCrashing() {
        let empty = DashboardSnapshot.empty(updatedText: "未刷新")
        XCTAssertEqual(empty.periods.map(\.id), ["today", "sevenDays", "thirtyDays", "allTime"])
        XCTAssertEqual(empty.todayTokens, 0)
        XCTAssertEqual(empty.breakdown.total, 0)

        let malformed = DashboardSnapshot(
            planName: "Free",
            updatedText: "未刷新",
            periods: [PeriodUsage(
                id: "allTime", title: "累计", total: 7,
                uncachedInput: 7, cachedInput: 0, output: 0, reasoning: 0
            )],
            quotas: [],
            models: [],
            dailyUsage: []
        )
        XCTAssertEqual(malformed.todayTokens, 0)
        XCTAssertEqual(malformed.sevenDayTokens, 0)
        XCTAssertEqual(malformed.thirtyDayTokens, 0)
        XCTAssertEqual(malformed.totalTokens, 7)
        XCTAssertEqual(malformed.breakdown.total, 0)
    }

    private func makeStore() throws -> UsageStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DashboardQueryServiceTests-\(UUID().uuidString).sqlite3")
        return try UsageStore(databaseURL: url)
    }

    private func usage(
        _ fingerprint: String,
        at date: Date,
        total: Int64,
        usage: TokenUsageDelta? = nil,
        model: String = "test-model",
        planRaw: String = "plus",
        project: ProjectIdentity = .unknown,
        workspace: WorkspaceIdentity? = nil,
        threadID: String = "thread-1",
        turnID: String? = nil
    ) -> StoredUsageEvent {
        StoredUsageEvent(
            fingerprint: fingerprint,
            observedAtMilliseconds: Int64((date.timeIntervalSince1970 * 1_000).rounded()),
            threadID: threadID,
            turnID: turnID,
            sourceKind: .cli,
            model: model,
            plan: PlanResolver.resolve(rawValue: planRaw),
            usage: usage ?? .init(uncachedInput: total, cachedInput: 0, visibleOutput: 0, reasoning: 0),
            sourceFileID: "file-1",
            sourceOffset: 1,
            project: project,
            workspace: workspace ?? WorkspaceIdentity(
                id: "workspace-\(project.id)",
                name: project.name,
                rootCount: project == .unknown ? 0 : 1
            )
        )
    }

    private func session(
        threadID: String,
        createdAtMilliseconds: Int64? = nil,
        updatedAtMilliseconds: Int64,
        activity: SessionActivityState = .completed,
        activeTurnID: String? = nil
    ) -> StoredSession {
        StoredSession(
            threadID: threadID,
            sourceKind: .cli,
            createdAtMilliseconds: createdAtMilliseconds ?? updatedAtMilliseconds - 1_000,
            updatedAtMilliseconds: updatedAtMilliseconds,
            state: SessionStateSnapshot(
                threadID: threadID,
                activity: activity,
                archive: .active,
                childEdgeStatus: nil,
                activeTurnID: activeTurnID,
                lastActivityAtMilliseconds: updatedAtMilliseconds,
                lastActivityEventKey: "\(threadID):1",
                archiveObservedAtMilliseconds: nil
            ),
            lastModel: "test-model",
            lastPlan: .plus,
            sourceFileID: "file-1"
        )
    }

    private func quota(
        _ fingerprint: String,
        kind: QuotaKind,
        now: Date,
        reset: Date?
    ) -> StoredQuotaEvent {
        StoredQuotaEvent(
            fingerprint: fingerprint,
            threadID: "thread-1",
            observation: QuotaObservation(
                kind: kind,
                observedAtMilliseconds: Int64((now.timeIntervalSince1970 * 1_000).rounded()),
                windowMinutes: kind == .fiveHour ? 300 : 10_080,
                remaining: 0.75,
                resetsAtMilliseconds: reset.map { Int64(($0.timeIntervalSince1970 * 1_000).rounded()) },
                plan: PlanResolver.resolve(rawValue: "plus")
            ),
            sourceKind: .cli
        )
    }

    private func activity(
        _ fingerprint: String,
        kind: ActivityKind,
        name: String,
        at date: Date,
        threadID: String = "thread-1",
        turnID: String? = "turn-1"
    ) -> StoredActivityEvent {
        StoredActivityEvent(
            fingerprint: fingerprint,
            observedAtMilliseconds: Int64((date.timeIntervalSince1970 * 1_000).rounded()),
            threadID: threadID,
            turnID: turnID,
            kind: kind,
            name: name,
            sourceKind: .cli,
            sourceFileID: "file-1",
            sourceOffset: 1
        )
    }

    private func lifecycle(
        _ fingerprint: String,
        threadID: String,
        turnID: String,
        kind: SessionLifecycleKind,
        at date: Date
    ) -> StoredSessionStateEvent {
        StoredSessionStateEvent(
            fingerprint: fingerprint,
            threadID: threadID,
            turnID: turnID,
            observedAtMilliseconds: Int64((date.timeIntervalSince1970 * 1_000).rounded()),
            kind: kind,
            sourceFileID: "file-1",
            sourceOffset: 1
        )
    }

    private func batch(
        events: [StoredUsageEvent],
        quotas: [StoredQuotaEvent],
        stateEvents: [StoredSessionStateEvent] = [],
        activityEvents: [StoredActivityEvent] = [],
        sessions: [StoredSession] = []
    ) -> ImportBatch {
        ImportBatch(
            file: FileCheckpoint(
                fileID: "file-1", deviceID: 1, inode: 1,
                path: "/synthetic/dashboard.jsonl", fileSize: 10, committedOffset: 10,
                generation: 0, threadID: "thread-1", lastRecordAtMilliseconds: nil,
                lastSuccessAtMilliseconds: nil, formatStatus: "supported", lastError: nil
            ),
            usageEvents: events,
            quotaEvents: quotas,
            stateEvents: stateEvents,
            activityEvents: activityEvents,
            sessions: sessions,
            threadCheckpoints: []
        )
    }
}
