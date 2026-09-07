import AppKit
import Foundation
import XCTest
@testable import CodexVista

private extension DashboardSnapshot {
    static let preview: DashboardSnapshot = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let startDate = calendar.date(
            from: DateComponents(year: 2026, month: 5, day: 28)
        ) ?? Date(timeIntervalSince1970: 0)
        let dailyUsage = (0..<45).compactMap { index -> DailyUsage? in
            guard let date = calendar.date(byAdding: .day, value: index, to: startDate) else {
                return nil
            }
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = components.year,
                  let month = components.month,
                  let day = components.day else {
                return nil
            }
            let total = 8_400_000 + (index % 10) * 650_000 + (index / 10) * 300_000
            let uncachedInput = total * 38 / 100
            let cachedInput = total * 52 / 100
            let output = total * 7 / 100
            let reasoning = total - uncachedInput - cachedInput - output
            return DailyUsage(
                id: String(format: "%04d-%02d-%02d", year, month, day),
                day: String(format: "%d/%d", month, day),
                total: total,
                uncachedInput: uncachedInput,
                cachedInput: cachedInput,
                output: output,
                reasoning: reasoning
            )
        }
        return DashboardSnapshot(
            planName: "Pro",
            updatedText: "刚刚刷新",
            periods: [
                PeriodUsage(
                    id: "today", title: "今日", total: 17_000_000,
                    uncachedInput: 8_200_000, cachedInput: 7_900_000,
                    output: 900_000, reasoning: 200_000
                ),
                PeriodUsage(
                    id: "sevenDays", title: "7 日", total: 84_200_000,
                    uncachedInput: 35_200_000, cachedInput: 45_500_000,
                    output: 3_500_000, reasoning: 900_000
                ),
                PeriodUsage(
                    id: "thirtyDays", title: "30 日", total: 198_600_000,
                    uncachedInput: 78_400_000, cachedInput: 112_100_000,
                    output: 8_100_000, reasoning: 1_900_000
                ),
                PeriodUsage(
                    id: "allTime", title: "累计", total: 326_800_000,
                    uncachedInput: 128_000_000, cachedInput: 184_000_000,
                    output: 14_800_000, reasoning: 3_400_000
                )
            ],
            quotas: [
                QuotaSnapshot(
                    id: "5h", title: "5 小时", remaining: 0.85, resetText: "02:52"
                ),
                QuotaSnapshot(
                    id: "7d", title: "7 天", remaining: 0.84,
                    resetText: "07-13"
                )
            ],
            models: [
                ModelUsage(id: "gpt-5.5", name: "gpt-5.5", share: 0.68),
                ModelUsage(id: "gpt-5.4", name: "gpt-5.4", share: 0.32)
            ],
            dailyUsage: dailyUsage
        )
    }()
}

final class TokenFormatterTests: XCTestCase {
    func testTokenCompositionDistinguishesMissingDataFromZeroUsage() {
        let missing = TokenCompositionSegment.make(breakdown: nil)
        let empty = TokenCompositionSegment.make(
            breakdown: TokenBreakdown(input: 0, cachedInput: 0, output: 0, reasoning: 0)
        )
        XCTAssertTrue(missing.allSatisfy { $0.value == nil && $0.valueText == "—" && $0.shareText == "—" })
        XCTAssertTrue(empty.allSatisfy { $0.value == 0 && $0.share == 0 && $0.valueText != "—" })
    }

    func testTokenCompositionPreservesSmallSharesAndCallerTotal() {
        let segments = TokenCompositionSegment.make(
            breakdown: TokenBreakdown(input: 1, cachedInput: 999, output: 0, reasoning: 0),
            total: 2_000
        )
        XCTAssertEqual(segments[0].share, 0.0005, accuracy: 0.000001)
        XCTAssertEqual(segments[1].share, 0.4995, accuracy: 0.000001)
        XCTAssertEqual(segments.map(\.share).reduce(0, +), 0.5, accuracy: 0.000001)
        XCTAssertEqual(segments[2].share, 0)
        XCTAssertEqual(segments[3].share, 0)
    }

