import AppKit
import SwiftUI

@main
@MainActor
enum DocumentationCapture {
    static var captures: [[String: Any]] = []
    static var output: URL!

    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        output = URL(fileURLWithPath: CommandLine.arguments[1])
        // Volatile defaults in a distinct bundle; never alter the user's preferences.
        UserDefaults.standard.setVolatileDomain([
            AppPreferenceKeys.skin: "standard", AppPreferenceKeys.colorScheme: "light",
            AppPreferenceKeys.firstSubscriptionDate: DocumentationFixture.snapshot.subscriptionCycle!.start.timeIntervalSince1970,
            AppPreferenceKeys.automaticRefreshEnabled: false,
            AppPreferenceKeys.automaticallyChecksForUpdates: false,
            AppPreferenceKeys.usageRemindersEnabled: true,
            "AppleLanguages": ["zh-Hans"], "AppleLocale": "zh_CN"
        ], forName: UserDefaults.argumentDomain)

        let store = DashboardStore(client: DocumentationDataClient(), automaticRefreshEnabled: false)
        store.state = .loaded(DocumentationFixture.snapshot, DocumentationDataClient.summary)
        store.sourceSummary = DocumentationDataClient.summary
        let reminders = UsageReminderController(store: store, notificationClient: DocumentationNotifications())
        reminders.authorizationStatus = .authorized
        let updates = AppUpdateService(provider: DocumentationUpdates())
        updates.state = .upToDate(checkedAt: DocumentationFixture.now)
        let settings = SettingsView(store: store, reminderController: reminders, updateService: updates)
        let snapshot = DocumentationFixture.snapshot

        for tab in DashboardAnalyticsTab.allCases {
            let names: [DashboardAnalyticsTab: String] = [.todayTasks: "today-tasks", .trend: "dashboard",
                                                          .activity: "activity-usage", .project: "project-usage"]
            try capture("codexvista-\(names[tab]!).png", title: tab.rawValue,
                        width: 1060, height: 840,
                        DashboardContentView(snapshot: snapshot, selectedRange: tab == .trend ? .thirtyDays : .sevenDays, selectedAnalyticsTab: tab))
        }
        try capture("codexvista-dashboard-compact.png", title: "最小窗口 · 紧凑概览", width: 920, height: 690,
                    DashboardContentView(snapshot: snapshot, selectedAnalyticsTab: .todayTasks, showsExpandedOverview: false))
        try capture("codexvista-subscription-composition.png", title: "订阅周期 · Token 构成", width: 920, height: 690,
                    DashboardContentView(snapshot: snapshot, selectedPeriodID: "subscriptionCycle", showsExpandedOverview: true))
        let workspace = DocumentationFixture.workspaces[0]
        let conversation = workspace.conversations[0]
        let replyRow = ProjectReplyDetailRow(id: "example-row", conversationTitle: conversation.displayTitle!,
                                            reply: conversation.replies[0])
        let task = TodayTaskUsageEntry(workspace: workspace, conversation: conversation)
        let detail = ProjectDetailView(entry: workspace, rank: 1, range: .sevenDays,
                                       onClose: {}, onDetailHover: { _ in })
        for tab in ProjectDetailTab.allCases {
            let names: [ProjectDetailTab: String] = [.overview: "project-overview", .conversations: "task-details", .replies: "reply-details"]
            try capture("codexvista-\(names[tab]!).png", title: "项目 · \(tab.rawValue)", width: 1120, height: 700,
                        ProjectDetailView(entry: workspace, rank: 1, range: .sevenDays,
                                          onClose: {}, onDetailHover: { _ in }, selectedTab: tab))
        }
        try capture("codexvista-today-task-detail.png", title: "今日任务详情", width: 960, height: 800,
                    TodayTaskDetailView(task: task, onClose: {}, onReplyHover: { _ in }))
        try capture("codexvista-task-activity-detail.png", title: "任务调用明细", width: 520,
                    ProjectConversationHoverCard(conversation: conversation))
        try capture("codexvista-reply-activity-detail.png", title: "回复调用明细", width: 520,
                    ProjectReplyHoverCard(row: replyRow))
        try capture("codexvista-today-task-reply-hover.png", title: "今日任务 · 回复调用明细", width: 520,
                    ProjectReplyHoverCard(row: replyRow))
        try capture("codexvista-project-trend-hover.png", title: "项目趋势节点", width: 300,
                    detail.trendTooltip(for: workspace.dailyUsage.last!).padding(24))

