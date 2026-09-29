import AppKit
import SwiftUI
import Charts

enum MenuBarAvailabilityText {
    static func text(for state: DashboardLoadState) -> String {
        switch state {
        case .loaded: "可用"
        case .stale: "数据待更新"
        case .loading: "载入中"
        case .empty: "暂无数据"
        case .failed, .unsupported: "不可用"
        }
    }
}

enum MenuBarUpdateText {
    static func text(
        for state: DashboardLoadState,
        calendar: Calendar = .current
    ) -> String {
        switch state {
        case .loading:
            "正在载入"
        case .loaded(let snapshot, let summary):
            snapshotText(snapshot, summary: summary, calendar: calendar)
        case .empty:
            "未检测到 Codex 数据"
        case .stale(let snapshot, let summary, _):
            "部分数据待更新 · \(snapshotText(snapshot, summary: summary, calendar: calendar))"
        case .failed(let message), .unsupported(let message):
            message
        }
    }

    private static func snapshotText(
        _ snapshot: DashboardSnapshot,
        summary: SourceSummary,
        calendar: Calendar
    ) -> String {
        let statusText = snapshot.updatedText == "刚刚刷新" ? "刚刚更新" : snapshot.updatedText
        guard let refreshedAt = summary.lastSuccessfulRefresh else { return statusText }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return "\(statusText) · \(formatter.string(from: refreshedAt))"
    }
}

enum MenuBarQuotaResetText {
    static func text(for quota: QuotaSnapshot, now: Date = Date()) -> String {
        quota.detailedResetDescription(now: now) ?? "\(quota.resetText) 重置"
    }
}

enum MenuBarQuotaTimingText {
    static func text(for quota: QuotaSnapshot, now: Date = Date()) -> String {
        let resetText = MenuBarQuotaResetText.text(for: quota, now: now)
        guard let observationText = quota.observationDescription(now: now) else {
            return resetText
        }
        return "\(resetText) · \(observationText)"
    }
}

struct MenuBarUnavailableContent: Equatable {
    let title: String
    let description: String
    let systemImage: String
    let showsRefresh: Bool

    static func content(for state: DashboardLoadState) -> MenuBarUnavailableContent? {
        switch state {
        case .loading:
            MenuBarUnavailableContent(
                title: "正在载入 Codex 数据",
                description: "CodexVista 正在读取本地统计。",
                systemImage: "chart.bar.doc.horizontal",
                showsRefresh: false
            )
        case .empty:
            MenuBarUnavailableContent(
                title: "未检测到 Codex 数据",
                description: "使用 Codex 后重新刷新即可查看 Token 用量。",
                systemImage: "tray",
                showsRefresh: true
            )
        case .failed(let message):
            MenuBarUnavailableContent(
                title: "暂时无法读取数据",
                description: message,
                systemImage: "exclamationmark.triangle",
                showsRefresh: true
            )
        case .unsupported(let message):
            MenuBarUnavailableContent(
                title: "数据格式暂不兼容",
                description: message,
                systemImage: "doc.badge.ellipsis",
                showsRefresh: true
            )
        case .loaded, .stale:
            nil
        }
    }
}

enum MenuBarSummaryLayout: Equatable {
    case sideBySide
    case stacked

    static func layout(forQuotaCount count: Int) -> MenuBarSummaryLayout {
        count > 1 ? .stacked : .sideBySide
    }
}