    func testTokenCategoryColorsStayDistinctAcrossSkinsAndAppearances() {
        // CIE Lab catches colors with different RGB values but similar visual appearance.
        func lab(_ hex: UInt32) -> [Double] {
            let rgb = [16, 8, 0].map { shift -> Double in
                let value = Double((hex >> shift) & 255) / 255
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            let r = rgb[0], g = rgb[1], b = rgb[2]
            let xyz = [(0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047,
                       0.2126729 * r + 0.7151522 * g + 0.0721750 * b,
                       (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883]
            let f = xyz.map { $0 > 0.008856 ? pow($0, 1.0 / 3.0) : 7.787 * $0 + 16.0 / 116.0 }
            return [116 * f[1] - 16, 500 * (f[0] - f[1]), 200 * (f[1] - f[2])]
        }
        for skin in AppSkinPreference.allCases {
            for dark in [false, true] {
                let palette = CodexVistaPalette.resolve(skin: skin, dark: dark)
                let colors = [palette.accent, palette.cached, palette.output, palette.reasoning].map(lab)
                for i in colors.indices {
                    for j in colors.indices where j > i {
                        let delta = sqrt(zip(colors[i], colors[j]).reduce(0) { $0 + pow($1.0 - $1.1, 2) })
                        XCTAssertGreaterThanOrEqual(delta, 35, "\(skin.rawValue), dark=\(dark), categories=\(i)/\(j)")
                    }
                }
            }
        }
    }

    func testSkinPalettesKeepSmallTextReadableInBothAppearances() {
        func luminance(_ hex: UInt32) -> Double {
            let channels = [16, 8, 0].map { shift -> Double in
                let value = Double((hex >> shift) & 255) / 255
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
        }
        func blend(_ foreground: UInt32, over background: UInt32, opacity: Double) -> UInt32 {
            [16, 8, 0].reduce(UInt32(0)) { result, shift in
                let front = Double((foreground >> shift) & 255)
                let back = Double((background >> shift) & 255)
                return result | (UInt32((front * opacity + back * (1 - opacity)).rounded()) << shift)
            }
        }
        for skin in AppSkinPreference.allCases {
            for dark in [false, true] {
                let palette = CodexVistaPalette.resolve(skin: skin, dark: dark)
                var textPairs: [(UInt32, UInt32)] = [
                    (palette.primary, palette.raised),
                    (palette.muted, palette.control),
                    (palette.muted, palette.surface),
                    (palette.selectedText, palette.selected),
                    (palette.heatText, palette.accent),
                    (0xFFFFFF, palette.action)
                ]
                // Token colors are also used for small labels in popovers and legends.
                for color in [palette.accent, palette.secondary, palette.cached, palette.output, palette.reasoning] {
                    textPairs.append((color, palette.surface))
                    textPairs.append((color, palette.raised))
                }
                for level in 1...3 {
                    textPairs.append((palette.primary, blend(
                        palette.accent, over: palette.surface, opacity: skin.calendarOpacity(for: level)
                    )))
                }
                for (foreground, background) in textPairs {
                    let values = [luminance(foreground), luminance(background)].sorted()
                    XCTAssertGreaterThanOrEqual(
                        (values[1] + 0.05) / (values[0] + 0.05), 4.5,
                        "\(skin.rawValue), dark=\(dark), foreground=\(foreground), background=\(background)"
                    )
                }
            }
        }
    }

    func testWorktimeFormattingKeepsShortNonzeroDurationsVisible() {
        XCTAssertEqual(TokenFormatter.compactWorktime(0), "0m")
        XCTAssertEqual(TokenFormatter.compactWorktime(30_000), "<1m")
        XCTAssertEqual(TokenFormatter.compactWorktime(59 * 60_000), "59m")
        XCTAssertEqual(TokenFormatter.compactWorktime(60 * 60_000), "1h")
        XCTAssertEqual(TokenFormatter.compactWorktime(5_400_000), "1h 30m")
        XCTAssertEqual(TokenFormatter.compactWorktime(24 * 3_600_000), "1d")
        XCTAssertEqual(TokenFormatter.compactWorktime(26 * 3_600_000), "1d 2h")
        XCTAssertEqual(TokenFormatter.worktime(30_000), "少于 1 分钟")
        XCTAssertEqual(TokenFormatter.worktime(5_400_000), "1 小时 30 分钟")
        XCTAssertEqual(
            TokenFormatter.worktime(26 * 3_600_000 + 30 * 60_000),
            "1 天 2 小时 30 分钟"
        )
    }

    func testDashboardDefaultsToTodayTasksTab() {
        XCTAssertEqual(DashboardAnalyticsTab.defaultTab, .todayTasks)
        XCTAssertEqual(
            DashboardAnalyticsTab.allCases.map(\.rawValue),
            ["今日任务", "用量趋势", "Skills / Tools", "项目用量"]
        )
    }

    func testReplyModelTextPreservesCallCountsAndFallsBackWhenUnknown() {
        XCTAssertEqual(
            ProjectReplyPresentation.modelText("child-model ×1 · parent-model ×2"),
            "child-model ×1 · parent-model ×2"
        )
        XCTAssertEqual(ProjectReplyPresentation.modelText(""), "模型未知")
    }

    func testPeriodSelectionKeepsDashboardMinimumSizeStable() {
        XCTAssertEqual(
            DashboardWindowLayout.expandedContentSize(hasSubscriptionCycle: false),
            CGSize(width: 920, height: 690)
        )
        XCTAssertEqual(
            DashboardWindowLayout.expandedContentSize(hasSubscriptionCycle: true),
            CGSize(width: 920, height: 690)
        )
    }

    func testDashboardWindowLayoutPreservesUserExpandedHeight() {
        XCTAssertEqual(
            DashboardWindowLayout.targetExpandedContentSize(
                current: CGSize(width: 1_040, height: 760),
                requested: CGSize(width: 920, height: 680)
            ),
            CGSize(width: 1_040, height: 760)
        )
    }

    func testDashboardWindowLayoutDoesNotShrinkWhenSkinRebuildsContent() {
        XCTAssertEqual(
            DashboardWindowLayout.targetExpandedContentSize(
                current: CGSize(width: 1_040, height: 780),
                requested: CGSize(width: 920, height: 680)
            ),
            CGSize(width: 1_040, height: 780)
        )
        XCTAssertEqual(
            DashboardWindowLayout.targetExpandedContentSize(
                current: CGSize(width: 920, height: 728), requested: CGSize(width: 920, height: 680)
            ).height, 728
        )
    }

    func testDashboardWindowSizingReservesToolbarOutsideUsableContent() {
        XCTAssertEqual(
            DashboardWindowLayout.windowContentSize(
                for: CGSize(width: 920, height: 680),
                contentSize: CGSize(width: 920, height: 680),
                layoutSize: CGSize(width: 920, height: 628)
            ), CGSize(width: 920, height: 732)
        )
        XCTAssertEqual(
            DashboardWindowLayout.windowContentSize(
                for: CGSize(width: 920, height: 680),
                contentSize: CGSize(width: 920, height: 680),
                layoutSize: CGSize(width: 920, height: 680)
            ), CGSize(width: 920, height: 680)
        )
    }

    @MainActor
    func testDashboardSizingRechecksToolbarChangesAndPreservesExpandedWindow() async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 680),
                              styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.titlebarAppearsTransparent = true
        XCTAssertLessThan(window.contentLayoutRect.height, 680)
        let bridge = DashboardWindowSizingView()
        bridge.setLayout(expandedContentSize: CGSize(width: 920, height: 680))
        window.contentView = bridge
        await settleWindowLayout()
        XCTAssertEqual(window.contentLayoutRect.height, 680, accuracy: 0.5)

        // Reproduce the toolbar being attached after the content first mounts.
        window.toolbar = NSToolbar(identifier: "DashboardSizingRegression")
        window.toolbarStyle = .unified
        await settleWindowLayout()
        XCTAssertEqual(window.contentLayoutRect.height, 680, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(window.contentMinSize.height, 680)

        var largerFrame = window.frame
        largerFrame.size.height += 90
        window.setFrame(largerFrame, display: false)
        let expandedHeight = window.frame.height
        window.contentView = DashboardWindowSizingView()
        await settleWindowLayout()
        XCTAssertEqual(window.frame.height, expandedHeight, accuracy: 0.5)
    }

    @MainActor
    private func settleWindowLayout() async {
        // Allow the deferred sizing pass and contentLayoutRect observation to settle.
        for _ in 0..<5 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    func testDashboardCloseBehaviorResolvesStoredPreferenceAndUsesSafeFallback() {
        XCTAssertEqual(
            DashboardCloseBehavior.resolved(
                from: DashboardCloseBehavior.quitApplication.rawValue
            ),
            .quitApplication
        )
        XCTAssertTrue(DashboardCloseBehavior.quitApplication.terminatesApplication)
        XCTAssertFalse(DashboardCloseBehavior.closeDashboard.terminatesApplication)
        XCTAssertEqual(
            DashboardCloseBehavior.resolved(from: "unsupported-value"),
            .closeDashboard
        )

        let suiteName = "DashboardCloseBehaviorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(DashboardCloseBehavior.load(from: defaults), .closeDashboard)
        defaults.set(
            DashboardCloseBehavior.quitApplication.rawValue,
            forKey: AppPreferenceKeys.dashboardCloseBehavior
        )
        XCTAssertEqual(DashboardCloseBehavior.load(from: defaults), .quitApplication)
        defaults.set(
            DashboardCloseBehavior.closeDashboard.rawValue,
            forKey: AppPreferenceKeys.dashboardCloseBehavior
        )
        XCTAssertEqual(DashboardCloseBehavior.load(from: defaults), .closeDashboard)
    }

    func testColorSchemePreferenceResolvesStoredValueAndUsesSystemFallback() {
        XCTAssertEqual(AppColorSchemePreference.resolved(from: "unsupported-value"), .system)
        XCTAssertNil(AppColorSchemePreference.system.colorScheme)
        XCTAssertEqual(AppColorSchemePreference.light.colorScheme, .light)
        XCTAssertEqual(AppColorSchemePreference.dark.colorScheme, .dark)

        let suiteName = "ColorSchemePreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(AppColorSchemePreference.load(from: defaults), .system)
        defaults.set(
            AppColorSchemePreference.dark.rawValue,
            forKey: AppPreferenceKeys.colorScheme
        )
        XCTAssertEqual(AppColorSchemePreference.load(from: defaults), .dark)
    }

    func testSkinPreferencePersistsIndependentlyOfColorSchemeAndFallsBackSafely() {
        let suiteName = "SkinPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(AppSkinPreference.load(from: defaults), .standard)
        defaults.set(AppColorSchemePreference.dark.rawValue, forKey: AppPreferenceKeys.colorScheme)
        defaults.set(AppSkinPreference.ink.rawValue, forKey: AppPreferenceKeys.skin)
        XCTAssertEqual(AppSkinPreference.load(from: defaults), .ink)
        XCTAssertEqual(AppColorSchemePreference.load(from: defaults), .dark)

        defaults.set("unknown-skin", forKey: AppPreferenceKeys.skin)
        XCTAssertEqual(AppSkinPreference.load(from: defaults), .standard)
        XCTAssertEqual(AppColorSchemePreference.load(from: defaults), .dark)
    }

    func testInkForcesLightWithoutReplacingTheClassicColorSchemePreference() {
        let suiteName = "InkAppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for preference in AppColorSchemePreference.allCases {
            defaults.set(preference.rawValue, forKey: AppPreferenceKeys.colorScheme)
            defaults.set(AppSkinPreference.ink.rawValue, forKey: AppPreferenceKeys.skin)
            let stored = AppColorSchemePreference.load(from: defaults)
            XCTAssertEqual(AppSkinPreference.load(from: defaults).effectiveColorScheme(for: stored), .light)
            XCTAssertEqual(stored, preference)

            defaults.set(AppSkinPreference.standard.rawValue, forKey: AppPreferenceKeys.skin)
            XCTAssertEqual(
                AppSkinPreference.load(from: defaults).effectiveColorScheme(for: stored),
                preference.colorScheme
            )
        }
        let inkOnDarkSystem = CodexVistaPalette.resolve(skin: .ink, dark: true)
        let inkOnLightSystem = CodexVistaPalette.resolve(skin: .ink, dark: false)
        XCTAssertEqual(inkOnDarkSystem.background, inkOnLightSystem.background)
        XCTAssertEqual(inkOnDarkSystem.primary, inkOnLightSystem.primary)
    }

    func testAdditionalSkinsPersistAndRespectSupportedAppearances() {
        let suiteName = "AdditionalSkinsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        for skin in [AppSkinPreference.celadon, .dusk] {
            defaults.set(skin.rawValue, forKey: AppPreferenceKeys.skin)
            XCTAssertEqual(AppSkinPreference.load(from: defaults), skin)
            for scheme in AppColorSchemePreference.allCases {
                XCTAssertEqual(skin.effectiveColorScheme(for: scheme), scheme.colorScheme)
            }
        }
        defaults.set("midnight", forKey: AppPreferenceKeys.skin)
        XCTAssertEqual(AppSkinPreference.load(from: defaults), .standard)
        XCTAssertEqual(AppSkinPreference.load(from: defaults).effectiveColorScheme(for: .dark), .dark)
    }

    func testFantasyAndTechSkinsUseTheirFixedAppearancesAndPersist() {
        let suiteName = "FixedSkinTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        for skin in [AppSkinPreference.cyber, .xianxia] {
            defaults.set(skin.rawValue, forKey: AppPreferenceKeys.skin)
            XCTAssertEqual(AppSkinPreference.load(from: defaults), skin)
            for preference in AppColorSchemePreference.allCases {
                defaults.set(preference.rawValue, forKey: AppPreferenceKeys.colorScheme)
                XCTAssertEqual(skin.effectiveColorScheme(for: preference), skin == .cyber ? .dark : .light)
                XCTAssertEqual(AppColorSchemePreference.load(from: defaults), preference)
            }
            XCTAssertEqual(CodexVistaPalette.resolve(skin: skin, dark: false).background,
                           CodexVistaPalette.resolve(skin: skin, dark: true).background)
        }
        XCTAssertFalse(AppSkinPreference.allCases.map(\.rawValue).contains("midnight"))
    }

    func testUsageCalendarBuildsMondayFirstSixWeekGrid() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 16, hour: 12
        )))
        let usage = DailyUsage(id: "2026-07-15", day: "7/15", total: 100)
        let model = UsageCalendarModel(usage: [usage], calendar: calendar, today: today)

        let cells = model.cells(for: today)

        XCTAssertEqual(cells.count, 42)
        XCTAssertEqual(cells.first?.id, "2026-06-29")
        XCTAssertEqual(cells.last?.id, "2026-08-09")
        XCTAssertEqual(cells.filter(\.isInDisplayedMonth).count, 31)
        XCTAssertEqual(cells.first { $0.id == "2026-07-16" }?.isToday, true)
        XCTAssertEqual(cells.first { $0.id == "2026-07-17" }?.isFuture, true)
    }

    func testUsageCalendarNavigationUsesNonzeroHistoryAndCurrentMonthBounds() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 16, hour: 12
        )))
        let model = UsageCalendarModel(
            usage: [
                DailyUsage(id: "2026-05-30", day: "5/30", total: 0),
                DailyUsage(id: "2026-06-02", day: "6/2", total: 10)
            ],
            calendar: calendar,
            today: today
        )

        XCTAssertTrue(model.canMoveMonth(model.latestMonth, by: -1))
        XCTAssertFalse(model.canMoveMonth(model.earliestMonth, by: -1))
        XCTAssertFalse(model.canMoveMonth(model.latestMonth, by: 1))
        XCTAssertEqual(
            calendar.dateComponents([.year, .month], from: model.earliestMonth),
            DateComponents(year: 2026, month: 6)
        )
    }

    func testUsageCalendarIntensityUsesBalancedSquareRootScale() {
        XCTAssertEqual(UsageCalendarModel.intensity(total: 0, maximum: 1_000_000), 0)
        XCTAssertEqual(UsageCalendarModel.intensity(total: 10, maximum: 1_000_000), 1)
        XCTAssertEqual(UsageCalendarModel.intensity(total: 62_499, maximum: 1_000_000), 1)
        XCTAssertEqual(UsageCalendarModel.intensity(total: 62_500, maximum: 1_000_000), 2)
        XCTAssertEqual(UsageCalendarModel.intensity(total: 249_999, maximum: 1_000_000), 2)
        XCTAssertEqual(UsageCalendarModel.intensity(total: 250_000, maximum: 1_000_000), 3)
        XCTAssertEqual(UsageCalendarModel.intensity(total: 562_499, maximum: 1_000_000), 3)
        XCTAssertEqual(UsageCalendarModel.intensity(total: 562_500, maximum: 1_000_000), 4)
        XCTAssertEqual(UsageCalendarModel.intensity(total: 1_000_000, maximum: 1_000_000), 4)
    }

    func testUsageCalendarIntensityRangesMatchEveryDisplayedLevel() throws {
        let maximum = 1_000_000
        let ranges = try (1...4).map { level in
            try XCTUnwrap(UsageCalendarModel.intensityRange(level: level, maximum: maximum))
        }

        XCTAssertEqual(ranges.first?.lowerBound, 1)
        XCTAssertEqual(ranges.last?.upperBound, maximum)

        for (index, range) in ranges.enumerated() {
            let level = index + 1
            XCTAssertEqual(UsageCalendarModel.intensity(total: range.lowerBound, maximum: maximum), level)
            XCTAssertEqual(UsageCalendarModel.intensity(total: range.upperBound, maximum: maximum), level)
            if index > 0 {
                XCTAssertEqual(ranges[index - 1].upperBound + 1, range.lowerBound)
            }
        }

        XCTAssertNil(UsageCalendarModel.intensityRange(level: 1, maximum: 1))
        XCTAssertEqual(UsageCalendarModel.intensityRange(level: 4, maximum: 1), 1...1)
        XCTAssertNil(UsageCalendarModel.intensityRange(level: 5, maximum: maximum))
        XCTAssertNil(UsageCalendarModel.intensityRange(level: 1, maximum: 0))
    }

    func testMenuQuotaResetTextUsesRelativeDescriptionAndLabeledFallback() {
        let now = Date(timeIntervalSince1970: 1_000)
        let relativeQuota = QuotaSnapshot(
            id: "7d",
            title: "7 天",
            remaining: 0.52,
            resetText: "2026-07-22 10:08",
            resetsAt: now.addingTimeInterval(6 * 86_400)
        )
        let fallbackQuota = QuotaSnapshot(
            id: "7d",
            title: "7 天",
            remaining: 0.52,
            resetText: "2026-07-22 10:08"
        )

        XCTAssertEqual(MenuBarQuotaResetText.text(for: relativeQuota, now: now), "6 天后重置")
        XCTAssertEqual(
            MenuBarQuotaResetText.text(for: fallbackQuota, now: now),
            "2026-07-22 10:08 重置"
        )
    }

    func testMenuQuotaResetTextShowsDetailedDayAndHourCountdown() {
        let now = Date(timeIntervalSince1970: 1_000)
        let quota = QuotaSnapshot(
            id: "7d",
            title: "7 天",
            remaining: 0.52,
            resetText: "",
            resetsAt: now.addingTimeInterval(5 * 86_400 + 22 * 3_600 + 37 * 60)
        )

        XCTAssertEqual(
            MenuBarQuotaResetText.text(for: quota, now: now),
            "5 天 22 小时后重置"
        )
    }

    func testMenuSummaryLayoutStacksOnlyWhenBothQuotasAreVisible() {
        XCTAssertEqual(MenuBarSummaryLayout.layout(forQuotaCount: 0), .sideBySide)
        XCTAssertEqual(MenuBarSummaryLayout.layout(forQuotaCount: 1), .sideBySide)
        XCTAssertEqual(MenuBarSummaryLayout.layout(forQuotaCount: 2), .stacked)
    }

    func testQuotaObservationDescriptionUsesActualObservationAge() {
        let now = Date(timeIntervalSince1970: 100_000)
        let quota = QuotaSnapshot(
            id: "7d",
            title: "7 天",
            remaining: 0.52,
            resetText: "2026-07-22 10:08",
            observedAt: now.addingTimeInterval(-125)
        )

        XCTAssertEqual(quota.observationDescription(now: now), "2 分钟前观测")
        XCTAssertEqual(
            MenuBarQuotaTimingText.text(for: quota, now: now),
            "2026-07-22 10:08 重置 · 2 分钟前观测"
        )
    }

    func testFormatsCompactValues() {
        XCTAssertEqual(TokenFormatter.compact(999), "999")
        XCTAssertEqual(TokenFormatter.compact(1_500), "1.5K")
        XCTAssertEqual(TokenFormatter.compact(17_000_000), "17.0M")
        XCTAssertEqual(TokenFormatter.compact(1_061_100_000), "1.1B")
    }

    func testFormatsPercentagesWithOneDecimalPlace() {
        XCTAssertEqual(TokenFormatter.percentage(0.48235), "48.2%")
        XCTAssertEqual(TokenFormatter.percentage(0), "0.0%")
        XCTAssertEqual(TokenFormatter.percentage(1), "100.0%")
    }
}