        let usage = snapshot.dailyUsage.last!
        try capture("codexvista-trend-hover.png", title: "趋势节点明细", width: 430,
                    DailyUsageHoverCard(usage: usage, dateText: "2026年9月4日", showsModelDetails: .constant(false)).padding(24))
        try capture("codexvista-trend-hover-details.png", title: "趋势节点 · 模型明细", width: 430,
                    DailyUsageHoverCard(usage: usage, dateText: "2026年9月4日", showsModelDetails: .constant(true)).padding(24))
        try capture("codexvista-calendar-day-hover.png", title: "用量日历 · 日期明细", width: 430,
                    VStack(spacing: 14) {
                        UsageCalendarPanel(usage: snapshot.dailyUsage, today: DocumentationFixture.now).frame(height: 270)
                        DailyUsageHoverCard(usage: usage, dateText: "2026年9月4日", showsModelDetails: .constant(false))
                    }.padding(24))
        try capture("codexvista-calendar-legend-hover.png", title: "用量日历 · 图例明细", width: 340,
                    UsageHeatLegendHoverCard(level: 4, range: 1_200_000...1_200_000,
                                            maximum: 1_200_000, color: CodexVistaTheme.dashboardAccent).padding(24))
        try capture("codexvista-skill-breakdown-hover.png", title: "Skills · 命名空间细分", width: 450,
                    SkillBreakdownPopover(entry: DocumentationFixture.activity.skills[0]).padding(16))
        try capture("codexvista-model-hover-details.png", title: "7 日 · 完整模型排行", width: 780,
                    PeriodModelRankingPopover(periodTitle: "7 日", periodSubtitle: nil,
                        ranking: snapshot.modelUsage.sevenDays, isPinned: true, onTogglePin: {}, onClose: {}))
        try capture("codexvista-model-preview.png", title: "7 日 · 前五名模型预览", width: 780,
                    PeriodModelRankingPopover(periodTitle: "7 日", periodSubtitle: nil,
                        ranking: snapshot.modelUsage.sevenDays, isPinned: false, onTogglePin: {}, onClose: {}))
        try capture("codexvista-model-cost-hover-details.png", title: "模型费用明细", width: 430,
                    ModelCostDetailCard(entry: snapshot.modelUsage.today.entries[0]).padding(20))
        try capture("codexvista-model-token-hover-details.png", title: "模型 Token 明细", width: 430,
                    ModelTokenDetailCard(entry: snapshot.modelUsage.today.entries[0]).padding(20))
        try capture("codexvista-model-pricing-popover.png", title: "模型标准价格目录", width: 760,
                    ModelPricingExplanationView().padding(20))
        try capture("codexvista-popover.png", title: "菜单栏弹窗", width: 390,
                    MenuBarPopoverView(store: store, updateService: updates))

