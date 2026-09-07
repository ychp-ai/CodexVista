import AppKit
import SwiftUI

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
                Text(verbatim: "当前版本 v\(updateService.currentVersion)")
                    .font(.caption2)
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            }

            Spacer(minLength: 8)

            updateStatusControl
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            CodexVistaTheme.dashboardControlBackground.opacity(0.58),
            in: RoundedRectangle(cornerRadius: CodexVistaTheme.cornerRadius(10), style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CodexVistaTheme.cornerRadius(10), style: .continuous)
                .stroke(CodexVistaTheme.dashboardBorder)
        }
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

            quotaAndTodaySummary

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("今日构成")
                    Spacer()
                    Text(store.snapshot == nil ? "暂无数据" : "按今日总量")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                TokenCompositionView(breakdown: store.snapshot?.breakdown,
                                     total: store.snapshot?.todayTokens)
            }
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

    private var quotaAndTodaySummary: some View {
        let quotaCount = store.snapshot?.visibleQuotas.count ?? 0

        return Group {
            switch MenuBarSummaryLayout.layout(forQuotaCount: quotaCount) {
            case .sideBySide:
                HStack(alignment: .top, spacing: 10) {
                    quotaSection

                    Rectangle()
                        .fill(CodexVistaTheme.dashboardBorder)
                        .frame(width: 1, height: 58)

                    compactTodaySummary
                }
            case .stacked:
                VStack(spacing: 9) {
                    quotaSection

                    Rectangle()
                        .fill(CodexVistaTheme.dashboardBorder)
                        .frame(height: 1)

                    wideTodaySummary
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CodexVistaTheme.dashboardSurface, in: RoundedRectangle(cornerRadius: CodexVistaTheme.cornerRadius(10)))
    }

    private var compactTodaySummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("今日 Token")
                .font(.caption)
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)

            todayTokenValue
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: 84, height: 58, alignment: .top)
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