@MainActor
final class StatusItemPresentationTests: XCTestCase {
    func testSummaryPlacementPersistsAndDefaultsToMenuBar() {
        let suiteName = "SummaryPlacementTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        XCTAssertEqual(SummaryPlacementPreference.load(from: defaults), .menuBar)
        defaults.set("notch", forKey: AppPreferenceKeys.summaryPlacement)
        XCTAssertEqual(SummaryPlacementPreference.load(from: defaults), .notch)
        defaults.set("menuBar", forKey: AppPreferenceKeys.summaryPlacement)
        XCTAssertEqual(SummaryPlacementPreference.load(from: defaults), .menuBar)
        defaults.set("unknown", forKey: AppPreferenceKeys.summaryPlacement)
        XCTAssertEqual(SummaryPlacementPreference.load(from: defaults), .menuBar)
    }

    func testNotchSummaryUsesGlobalCoordinatesAndStaysBelowCamera() throws {
        let screen = NSRect(x: -1512, y: 200, width: 1512, height: 982)
        let frame = try XCTUnwrap(NotchSummaryLayout.frame(
            screenFrame: screen,
            topInset: 32,
            leftArea: NSRect(x: -1512, y: 1150, width: 660, height: 32),
            rightArea: NSRect(x: -660, y: 1150, width: 660, height: 32),
            contentWidth: 180
        ))
        XCTAssertEqual(frame.midX, -756)
        XCTAssertEqual(frame.maxY, screen.maxY - 32)
        XCTAssertTrue(screen.contains(frame))
        XCTAssertEqual(frame.width, 180)
    }