        let categories = [("appearance", "外观"), ("dashboard", "看板与摘要"), ("reminders", "额度提醒"),
                          ("data", "数据与更新"), ("plans", "订阅与关于")]
        // Native Settings toolbar is checked in the product. Offscreen capture renders
        // each production content page directly, since NSTabView draws a black strip.
        let settingsPages = [
            AnyView(settings.settingsPage { settings.appearanceSettings }),
            AnyView(settings.settingsPage { settings.dashboardSettings; settings.statusBarSettings }),
            AnyView(settings.settingsPage { settings.usageReminderSettings }),
            AnyView(settings.settingsPage { settings.dataAndRefreshSettings; settings.softwareUpdateSettings }),
            AnyView(settings.settingsPage { settings.planAndBillingSettings; settings.privacyNotice })
        ]
        for (index, category) in categories.enumerated() {
            try capture("codexvista-settings-\(category.0).png", title: category.1, width: 640, height: 700,
                settingsPages[index].padding(12))
        }
        try capture("codexvista-settings.png", title: "设置 · 外观", width: 640, height: 700, settingsPages[0].padding(12))
        try capture("layout/daily-reading.png", title: "完整用量明细", width: 620, height: 640,
                    DailyUsageHoverCard(usage: usage, dateText: "2026年9月4日", showsModelDetails: .constant(true), isExpanded: true))
        for tab in DashboardAnalyticsTab.allCases {
            try capture("layout/main-\(tab).png", title: "最小窗口 · \(tab.rawValue)", width: 920, height: 690,
                        DashboardContentView(snapshot: snapshot, selectedAnalyticsTab: tab))
        }
        for tab in ProjectDetailTab.allCases {
            try capture("layout/project-\(tab).png", title: "最小项目详情 · \(tab.rawValue)", width: 760, height: 560,
                        ProjectDetailView(entry: workspace, rank: 1, range: .sevenDays,
                                          onClose: {}, onDetailHover: { _ in }, selectedTab: tab))
        }
        let dense = DocumentationFixture.denseWorkspace
        for tab in ["回复明细", "用量与调用", "关联目录"] {
            try capture("layout/task-\(tab).png", title: "最小任务详情 · \(tab)", width: 760, height: 560,
                TodayTaskDetailView(task: .init(workspace: dense, conversation: dense.conversations[0]),
                                   onClose: {}, onReplyHover: { _ in }, selectedDetailTab: tab))
        }
        let denseRanking = WorkspaceUsageRanking(entries: [dense], totalTokens: dense.tokens, workspaceCount: 1, projectCount: 1)
        let denseSnapshot = DashboardSnapshot(planName: snapshot.planName, updatedText: snapshot.updatedText,
            periods: snapshot.periods, quotas: snapshot.quotas, models: snapshot.models, dailyUsage: snapshot.dailyUsage,
            workspaceUsage: .init(today: denseRanking, sevenDays: denseRanking, thirtyDays: denseRanking, allTime: denseRanking))
        try capture("layout/main-dense.png", title: "30 条任务 · 最小窗口 · 手动收起概览", width: 920, height: 690,
                    DashboardContentView(snapshot: denseSnapshot, showsExpandedOverview: false))
        let longActivity = ActivityRanking(skills: DocumentationFixture.activity.skills,
            tools: [.init(name: String(repeating: "example_namespace_", count: 5), count: 999)])
        try capture("layout/activity-long-name.png", title: "长工具名称", width: 880, height: 400,
                    ActivityRankingPanel(ranking: longActivity))
        for width: CGFloat in [880, 1_040] {
            try capture("layout/reply-trace-\(Int(width)).png", title: "回复调用链", width: width, height: 560,
                        ReplyTraceContent(trace: DocumentationFixture.trace, totalTokens: 40_000))
        }
        try capture("layout/reply-trace-slow-tools.png", title: "调用链 · 慢工具排行", width: 420,
                    ReplyTraceSlowTools(nodes: DocumentationFixture.trace.slowestTools,
                                        traceStart: DocumentationFixture.trace.start, onSelect: { _ in }))