struct MenuBarPopoverView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var colorScheme

    let store: DashboardStore
    let updateService: AppUpdateService
    private let onOpenDashboard: (() -> Void)?
    private let onOpenSettings: (() -> Void)?

    init(
        store: DashboardStore,
        updateService: AppUpdateService,
        onOpenDashboard: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil
    ) {
        self.store = store
        self.updateService = updateService
        self.onOpenDashboard = onOpenDashboard
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        CodexVistaGlassGroup(spacing: 10) {
            VStack(spacing: 10) {
                header
                popoverContent
                updateStatus
                footerActions
            }
        }
        .padding(16)
        .frame(width: 390)
        .background { CodexVistaBackdrop() }
        .foregroundStyle(CodexVistaTheme.dashboardPrimaryText)
        .task { await store.start() }
    }

    private var updateStatus: some View {
        HStack(spacing: 8) {
            Image(systemName: updateStatusSymbol)
                .foregroundStyle(updateStatusColor)

            VStack(alignment: .leading, spacing: 1) {
                Text(updateStatusTitle)
                    .font(.caption.weight(.medium))
            }

            Spacer(minLength: 8)

            updateStatusControl
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .help(Text(verbatim: "当前版本 v\(updateService.currentVersion)"))
    }

    @ViewBuilder
    private var updateStatusControl: some View {
        switch updateService.state {
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .available:
            HStack(spacing: 6) {
                Button("手动下载") { updateService.openReleasePage() }
                    .buttonStyle(.plain)
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                Button("更新") {
                    Task { await updateService.updateNow() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        case .downloading:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("下载中")
                    .font(.caption)
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            }
        case .ready:
            Button("打开安装包") {
                Task { await updateService.updateNow() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        case .idle, .upToDate, .failed:
            Button("检查更新") {
                Task { await updateService.checkForUpdates() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var updateStatusTitle: String {
        switch updateService.state {
        case .idle: "软件更新"
        case .checking: "正在检查更新"
        case .upToDate: "已是最新版本"
        case .available(let release): "新版本 v\(release.version) 可用"
        case .downloading(let release): "正在下载 v\(release.version)"
        case .ready(let release, _): "v\(release.version) 已下载"
        case .failed: "暂时无法检查更新"
        }
    }

    private var updateStatusSymbol: String {
        switch updateService.state {
        case .available, .ready: "arrow.down.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .upToDate: "checkmark.circle.fill"
        case .idle, .checking, .downloading: "arrow.triangle.2.circlepath"
        }
    }

    private var updateStatusColor: Color {
        switch updateService.state {
        case .available, .ready: CodexVistaTheme.accent
        case .failed: .orange
        case .upToDate: .green
        case .idle, .checking, .downloading: CodexVistaTheme.dashboardMutedText
        }
    }

    @ViewBuilder
    private var popoverContent: some View {
        if let content = MenuBarUnavailableContent.content(for: store.state) {
            unavailableCard(content)
        } else {
            usageCard
            todayCard
        }
    }

    private func unavailableCard(_ content: MenuBarUnavailableContent) -> some View {
        VStack(spacing: 9) {
            Image(systemName: content.systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(unavailableIconColor)

            Text(content.title)
                .font(CodexVistaTheme.headingFont(size: 13))

            Text(content.description)
                .font(.caption)
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if content.showsRefresh {
                Button("重新刷新", systemImage: "arrow.clockwise") {
                    Task { await store.refresh() }
                }
                .buttonStyle(.bordered)
                .disabled(store.isRefreshing)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 136)
        .dashboardCard(padding: 14)
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 21.5, height: 21.5)
                .foregroundStyle(.white)
                .padding(6.5)
                .background(CodexVistaTheme.brandGradient, in: RoundedRectangle(cornerRadius: CodexVistaTheme.cornerRadius(8)))

            VStack(alignment: .leading, spacing: 3) {
                Text("CodexVista")
                    .font(CodexVistaTheme.headingFont(size: 14.5))
                Text(MenuBarUpdateText.text(for: store.state))
                    .font(.system(size: 10.5))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                Task { await store.refresh() }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: CodexVistaTheme.cornerRadius(8))
                        .fill(CodexVistaTheme.dashboardControlBackground)

                    if store.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(CodexVistaTheme.accent)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(store.isRefreshing)
            .accessibilityLabel(store.isRefreshing ? "正在刷新" : "刷新")
            .help(store.isRefreshing ? "正在刷新" : "刷新")
        }
    }

    private var usageCard: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image("CodexIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                    Text("Codex · \(store.snapshot?.planName ?? "未检测到")")
                }
                .font(CodexVistaTheme.headingFont(size: 13))
                Spacer()
                Label(availabilityText, systemImage: availabilitySymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(availabilityColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(availabilityColor.opacity(0.12), in: Capsule())
            }

            quotaSection

            Divider().overlay(CodexVistaTheme.dashboardBorder)

            MenuBarQuotaHistoryChart(history: store.snapshot?.quotaHistory ?? .empty)
        }
        .dashboardCard(padding: 14)
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            wideTodaySummary
            TokenCompositionView(breakdown: store.snapshot?.breakdown,
                                 total: store.snapshot?.todayTokens,
                                 compact: true)
        }
        .dashboardCard(padding: 14)
    }

    private var footerActions: some View {
        HStack(spacing: 10) {
            Button("打开看板", systemImage: "square.grid.2x2") {
                if let onOpenDashboard {
                    onOpenDashboard()
                } else {
                    openWindow(id: "dashboard")
                }
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.borderedProminent)

            Button("设置", systemImage: "gearshape") {
                if let onOpenSettings {
                    onOpenSettings()
                } else {
                    openSettings()
                }
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.bordered)

            Spacer(minLength: 0)

            Divider()
                .frame(height: 18)

            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
            }
            .buttonStyle(.plain)
            .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            .help("退出 CodexVista")
        }
    }

    private var wideTodaySummary: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("今日 Token")
                .font(.caption)
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)

            Spacer()

            todayTokenValue
        }
    }

    private var todayTokenValue: some View {
        Text(store.snapshot.map { TokenFormatter.compact($0.todayTokens) } ?? "--")
            .font(CodexVistaTheme.metricFont(size: 20))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    @ViewBuilder
    private var quotaSection: some View {
        let quotas = store.snapshot?.visibleQuotas ?? []

        if quotas.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(CodexVistaTheme.headingFont(size: 13))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)

                VStack(alignment: .leading, spacing: 3) {
                    Text("暂无可用额度数据")
                        .font(.subheadline.weight(.semibold))
                    Text("等待 Codex 返回额度信息")
                        .font(.caption)
                        .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        } else {
            HStack(spacing: 12) {
                ForEach(quotas) { quota in
                    quotaColumn(quota, color: quotaColor(for: quota))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func quotaColumn(_ quota: QuotaSnapshot, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(quota.title)剩余")
                    .font(.caption)
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                Spacer(minLength: 6)
                Text("\(quota.remainingPercent)%")
                    .font(CodexVistaTheme.metricFont(size: 16))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }

            ProgressView(value: quota.remaining)
                .tint(color)
                .controlSize(.mini)

            Text(MenuBarQuotaTimingText.text(for: quota))
                .font(.caption)
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("额度信息来自最近一次 Codex 本地观测")
    }

    private func quotaColor(for quota: QuotaSnapshot) -> Color {
        quota.id == "7d" ? CodexVistaTheme.accent : CodexVistaTheme.accentBlue
    }

    private var availabilityText: String {
        MenuBarAvailabilityText.text(for: store.state)
    }

    private var availabilityColor: Color {
        switch store.state {
        case .loaded: .green
        case .stale: .orange
        case .loading, .empty: CodexVistaTheme.dashboardMutedText
        case .failed, .unsupported: .red
        }
    }

    private var availabilitySymbol: String {
        switch store.state {
        case .loaded: "checkmark.circle.fill"
        case .stale: "clock.badge.exclamationmark"
        case .loading: "arrow.triangle.2.circlepath"
        case .empty: "minus.circle"
        case .failed, .unsupported: "exclamationmark.triangle.fill"
        }
    }

    private var unavailableIconColor: Color {
        switch store.state {
        case .failed, .unsupported:
            .red
        case .stale:
            .orange
        case .loading, .empty, .loaded:
            CodexVistaTheme.popoverPrimary
        }
    }
}

struct MenuBarQuotaHistoryChart: View {
    private enum TimeRange: Hashable {
        case today
        case sevenDays
    }

    let history: QuotaHistorySnapshot
    @State private var hoveredDate: Date?
    @State private var timeRange: TimeRange = .today

    private var visibleHistory: QuotaHistorySnapshot {
        timeRange == .today ? history.today() : history
    }

    private func changeDescription(_ change: QuotaHistorySnapshot.PointChange) -> String {
        let percentagePoints = abs(change.quotaDecreasePercentagePoints)
            .formatted(.number.precision(.fractionLength(1)))
        let quotaChange: String
        if change.quotaDecreasePercentagePoints > 0.0001 {
            quotaChange = "额度减少 \(percentagePoints) 个百分点"
        } else if change.quotaDecreasePercentagePoints < -0.0001 {
            quotaChange = "额度回升 \(percentagePoints) 个百分点"
        } else {
            quotaChange = "额度持平"
        }
        return "较上一节点 · \(quotaChange) · Token 增加 \(change.tokenIncrease.formatted())"
    }

    var body: some View {
        let displayedHistory = visibleHistory
        let tokenMaximum = displayedHistory.points.map(\.tokens).max() ?? 0
        let selectedIndex = hoveredDate.flatMap { hoveredDate in
            displayedHistory.points.indices.min {
                abs(displayedHistory.points[$0].observedAt.timeIntervalSince(hoveredDate)) <
                    abs(displayedHistory.points[$1].observedAt.timeIntervalSince(hoveredDate))
            }
        }
        let selected = selectedIndex.map { displayedHistory.points[$0] }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("额度趋势")
                    .font(CodexVistaTheme.headingFont(size: 12))
                Spacer()
                Text("● 剩余 %")
                    .font(.system(size: 10))
                    .foregroundStyle(CodexVistaTheme.dashboardAccent)
                if tokenMaximum > 0 {
                    Text("● 周期 Token")
                        .font(.system(size: 10))
                        .foregroundStyle(CodexVistaTheme.dashboardCachedInput)
                }
                Picker("趋势范围", selection: $timeRange) {
                    Text("今日").tag(TimeRange.today)
                    Text("7 日").tag(TimeRange.sevenDays)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 112)
            }
            Group {
                if displayedHistory.points.isEmpty {
                    Text(timeRange == .today ? "今日暂无额度观测" : "近 7 天暂无额度观测")
                        .font(.caption)
                        .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Chart {
                        ForEach(displayedHistory.bridges) { bridge in
                            LineMark(
                                x: .value("时间", bridge.start.observedAt),
                                y: .value("剩余额度", bridge.start.remaining * 100),
                                series: .value("序列", "bridge-\(bridge.id)")
                            )
                            .interpolationMethod(.linear)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                            LineMark(
                                x: .value("时间", bridge.end.observedAt),
                                y: .value("剩余额度", bridge.end.remaining * 100),
                                series: .value("序列", "bridge-\(bridge.id)")
                            )
                            .interpolationMethod(.linear)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                        }
                        ForEach(displayedHistory.points) { point in
                            LineMark(
                                x: .value("时间", point.observedAt),
                                y: .value("剩余额度", point.remaining * 100),
                                series: .value("序列", "quota-\(point.segment)")
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(CodexVistaTheme.dashboardAccent)
                            PointMark(x: .value("时间", point.observedAt), y: .value("剩余额度", point.remaining * 100))
                                .symbolSize(7)
                                .foregroundStyle(CodexVistaTheme.dashboardAccent)
                        }
                        if tokenMaximum > 0 {
                            ForEach(displayedHistory.points) { point in
                                LineMark(
                                    x: .value("时间", point.observedAt),
                                    y: .value("周期累计 Token", Double(point.tokens) / Double(tokenMaximum) * 100),
                                    series: .value("序列", "token-\(point.cycle)")
                                )
                                .interpolationMethod(.monotone)
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                                .foregroundStyle(CodexVistaTheme.dashboardCachedInput)
                            }
                        }
                        if let selected {
                            RuleMark(x: .value("时间", selected.observedAt))
                                .foregroundStyle(CodexVistaTheme.dashboardMutedText.opacity(0.5))
                            PointMark(x: .value("时间", selected.observedAt), y: .value("剩余额度", selected.remaining * 100))
                                .symbolSize(30)
                                .foregroundStyle(CodexVistaTheme.dashboardAccent)
                            if tokenMaximum > 0 {
                                PointMark(
                                    x: .value("时间", selected.observedAt),
                                    y: .value("周期累计 Token", Double(selected.tokens) / Double(tokenMaximum) * 100)
                                )
                                .symbolSize(30)
                                .foregroundStyle(CodexVistaTheme.dashboardCachedInput)
                            }
                        }
                    }
                    .chartXScale(domain: displayedHistory.chartDomain)
                    .chartYScale(domain: 0...100)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                            AxisGridLine()
                            AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%").font(.system(size: 9)) }
                        }
                        if tokenMaximum > 0 {
                            AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                                AxisValueLabel {
                                    let tokens = Int64(Double(tokenMaximum) * Double(value.as(Int.self) ?? 0) / 100)
                                    Text(TokenFormatter.compact(Int(clamping: tokens)))
                                        .font(.system(size: 9))
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        if timeRange == .today {
                            AxisMarks(values: .stride(by: .hour, count: 2)) { value in
                                if let date = value.as(Date.self),
                                   date <= displayedHistory.end.addingTimeInterval(-45 * 60) {
                                    AxisValueLabel(format: .dateTime.hour())
                                        .font(.system(size: 9))
                                }
                            }
                        } else {
                            AxisMarks(values: .stride(by: .day, count: 2)) { value in
                                if let date = value.as(Date.self),
                                   date <= displayedHistory.end.addingTimeInterval(-24 * 60 * 60) {
                                    AxisValueLabel(format: .dateTime.month().day())
                                        .font(.system(size: 9))
                                }
                            }
                        }
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let location):
                                        guard let plot = proxy.plotFrame else { return }
                                        let frame = geometry[plot]
                                        hoveredDate = frame.contains(location)
                                            ? proxy.value(atX: location.x - frame.minX, as: Date.self) : nil
                                    case .ended:
                                        hoveredDate = nil
                                    }
                                }
                        }
                    }
                }
            }
            .frame(height: 120)
            VStack(alignment: .leading, spacing: 2) {
                Text(selected.map {
                    $0.observedAt.formatted(.dateTime.month().day().hour().minute()) +
                        " · 剩余 " + TokenFormatter.percentage($0.remaining) +
                        (tokenMaximum > 0 ? " · 周期累计 " + TokenFormatter.compact(Int(clamping: $0.tokens)) + " Token" : "")
                } ?? "本地观测 · 虚线表示观测间隔")
                    .lineLimit(1)
                if let selectedIndex {
                    Text(displayedHistory.changeFromPrevious(at: selectedIndex).map(changeDescription)
                         ?? (selectedIndex == 0 ? "本范围首个观测点" : "新周期首个观测点"))
                        .lineLimit(1)
                }
            }
            .font(.system(size: 9))
            .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: timeRange) { _, _ in hoveredDate = nil }
    }
}