    func testNotchSummaryFallsBackForUnobscuredOrUnknownScreens() {
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        XCTAssertNil(NotchSummaryLayout.frame(
            screenFrame: screen, topInset: 0, leftArea: nil, rightArea: nil, contentWidth: 180
        ))
        XCTAssertNil(NotchSummaryLayout.frame(
            screenFrame: screen, topInset: 32, leftArea: nil, rightArea: nil, contentWidth: 180
        ))
        XCTAssertNil(NotchSummaryLayout.frame(
            screenFrame: screen, topInset: 32,
            leftArea: NSRect(x: 0, y: 1048, width: 960, height: 32),
            rightArea: NSRect(x: 960, y: 1048, width: 960, height: 32),
            contentWidth: 180
        ))
    }

    func testAppWindowLevelPolicyKeepsSettingsAbovePinnedDashboard() {
        let dashboardLevel = AppWindowLevelPolicy.level(
            for: .dashboard,
            keepsDashboardOnTop: true
        )
        let settingsLevel = AppWindowLevelPolicy.level(
            for: .settings,
            keepsDashboardOnTop: true
        )

        XCTAssertEqual(dashboardLevel, .floating)
        XCTAssertEqual(settingsLevel, .modalPanel)
        XCTAssertGreaterThan(settingsLevel.rawValue, dashboardLevel.rawValue)
        XCTAssertEqual(
            AppWindowLevelPolicy.level(for: .dashboard, keepsDashboardOnTop: false),
            .normal
        )
        XCTAssertEqual(
            AppWindowLevelPolicy.level(for: .settings, keepsDashboardOnTop: false),
            .normal
        )
    }