        let presentation = StatusItemPresentation(snapshot: snapshot, configuration: .standard, now: DocumentationFixture.now)
        try capture("codexvista-status-bar.png", title: "状态栏摘要", width: 350,
                    summary(presentation, skin: .standard, dark: false).padding(24))
        try capture("codexvista-notch-summary.png", title: "刘海下方摘要", width: 350,
                    NotchSummaryView(presentation: presentation, quotaDisplay: .remaining,
                                     theme: .init(skin: .standard, dark: false)).padding(24))
        let themes: [(AppSkinPreference, Bool, String)] = [
            (.standard, false, "light"), (.standard, true, "dark"), (.ink, false, "ink-light"),
            (.celadon, false, "celadon-light"), (.celadon, true, "celadon-dark"),
            (.dusk, false, "dusk-light"), (.dusk, true, "dusk-dark"),
            (.cyber, true, "cyber-dark"), (.xianxia, false, "xianxia-light")]
        for (skin, dark, suffix) in themes {
            setTheme(skin, dark: dark)
            try capture("themes/codexvista-token-colors-\(suffix).png",
                        title: "\(skin.title) · \(dark ? "深色" : "浅色") · Token 配色", width: 430,
                        VStack(alignment: .leading, spacing: 24) {
                            Text("四类 Token 对照").font(.headline)
                            TokenCompositionView(breakdown: .init(input: 25_000, cachedInput: 25_000,
                                                                 output: 25_000, reasoning: 25_000))
                            Text("缓存占比 95.4% · 紧凑浮层").font(.headline)
                            TokenCompositionView(breakdown: .init(input: 4_200, cachedInput: 95_400,
                                                                 output: 300, reasoning: 100), compact: true)
                        }.padding(24))
            try capture("themes/codexvista-\(suffix).png", title: "\(skin.title) · \(dark ? "深色" : "浅色")",
                        width: 1060, height: 840,
                        DashboardContentView(snapshot: snapshot, selectedAnalyticsTab: .todayTasks))
        }
        setTheme(.standard, dark: false)
        try capture("themes/codexvista-summary-themes.png", title: "状态栏与刘海 · 全部配色", width: 850,
                    VStack(spacing: 12) {
                        ForEach(themes.indices, id: \.self) { index in
                            let (skin, dark, _) = themes[index]
                            HStack(spacing: 32) {
                                Text("\(skin.title) · \(dark ? "深色" : "浅色")").frame(width: 130, alignment: .leading)
                                summary(presentation, skin: skin, dark: dark)
                                NotchSummaryView(presentation: presentation, quotaDisplay: .remaining,
                                                 theme: .init(skin: skin, dark: dark))
                            }.padding(14).frame(maxWidth: .infinity)
                                .background(dark ? Color(white: 0.16) : Color(white: 0.94))
                                .foregroundStyle(dark ? .white : .black)
                        }
                    }.padding(24))
        try capture("codexvista-loading.png", title: "首次载入", width: 1060, height: 840,
                    DashboardLoadingView())
        let emptyStore = DashboardStore(client: DocumentationDataClient(), automaticRefreshEnabled: false)
        // Render the production empty-state component without its data-loading task.
        try capture("codexvista-empty.png", title: "尚无本地数据", width: 800, height: 450,
                    DashboardView(store: emptyStore).unavailableView("未检测到 Codex 数据", systemImage: "tray",
                        description: "使用 Codex 后刷新即可在这里查看 Token 用量。"))
        let data = try JSONSerialization.data(withJSONObject: captures, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.appendingPathComponent("complete.json"))
    }

    static func setTheme(_ skin: AppSkinPreference, dark: Bool) {
        var domain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        domain[AppPreferenceKeys.skin] = skin.rawValue
        domain[AppPreferenceKeys.colorScheme] = dark ? "dark" : "light"
        UserDefaults.standard.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }

    static func summary(_ presentation: StatusItemPresentation, skin: AppSkinPreference, dark: Bool) -> some View {
        Image(nsImage: StatusItemRenderer(theme: .init(skin: skin, dark: dark)).render(
            presentation, appearance: NSAppearance(named: dark ? .darkAqua : .aqua)!))
    }

    static func capture<V: View>(_ path: String, title: String, width: CGFloat,
                                 height: CGFloat? = nil, _ content: V) throws {
        try path.write(to: output.appendingPathComponent("progress.txt"), atomically: true, encoding: .utf8)
        let dark = AppColorSchemePreference.load() == .dark
        let view = VStack(spacing: 0) {
            HStack {
                Text("CodexVista · \(title)").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("示例数据").font(.system(size: 10))
            }.padding(.horizontal, 20).frame(height: 42)
                .background(CodexVistaTheme.dashboardSurface)
            content.frame(width: width, height: height)
        }
        .frame(width: width)
        .environment(\.colorScheme, dark ? .dark : .light)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .transaction { $0.disablesAnimations = true }
        .tint(CodexVistaTheme.accent)
        .foregroundStyle(CodexVistaTheme.dashboardPrimaryText)
        .background(CodexVistaTheme.dashboardBackground)
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -16_000, y: 0))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        hosting.layoutSubtreeIfNeeded()
        try save(hosting, path: path, title: title)
        window.orderOut(nil)
    }

    static func save(_ view: NSView, path: String, title: String) throws {
        let bounds = view.bounds
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2),
            pixelsHigh: Int(bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = bounds.size
        view.cacheDisplay(in: bounds, to: bitmap)
        let url = output.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        captures.append(["path": path, "title": title, "width": bitmap.pixelsWide, "height": bitmap.pixelsHigh])
    }

}