    func testUsesCodexUCompatibleCanvasAndIconMetrics() {
        let presentation = StatusItemPresentation(
            snapshot: .preview,
            configuration: .standard
        )

        XCTAssertEqual(presentation.imageSize.height, 22)
        XCTAssertEqual(StatusItemLayoutMetrics.iconRect, NSRect(x: 2, y: 2, width: 18, height: 18))
        XCTAssertEqual(StatusItemLayoutMetrics.elementSpacing, 5)
        XCTAssertEqual(
            StatusItemLayoutMetrics.leadingContentWidth,
            StatusItemLayoutMetrics.iconRect.maxX + StatusItemLayoutMetrics.elementSpacing
        )
        XCTAssertEqual(presentation.itemLength, presentation.imageSize.width + 8)

        guard let appearance = NSAppearance(named: .aqua) else {
            return XCTFail("Expected the standard Aqua appearance to be available")
        }
        let image = StatusItemRenderer().render(presentation, appearance: appearance)
        XCTAssertEqual(image.size, presentation.imageSize)
        XCTAssertFalse(image.isTemplate)
    }

    func testStatusItemRendererPreservesTheCallersGraphicsTransform() throws {
        let canvas = NSImage(size: NSSize(width: 320, height: 80))
        canvas.lockFocus()
        defer { canvas.unlockFocus() }

        let context = try XCTUnwrap(NSGraphicsContext.current?.cgContext)
        context.translateBy(x: 13, y: 7)
        context.scaleBy(x: 1.25, y: 0.75)
        let transformBeforeRendering = context.ctm
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let presentation = StatusItemPresentation(
            snapshot: .preview,
            configuration: .standard
        )

        _ = StatusItemRenderer().render(presentation, appearance: appearance)

        XCTAssertEqual(context.ctm.a, transformBeforeRendering.a, accuracy: 0.000_001)
        XCTAssertEqual(context.ctm.b, transformBeforeRendering.b, accuracy: 0.000_001)
        XCTAssertEqual(context.ctm.c, transformBeforeRendering.c, accuracy: 0.000_001)
        XCTAssertEqual(context.ctm.d, transformBeforeRendering.d, accuracy: 0.000_001)
        XCTAssertEqual(context.ctm.tx, transformBeforeRendering.tx, accuracy: 0.000_001)
        XCTAssertEqual(context.ctm.ty, transformBeforeRendering.ty, accuracy: 0.000_001)
    }

    func testStatusItemRendererAllocatesEnoughWidthForTwoDigitCountdownSuffix() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: StatusItemLayoutMetrics.numericFontSize, weight: .semibold)
        let leadingInset: CGFloat = 12
        let trailingInset: CGFloat = 5
        let availableTextWidth = StatusItemLayoutMetrics.richResetWidth
            - leadingInset
            - trailingInset

        for countdown in ["24h", "60m"] {
            let requiredTextWidth = NSAttributedString(
                string: countdown,
                attributes: [.font: font]
            ).size().width
            XCTAssertGreaterThanOrEqual(availableTextWidth, requiredTextWidth, countdown)
        }
    }

    func testQuotaPillTextMaintainsReadableContrastAcrossEveryPaletteSurface() throws {
        for skin in AppSkinPreference.allCases {
            for name in [NSAppearance.Name.aqua, .darkAqua] {
                let appearance = try XCTUnwrap(NSAppearance(named: name))
                let theme = StatusItemTheme.resolve(skin: skin, preference: .system, appearance: appearance)
                XCTAssertGreaterThanOrEqual(try contrastRatio(theme.primary, theme.background), 4.5, skin.rawValue)
                XCTAssertGreaterThanOrEqual(try contrastRatio(theme.countdown, theme.countdownBackground), 4.5, skin.rawValue)
                for role in [StatusItemQuotaPaletteRole.fiveHour, .weekly] {
                    let palette = StatusItemQuotaPalette.resolve(role, theme: theme)
                    XCTAssertEqual(palette.background.alphaComponent, 1)
                    XCTAssertGreaterThanOrEqual(try contrastRatio(palette.text, palette.background), 4.5, skin.rawValue)
                    XCTAssertGreaterThanOrEqual(try contrastRatio(palette.start, palette.background), 3, skin.rawValue)
                }
            }
        }
    }

    func testSummaryDigitsUseConsistentSizeWithoutClippingFullQuota() {
        for skin in AppSkinPreference.allCases {
            let theme = StatusItemTheme(skin: skin, dark: false)
            XCTAssertEqual(theme.valueFont.pointSize, StatusItemLayoutMetrics.numericFontSize)
            let bounds = NSAttributedString(string: "100%", attributes: [.font: theme.valueFont]).size()
            XCTAssertLessThanOrEqual(bounds.width, StatusItemLayoutMetrics.richValueWidth, skin.rawValue)
            XCTAssertLessThanOrEqual(bounds.height, 14, skin.rawValue)
        }
    }

    func testSummaryAppearanceRespectsFixedSkinsAndExplicitColorPreference() throws {
        let light = try XCTUnwrap(NSAppearance(named: .aqua))
        let dark = try XCTUnwrap(NSAppearance(named: .darkAqua))
        for skin in AppSkinPreference.allCases {
            for preference in AppColorSchemePreference.allCases {
                for appearance in [light, dark] {
                    let theme = StatusItemTheme.resolve(skin: skin, preference: preference, appearance: appearance)
                    let expectedDark = skin.fixedColorScheme.map { $0 == .dark }
                        ?? preference.colorScheme.map { $0 == .dark }
                        ?? (appearance.name == .darkAqua)
                    XCTAssertEqual(theme.dark, expectedDark, "\(skin) / \(preference)")
                }
            }
        }
    }

    func testThemeSwitchChangesRenderedSummaryWithoutChangingItsLayout() throws {
        let presentation = StatusItemPresentation(snapshot: .preview, configuration: .standard)
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        for style in [StatusItemRenderer.Style.menuBar, .notch] {
            var images = Set<Data>()
            for skin in AppSkinPreference.allCases {
                let theme = StatusItemTheme.resolve(skin: skin, preference: .system, appearance: appearance)
                let image = StatusItemRenderer(style: style, theme: theme).render(presentation, appearance: appearance)
                XCTAssertEqual(image.size, presentation.imageSize)
                images.insert(try XCTUnwrap(image.tiffRepresentation))
            }
            XCTAssertEqual(images.count, AppSkinPreference.allCases.count)
        }
    }

    func testBuildsOnlyConfiguredQuotaMetrics() {
        let presentation = StatusItemPresentation(
            snapshot: .preview,
            configuration: .standard
        )

        XCTAssertEqual(presentation.metrics.map(\.label), ["7d"])
        XCTAssertEqual(presentation.metrics.map(\.value), ["84%"])
        XCTAssertEqual(presentation.metrics.map(\.paletteRole), [.weekly])
        XCTAssertFalse(presentation.label.contains("今日"))
    }

    func testDisabledLivePreviewCollapsesStatusItemToIconOnly() {
        let presentation = StatusItemPresentation(
            snapshot: .preview,
            configuration: MenuBarLabelConfiguration(
                showsLivePreview: false,
                quotaDisplay: .remaining,
                showsFiveHour: true,
                showsWeekly: true,
                showsResetCountdown: true
            )
        )

        XCTAssertTrue(presentation.metrics.isEmpty)
        XCTAssertEqual(presentation.imageSize.width, StatusItemLayoutMetrics.emptyImageWidth)
        XCTAssertEqual(presentation.label, "CodexVista")
        XCTAssertTrue(presentation.tooltip.contains("实时预览已关闭"))
    }

    func testCountdownPreferenceControlsInlineResetAndCodexStyleTooltip() {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = DashboardSnapshot(
            planName: "Pro 20x",
            updatedText: "刚刚",
            periods: DashboardSnapshot.preview.periods,
            quotas: [
                QuotaSnapshot(
                    id: "7d", title: "7 天", remaining: 0.57, resetText: "",
                    resetsAt: now.addingTimeInterval(6 * 86_400)
                )
            ],
            models: [],
            dailyUsage: []
        )
        let visible = StatusItemPresentation(
            snapshot: snapshot,
            configuration: .standard,
            now: now
        )
        let hidden = StatusItemPresentation(
            snapshot: snapshot,
            configuration: MenuBarLabelConfiguration(
                showsLivePreview: true,
                quotaDisplay: .remaining,
                showsFiveHour: true,
                showsWeekly: true,
                showsResetCountdown: false
            ),
            now: now
        )

        XCTAssertEqual(visible.metrics.first?.resetText, "6d")
        XCTAssertTrue(visible.tooltip.contains("7 天额度 剩余 57%，6 天后重置"))
        XCTAssertTrue(visible.tooltip.contains("点击查看用量"))
        XCTAssertFalse(visible.tooltip.contains("Codex 用量菜单"))
        XCTAssertNil(hidden.metrics.first?.resetText)
        XCTAssertFalse(hidden.tooltip.contains("重置"))
        XCTAssertLessThan(hidden.imageSize.width, visible.imageSize.width)
        XCTAssertEqual(
            visible.imageSize.width,
            StatusItemLayoutMetrics.leadingContentWidth
                + StatusItemLayoutMetrics.richValueWidth
                + StatusItemLayoutMetrics.elementSpacing
                + StatusItemLayoutMetrics.richResetWidth
                + 2
        )
        XCTAssertEqual(
            hidden.imageSize.width,
            StatusItemLayoutMetrics.leadingContentWidth
                + StatusItemLayoutMetrics.richValueWidth
                + 2
        )
    }

    private func contrastRatio(_ foreground: NSColor, _ background: NSColor) throws -> CGFloat {
        let foregroundLuminance = try relativeLuminance(foreground)
        let backgroundLuminance = try relativeLuminance(background)
        return (max(foregroundLuminance, backgroundLuminance) + 0.05)
            / (min(foregroundLuminance, backgroundLuminance) + 0.05)
    }

    private func relativeLuminance(_ color: NSColor) throws -> CGFloat {
        let color = try XCTUnwrap(color.usingColorSpace(.sRGB))
        func linearize(_ component: CGFloat) -> CGFloat {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(color.redComponent)
            + 0.7152 * linearize(color.greenComponent)
            + 0.0722 * linearize(color.blueComponent)
    }
}

final class DashboardSnapshotTests: XCTestCase {
    func testTrendRangesExposeExpectedLabelsAndDefault() {
        XCTAssertEqual(TrendRange.allCases.map(\.rawValue), ["7 天", "30 天", "周期"])
        XCTAssertEqual(TrendRange.defaultRange, .sevenDays)
    }

    func testTrendRangeHidesXAxisOnlyWhenThirtyDaysAreSelected() {
        XCTAssertTrue(TrendRange.sevenDays.showsXAxis)
        XCTAssertFalse(TrendRange.thirtyDays.showsXAxis)
        XCTAssertFalse(TrendRange.subscriptionCycles.showsXAxis)
    }

    func testActivityRangesExposeExpectedLabelsDefaultAndIndependentSnapshots() {
        XCTAssertEqual(ActivityRange.allCases.map(\.rawValue), ["今日", "7 日", "30 日", "累计"])
        XCTAssertEqual(ActivityRange.defaultRange, .sevenDays)
        let today = ActivityRanking(
            skills: [.init(name: "today-skill", count: 1)],
            tools: [.init(name: "today-tool", count: 1)]
        )
        let seven = ActivityRanking(
            skills: [.init(name: "seven-skill", count: 7)],
            tools: [.init(name: "seven-tool", count: 7)]
        )
        let thirty = ActivityRanking(
            skills: [.init(name: "thirty-skill", count: 30)],
            tools: []
        )
        let all = ActivityRanking(
            skills: [],
            tools: [.init(name: "all-tool", count: 99)]
        )
        let snapshot = ActivityRankingSnapshot(
            today: today,
            sevenDays: seven,
            thirtyDays: thirty,
            allTime: all
        )

        XCTAssertEqual(snapshot.ranking(for: .today), today)
        XCTAssertEqual(snapshot.ranking(for: .sevenDays), seven)
        XCTAssertEqual(snapshot.ranking(for: .thirtyDays), thirty)
        XCTAssertEqual(snapshot.ranking(for: .allTime), all)
    }

    func testTrendRangesSelectLatestUsage() {
        let history = makeDailyUsage(count: 45)
        let cycles = [DailyUsage(id: "cycle", day: "周期", total: 99)]

        XCTAssertEqual(TrendRange.sevenDays.select(from: history).map(\.total), Array(39...45))
        XCTAssertEqual(TrendRange.thirtyDays.select(from: history).map(\.total), Array(16...45))
        XCTAssertEqual(
            TrendRange.subscriptionCycles.select(
                from: history,
                subscriptionCycleUsage: cycles
            ).map(\.total),
            [99]
        )
    }

    func testTrendRangeHandlesLimitedAndEmptyUsage() {
        let limited = makeDailyUsage(count: 3)

        XCTAssertEqual(TrendRange.sevenDays.select(from: limited).map(\.total), [1, 2, 3])
        XCTAssertTrue(TrendRange.thirtyDays.select(from: []).isEmpty)
    }

    func testPreviewContainsHistoryForSupportedTrendRanges() {
        XCTAssertGreaterThanOrEqual(DashboardSnapshot.preview.dailyUsage.count, 45)
    }

    func testPeriodShareUsesCurrentPeriodTotal() {
        let today = DashboardSnapshot.preview.periods[0]

        XCTAssertEqual(today.share(of: today.uncachedInput), 0.48235, accuracy: 0.00001)
    }

    func testPeriodShareHandlesZeroAndClampsInvalidValues() {
        let zeroTotal = PeriodUsage(
            id: "zero",
            title: "空周期",
            total: 0,
            uncachedInput: 0,
            cachedInput: 0,
            output: 0,
            reasoning: 0
        )
        let regular = DashboardSnapshot.preview.periods[0]

        XCTAssertEqual(zeroTotal.share(of: 10), 0)
        XCTAssertEqual(regular.share(of: -1), 0)
        XCTAssertEqual(regular.share(of: regular.total + 1), 1)
    }

    func testQuotaCenterLabelsUseCompactPeriods() {
        let quotas = DashboardSnapshot.preview.quotas

        XCTAssertEqual(quotas.map(\.compactTitle), ["5H", "7d"])
        XCTAssertEqual(quotas.map(\.remainingLabel), ["5H 85%", "7d 84%"])
    }

    func testPreviewQuotaResetTextUsesDashboardFormat() {
        let quotas = DashboardSnapshot.preview.quotas

        XCTAssertEqual(quotas.map(\.resetText), ["02:52", "07-13"])
        XCTAssertFalse(quotas.contains { $0.resetText.contains("重置") })
    }

    func testQuotaAccessorsDoNotDependOnArrayIndexes() {
        let snapshot = makeSnapshot(
            quotas: Array(DashboardSnapshot.preview.quotas.reversed())
        )

        XCTAssertEqual(snapshot.fiveHourQuota?.id, "5h")
        XCTAssertEqual(snapshot.weeklyQuota?.id, "7d")
        XCTAssertEqual(snapshot.visibleQuotas.map(\.id), ["5h", "7d"])
        XCTAssertEqual(snapshot.menuBarQuotaLabel, "7d 84%")
    }

    func testMissingFiveHourQuotaOnlyExposesWeeklyQuota() {
        let weeklyQuota = DashboardSnapshot.preview.quotas.first { $0.id == "7d" }!
        let snapshot = makeSnapshot(quotas: [weeklyQuota])

        XCTAssertNil(snapshot.fiveHourQuota)
        XCTAssertEqual(snapshot.visibleQuotas.map(\.id), ["7d"])
        XCTAssertEqual(snapshot.menuBarQuotaLabel, "7d 84%")
    }

    func testStandardMenuBarLabelIgnoresExhaustedFiveHourQuota() {
        let exhaustedFiveHourQuota = QuotaSnapshot(
            id: "5h",
            title: "5 小时",
            remaining: 0,
            resetText: "02:52"
        )
        let weeklyQuota = DashboardSnapshot.preview.quotas.first { $0.id == "7d" }!
        let snapshot = makeSnapshot(quotas: [exhaustedFiveHourQuota, weeklyQuota])

        XCTAssertNotNil(snapshot.fiveHourQuota)
        XCTAssertEqual(snapshot.visibleQuotas.map(\.id), ["5h", "7d"])
        XCTAssertEqual(snapshot.menuBarQuotaLabel, "7d 84%")
    }

    func testMenuBarConfigurationControlsMetricAndVisibleContent() {
        let usedFiveHour = MenuBarLabelConfiguration(
            showsLivePreview: true,
            quotaDisplay: .used,
            showsFiveHour: true,
            showsWeekly: false,
            showsResetCountdown: true
        )
        let remainingWeekly = MenuBarLabelConfiguration(
            showsLivePreview: true,
            quotaDisplay: .remaining,
            showsFiveHour: false,
            showsWeekly: true,
            showsResetCountdown: true
        )

        XCTAssertEqual(
            DashboardSnapshot.preview.menuBarLabel(configuration: usedFiveHour),
            "5H 15%"
        )
        XCTAssertEqual(
            DashboardSnapshot.preview.menuBarLabel(configuration: remainingWeekly),
            "7d 84%"
        )
    }

    func testMenuBarConfigurationFallsBackWhenEveryItemIsHidden() {
        let hidden = MenuBarLabelConfiguration(
            showsLivePreview: true,
            quotaDisplay: .remaining,
            showsFiveHour: false,
            showsWeekly: false,
            showsResetCountdown: true
        )

        XCTAssertEqual(
            DashboardSnapshot.preview.menuBarLabel(configuration: hidden),
            "CodexVista"
        )
    }

    func testMenuBarConfigurationHidesAllContentWhenLivePreviewIsDisabled() {
        let hidden = MenuBarLabelConfiguration(
            showsLivePreview: false,
            quotaDisplay: .remaining,
            showsFiveHour: true,
            showsWeekly: true,
            showsResetCountdown: true
        )

        XCTAssertEqual(
            DashboardSnapshot.preview.menuBarLabel(configuration: hidden),
            "CodexVista"
        )
    }

    func testQuotaResetCountdownUsesCompactMinuteHourAndDayUnits() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(
            QuotaSnapshot(
                id: "5h", title: "5 小时", remaining: 0.8, resetText: "",
                resetsAt: now.addingTimeInterval(30 * 60)
            ).resetCountdown(now: now),
            "30m"
        )
        XCTAssertEqual(
            QuotaSnapshot(
                id: "5h", title: "5 小时", remaining: 0.8, resetText: "",
                resetsAt: now.addingTimeInterval(2 * 3_600)
            ).resetCountdown(now: now),
            "2h"
        )
        XCTAssertEqual(
            QuotaSnapshot(
                id: "7d", title: "7 天", remaining: 0.8, resetText: "",
                resetsAt: now.addingTimeInterval(6 * 86_400 + 23 * 3_600)
            ).resetCountdown(now: now),
            "7d"
        )
        XCTAssertEqual(
            QuotaSnapshot(
                id: "7d", title: "7 天", remaining: 0.8, resetText: "",
                resetsAt: now.addingTimeInterval(5 * 86_400 + 22 * 3_600)
            ).resetCountdown(now: now),
            "6d"
        )
    }

    func testPreviewPeriodsUseConsistentTotals() {
        let periods = DashboardSnapshot.preview.periods

        XCTAssertEqual(periods.map(\.title), ["今日", "7 日", "30 日", "累计"])
        XCTAssertEqual(periods.count, 4)

        for period in periods {
            XCTAssertEqual(
                period.total,
                period.uncachedInput
                    + period.cachedInput
                    + period.visibleOutput
                    + period.reasoning
            )
        }
    }

    func testTodayBreakdownSplitsReasoningFromOutput() {
        let snapshot = DashboardSnapshot.preview
        let today = snapshot.periods[0]

        XCTAssertEqual(snapshot.todayTokens, today.total)
        XCTAssertEqual(snapshot.thirtyDayTokens, snapshot.periods[2].total)
        XCTAssertEqual(snapshot.totalTokens, snapshot.periods[3].total)
        XCTAssertEqual(snapshot.breakdown.input, today.uncachedInput)
        XCTAssertEqual(snapshot.breakdown.cachedInput, today.cachedInput)
        XCTAssertEqual(snapshot.breakdown.output, today.visibleOutput)
        XCTAssertEqual(snapshot.breakdown.reasoning, today.reasoning)
        XCTAssertEqual(snapshot.breakdown.total, today.total)
    }

    private func makeDailyUsage(count: Int) -> [DailyUsage] {
        (1...count).map { value in
            DailyUsage(id: "\(value)", day: "\(value)", total: value)
        }
    }

    private func makeSnapshot(quotas: [QuotaSnapshot]) -> DashboardSnapshot {
        let preview = DashboardSnapshot.preview
        return DashboardSnapshot(
            planName: preview.planName,
            updatedText: preview.updatedText,
            periods: preview.periods,
            quotas: quotas,
            models: preview.models,
            dailyUsage: preview.dailyUsage
        )
    }
}
