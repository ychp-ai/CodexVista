import AppKit
import Charts
import SwiftUI

enum DashboardRefreshBadge: Equatable {
    case success
    case warning
    case failure

    var symbolName: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failure: "xmark.circle.fill"
        }
    }
}

enum DashboardRefreshStatus: Equatable {
    case refreshed(String)
    case warning(String)

    static func resolve(from state: DashboardLoadState) -> DashboardRefreshStatus? {
        switch state {
        case .loaded(let snapshot, _):
            return .refreshed(snapshot.updatedText)
        case .stale(_, _, let message):
            return .warning(message)
        case .loading, .empty, .failed, .unsupported:
            return nil
        }
    }

    var badge: DashboardRefreshBadge {
        switch self {
        case .refreshed: .success
        case .warning: .warning
        }
    }

    var buttonHelp: String {
        switch self {
        case .refreshed(let text): "\(text)，点击再次刷新"
        case .warning(let message): "\(message) 点击重试刷新"
        }
    }
}

struct DashboardView: View {
    let store: DashboardStore
    @AppStorage(AppPreferenceKeys.keepsDashboardOnTop) private var keepsDashboardOnTop = false

    var body: some View {
        Group {
            switch store.state {
            case .loading:
                DashboardLoadingView()
            case .loaded(let snapshot, _):
                DashboardContentView(
                    snapshot: snapshot
                )
            case .empty:
                unavailableView(
                    "未检测到 Codex 数据",
                    systemImage: "tray",
                    description: "使用 Codex 后刷新即可在这里查看 Token 用量。"
                )
            case .stale(let snapshot, _, _):
                DashboardContentView(
                    snapshot: snapshot
                )
            case .failed(let message):
                unavailableView(
                    "暂时无法载入数据",
                    systemImage: "exclamationmark.triangle",
                    description: message
                )
            case .unsupported(let message):
                unavailableView(
                    "Codex 数据格式暂不兼容",
                    systemImage: "doc.badge.ellipsis",
                    description: message
                )
            }
        }
        .task { await store.start() }
        .background {
            CodexVistaBackdrop()
        }
        .background(DashboardWindowSizingBridge(
            expandedContentSize: DashboardWindowLayout.expandedContentSize(
                hasSubscriptionCycle: store.snapshot?.subscriptionCycle != nil
            )
        ))
        .background(DashboardWindowChromeBridge())
        .toolbar {
            dashboardToolbar
        }
    }

    @ToolbarContentBuilder
    private var dashboardToolbar: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.flexible, placement: .primaryAction)
            dashboardToolbarItems
                .sharedBackgroundVisibility(.hidden)
        } else {
            dashboardToolbarItems
        }
    }

    @ToolbarContentBuilder
    private var dashboardToolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await store.refresh() }
            } label: {
                DashboardRefreshButtonLabel(
                    isRefreshing: store.isRefreshing,
                    badge: refreshButtonBadge
                )
                .accessibilityHidden(true)
            }
            .disabled(store.isRefreshing)
            .keyboardShortcut("r", modifiers: .command)
            .accessibilityLabel(refreshButtonAccessibilityLabel)
            .accessibilityHint(refreshButtonHelp)
            .help(refreshButtonTooltipText)

            SettingsLink {
                Label("设置", systemImage: "gearshape")
                    .labelStyle(.iconOnly)
                    .frame(width: 16, height: 16)
            }
            .help("设置")

            Button {
                keepsDashboardOnTop.toggle()
            } label: {
                Image(systemName: keepsDashboardOnTop ? "pin.fill" : "pin")
                    .foregroundStyle(keepsDashboardOnTop ? Color.accentColor : Color.primary)
                    .frame(width: 16, height: 16)
            }
            .accessibilityLabel(keepsDashboardOnTop ? "取消看板置顶" : "置顶看板")
            .accessibilityValue(keepsDashboardOnTop ? "已置顶" : "未置顶")
            .accessibilityAddTraits(keepsDashboardOnTop ? .isSelected : [])
            .help(keepsDashboardOnTop ? "取消看板置顶" : "置顶看板")
        }
    }

    private var refreshButtonStatus: DashboardRefreshStatus? {
        DashboardRefreshStatus.resolve(from: store.state)
    }

    private var refreshButtonBadge: DashboardRefreshBadge? {
        guard !store.isRefreshing else { return nil }
        if let refreshButtonStatus {
            return refreshButtonStatus.badge
        }
        return switch store.state {
        case .failed: .failure
        case .unsupported: .warning
        case .loading, .loaded, .empty, .stale: nil
        }
    }

    private var refreshButtonHelp: String {
        if store.isRefreshing {
            return "正在重新读取本机 Codex 数据"
        }
        if let refreshButtonStatus {
            return refreshButtonStatus.buttonHelp
        }
        return switch store.state {
        case .failed(let message), .unsupported(let message):
            "\(message) 点击重试刷新"
        case .loading, .loaded, .empty, .stale:
            "刷新本机 Codex 数据"
        }
    }

    private var refreshButtonTooltipTitle: String {
        if store.isRefreshing {
            return "正在刷新"
        }
        return switch store.state {
        case .loaded: "数据已刷新"
        case .stale: "部分数据未刷新"
        case .failed: "刷新失败"
        case .unsupported: "数据格式不兼容"
        case .loading, .empty: "刷新看板数据"
        }
    }

    private var refreshButtonTooltipText: String {
        "\(refreshButtonTooltipTitle)\n\(refreshButtonHelp)\n快捷键 ⌘R"
    }

    private var refreshButtonAccessibilityLabel: String {
        if store.isRefreshing {
            return "正在刷新本机 Codex 数据"
        }
        return switch store.state {
        case .loaded(let snapshot, _): "\(snapshot.updatedText)，再次刷新"
        case .stale: "部分数据未刷新，重试"
        case .failed: "刷新失败，重试"
        case .unsupported: "数据格式不兼容，重试刷新"
        case .loading, .empty: "刷新本机 Codex 数据"
        }
    }

    private func unavailableView(
        _ title: String,
        systemImage: String,
        description: String
    ) -> some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(description)
        )
        .frame(
            minWidth: DashboardWindowLayout.baseExpandedContentSize.width,
            minHeight: DashboardWindowLayout.baseExpandedContentSize.height
        )
        .background(CodexVistaTheme.dashboardBackground)
    }
}

private struct DashboardRefreshButtonLabel: View {
    let isRefreshing: Bool
    let badge: DashboardRefreshBadge?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .frame(width: 16, height: 16)

            if let badge, !isRefreshing {
                Image(systemName: badge.symbolName)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(badgeColor(for: badge))
                    .background {
                        Circle()
                            .fill(Color(nsColor: .windowBackgroundColor))
                            .frame(width: 7, height: 7)
                    }
                    .offset(x: 3, y: 3)
            }
        }
        .frame(width: 18, height: 18)
    }

    private func badgeColor(for badge: DashboardRefreshBadge) -> Color {
        switch badge {
        case .success: .green
        case .warning: .orange
        case .failure: .red
        }
    }
}

private struct DashboardLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHighlighted = false

    var body: some View {
        ZStack {
            DashboardBackdrop()

            CodexVistaGlassGroup(spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    loadingOverview
                        .frame(height: DashboardWindowLayout.standardOverviewHeight)
                    loadingAnalytics
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .padding(.top, 10)
        }
        .frame(
            minWidth: DashboardWindowLayout.baseExpandedContentSize.width,
            minHeight: DashboardWindowLayout.baseExpandedContentSize.height
        )
        .foregroundStyle(CodexVistaTheme.dashboardPrimaryText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在载入 Codex 本地统计")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                isHighlighted = true
            }
        }
    }

    private var loadingOverview: some View {
        HStack(spacing: 16) {
            loadingQuota
                .frame(width: 280)

            Rectangle()
                .fill(CodexVistaTheme.dashboardBorder)
                .frame(width: 1)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 10
            ) {
                ForEach(0..<4, id: \.self) { index in
                    DashboardLoadingMetricTile(
                        index: index,
                        isHighlighted: isHighlighted
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .dashboardPanel(padding: 14, strong: true)
    }

    private var loadingQuota: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("额度使用", systemImage: "gauge.with.dots.needle.50percent")
                    .font(CodexVistaTheme.headingFont(size: 14))

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(CodexVistaTheme.dashboardAccent)
                    Text("正在读取")
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("额度使用，正在读取 Codex 本地数据")

            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(CodexVistaTheme.dashboardAccent.opacity(0.18), lineWidth: 2)
                    Circle()
                        .trim(from: 0.05, to: 0.32)
                        .stroke(
                            CodexVistaTheme.brandGradient,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(isHighlighted ? 230 : -40))

                    Text("…")
                        .font(CodexVistaTheme.metricFont(size: 24))
                        .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                }
                .frame(width: 112, height: 112)

                HStack(spacing: 8) {
                    Circle()
                        .fill(CodexVistaTheme.dashboardAccent.opacity(0.74))
                        .frame(width: 6, height: 6)
                    DashboardLoadingBlock(width: 58, height: 8, isHighlighted: isHighlighted)
                    Spacer(minLength: 8)
                    DashboardLoadingBlock(width: 42, height: 8, isHighlighted: isHighlighted)
                }
                .frame(maxWidth: 200)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var loadingAnalytics: some View {
        VStack(spacing: 9) {
            HStack(spacing: 2) {
                ForEach(
                    Array(["今日任务", "用量趋势", "Skills / Tools", "项目用量"].enumerated()),
                    id: \.offset
                ) { index, title in
                    Text(title)
                        .font(.system(size: 11, weight: index == 0 ? .semibold : .medium))
                        .foregroundStyle(
                            index == 0
                                ? CodexVistaTheme.dashboardPrimaryText.opacity(0.76)
                                : CodexVistaTheme.dashboardMutedText.opacity(0.7)
                        )
                        .frame(width: index == 2 ? 102 : 82, height: 24)
                        .background {
                            if index == 0 {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(CodexVistaTheme.dashboardSurfaceStrong.opacity(0.72))
                            }
                        }
                }
            }
            .padding(3)
            .background(
                CodexVistaTheme.dashboardControlBackground,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(CodexVistaTheme.dashboardBorder.opacity(0.72))
            }
            .frame(height: 30)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CodexVistaTheme.dashboardAccent)
                    DashboardLoadingBlock(width: 76, height: 10, isHighlighted: isHighlighted)
                    Spacer()
                    DashboardLoadingBlock(width: 108, height: 9, isHighlighted: isHighlighted)
                }

                GeometryReader { geometry in
                    VStack(spacing: 12) {
                        ForEach(0..<5, id: \.self) { index in
                            HStack(spacing: 10) {
                                DashboardLoadingBlock(
                                    width: 24,
                                    height: 8,
                                    isHighlighted: isHighlighted
                                )
                                DashboardLoadingBlock(
                                    width: max(120, geometry.size.width * loadingBarFraction(index)),
                                    height: 8,
                                    isHighlighted: isHighlighted
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                CodexVistaTheme.dashboardTile.opacity(0.72),
                in: RoundedRectangle(cornerRadius: CodexVistaTheme.cornerRadius(12), style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CodexVistaTheme.cornerRadius(12), style: .continuous)
                    .stroke(CodexVistaTheme.dashboardBorder.opacity(0.78))
            }
        }
        .dashboardPanel(padding: 10)
    }

    private func loadingBarFraction(_ index: Int) -> CGFloat {
        [0.74, 0.52, 0.82, 0.43, 0.64][index]
    }
}

private struct DashboardLoadingMetricTile: View {
    let index: Int
    let isHighlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(CodexVistaTheme.dashboardControlBackground)
                    .frame(width: 26, height: 26)
                    .overlay {
                        Image(systemName: index < 2 ? "calendar" : "chart.bar.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(CodexVistaTheme.dashboardAccent.opacity(0.72))
                    }
                DashboardLoadingBlock(width: 46, height: 10, isHighlighted: isHighlighted)
                Spacer()
                DashboardLoadingBlock(width: 72, height: 16, isHighlighted: isHighlighted)
            }

            Rectangle()
                .fill(CodexVistaTheme.dashboardBorder.opacity(0.72))
                .frame(height: 1)

            HStack {
                DashboardLoadingBlock(width: 64, height: 8, isHighlighted: isHighlighted)
                Spacer()
                DashboardLoadingBlock(width: 48, height: 8, isHighlighted: isHighlighted)
            }
            HStack {
                DashboardLoadingBlock(width: 54, height: 8, isHighlighted: isHighlighted)
                Spacer()
                DashboardLoadingBlock(width: 58, height: 8, isHighlighted: isHighlighted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            CodexVistaTheme.dashboardTile.opacity(0.74),
            in: RoundedRectangle(cornerRadius: CodexVistaTheme.cornerRadius(12), style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CodexVistaTheme.cornerRadius(12), style: .continuous)
                .stroke(CodexVistaTheme.dashboardBorder.opacity(0.78))
        }
    }
}

private struct DashboardLoadingBlock: View {
    let width: CGFloat
    let height: CGFloat
    let isHighlighted: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        CodexVistaTheme.dashboardControlBackground.opacity(0.74),
                        CodexVistaTheme.dashboardAccent.opacity(isHighlighted ? 0.16 : 0.07),
                        CodexVistaTheme.dashboardControlBackground.opacity(0.74)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width, height: height)
            .opacity(isHighlighted ? 1 : 0.72)
    }
}

private struct DashboardBackdrop: View {
    var body: some View { CodexVistaBackdrop() }
}

enum DashboardWindowLayout {
    static let standardOverviewHeight: CGFloat = 310
    static let subscriptionOverviewHeight: CGFloat = 310
    static let baseExpandedContentSize = CGSize(width: 920, height: 690)

    static func overviewHeight(hasSubscriptionCycle: Bool) -> CGFloat {
        hasSubscriptionCycle ? subscriptionOverviewHeight : standardOverviewHeight
    }

    static func expandedContentSize(hasSubscriptionCycle: Bool) -> CGSize {
        let additionalHeight = overviewHeight(hasSubscriptionCycle: hasSubscriptionCycle)
            - standardOverviewHeight
        return CGSize(
            width: baseExpandedContentSize.width,
            height: baseExpandedContentSize.height + additionalHeight
        )
    }

    static func targetExpandedContentSize(current: CGSize, requested: CGSize) -> CGSize {
        CGSize(width: max(current.width, requested.width), height: max(current.height, requested.height))
    }

    /// NSWindow content size can include the transparent toolbar; dashboard size cannot.
    static func windowContentSize(for usableSize: CGSize, contentSize: CGSize, layoutSize: CGSize) -> CGSize {
        CGSize(
            width: usableSize.width + max(0, contentSize.width - layoutSize.width),
            height: usableSize.height + max(0, contentSize.height - layoutSize.height)
        )
    }
}

private struct DashboardWindowSizingBridge: NSViewRepresentable {
    let expandedContentSize: CGSize

    func makeNSView(context: Context) -> DashboardWindowSizingView {
        let view = DashboardWindowSizingView()
        view.setLayout(expandedContentSize: expandedContentSize)
        return view
    }

    func updateNSView(_ nsView: DashboardWindowSizingView, context: Context) {
        nsView.setLayout(expandedContentSize: expandedContentSize)
    }
}

private struct DashboardWindowChromeBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> DashboardWindowChromeView {
        DashboardWindowChromeView()
    }

    func updateNSView(_ nsView: DashboardWindowChromeView, context: Context) {
        nsView.hideWindowTitle()
    }
}

@MainActor
private final class DashboardWindowChromeView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hideWindowTitle()
    }

    func hideWindowTitle() {
        window?.titleVisibility = .hidden
    }
}

@MainActor
final class DashboardWindowSizingView: NSView {
    private var requestedExpandedContentSize = DashboardWindowLayout.baseExpandedContentSize
    private weak var managedWindow: NSWindow?
    private var layoutObservation: NSKeyValueObservation?
    private var sizingUpdatePending = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard managedWindow !== window else { return }
        layoutObservation = nil
        managedWindow = window
        // SwiftUI may install or rebuild its toolbar after this view joins the window.
        layoutObservation = window?.observe(\.contentLayoutRect, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.scheduleSizingUpdate() }
        }
        scheduleSizingUpdate()
    }

    func setLayout(expandedContentSize: CGSize) {
        guard requestedExpandedContentSize != expandedContentSize else { return }
        requestedExpandedContentSize = expandedContentSize
        scheduleSizingUpdate()
    }

    private func scheduleSizingUpdate() {
        guard !sizingUpdatePending else { return }
        sizingUpdatePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.sizingUpdatePending = false
            self.applyRequestedState()
        }
    }

    private func applyRequestedState() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        let layoutSize = window.contentLayoutRect.size
        guard layoutSize.width > 0, layoutSize.height > 0 else { return }
        var frame = window.frame
        let contentSize = window.contentRect(forFrameRect: frame).size
        let minimumContentSize = DashboardWindowLayout.windowContentSize(
            for: requestedExpandedContentSize, contentSize: contentSize, layoutSize: layoutSize
        )
        if window.contentMinSize != minimumContentSize {
            window.contentMinSize = minimumContentSize
        }
        let targetSize = DashboardWindowLayout.targetExpandedContentSize(
            current: layoutSize, requested: requestedExpandedContentSize
        )
        guard targetSize.width - layoutSize.width > 0.5 || targetSize.height - layoutSize.height > 0.5 else { return }

        let heightIncrease = targetSize.height - layoutSize.height
        frame.size.width += targetSize.width - layoutSize.width
        frame.size.height += heightIncrease
        frame.origin.y -= heightIncrease
        // Immediate sizing avoids overlapping animated resizes during loading/skin changes.
        window.setFrame(frame, display: true, animate: false)
    }
}

private struct DashboardContentView: View {
    let snapshot: DashboardSnapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedRange = TrendRange.defaultRange
    @State private var selectedAnalyticsTab = DashboardAnalyticsTab.defaultTab
    @State private var selectedActivityRange = ActivityRange.defaultRange
    @State private var selectedProjectRange = ActivityRange.defaultRange
    @State private var hoveredUsageID: DailyUsage.ID?
    @State private var selectedPeriodID = "today"

    private var hasSubscriptionCycle: Bool {
        snapshot.subscriptionCycle != nil
    }

    private var overviewHeight: CGFloat {
        DashboardWindowLayout.overviewHeight(hasSubscriptionCycle: hasSubscriptionCycle)
    }

    private var expandedContentSize: CGSize {
        DashboardWindowLayout.expandedContentSize(hasSubscriptionCycle: hasSubscriptionCycle)
    }

    var body: some View {
        ZStack {
            DashboardBackdrop()

            CodexVistaGlassGroup(spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    overviewPanel.frame(height: overviewHeight)
                    analyticsPanel.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .padding(.top, 10)
        }
        .frame(
            minWidth: expandedContentSize.width,
            minHeight: expandedContentSize.height
        )
        .foregroundStyle(CodexVistaTheme.dashboardPrimaryText)
    }

    private var overviewPanel: some View {
        HStack(spacing: 16) {
            currentQuotaSection.frame(width: 280)
            Rectangle()
                .fill(CodexVistaTheme.dashboardBorder)
                .frame(width: 1)
            periodMetricsSection
        }
        .dashboardPanel(padding: 14, strong: true)
    }

    private var currentQuotaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("额度使用", systemImage: "gauge.with.dots.needle.50percent")
                    .font(CodexVistaTheme.headingFont(size: 14))
                    .foregroundStyle(CodexVistaTheme.dashboardPrimaryText)

                Spacer(minLength: 8)

                quotaIdentityBadge
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("额度使用，Codex，\(snapshot.planName) 套餐")

            if snapshot.visibleQuotas.isEmpty {
                ContentUnavailableView(
                    "暂无额度数据",
                    systemImage: "chart.donut"
                )
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            } else if CodexVistaTheme.isInk {
                VStack(spacing: 8) {
                    ForEach(snapshot.visibleQuotas) { quota in
                        CodexVistaInkQuota(quota: quota, compact: snapshot.visibleQuotas.count > 1)
                    }
                    Spacer(minLength: 4)
                    quotaResetList
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                    CodexVistaInkPainting()
                        .frame(height: snapshot.visibleQuotas.count > 1 ? 44 : 68)
                        .overlay(alignment: .bottomTrailing) {
                            CodexVistaInkSeal().padding(.trailing, 4).padding(.bottom, 2)
                        }
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if CodexVistaTheme.skin == .xianxia {
                VStack(spacing: 16) {
                    CodexVistaXianxiaQuota(quotas: snapshot.visibleQuotas)
                    quotaResetList
                        .padding(.top, 10)
                        .overlay(alignment: .top) {
                            Rectangle().fill(CodexVistaTheme.dashboardBorder).frame(height: 0.5)
                        }
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 5) {
                    quotaRingGroup
                    quotaResetList
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(alignment: .bottom) {
            if !CodexVistaTheme.isInk && CodexVistaTheme.skin != .xianxia {
                CodexVistaSkinMotif(skin: CodexVistaTheme.skin)
                    .frame(height: 54)
            }
        }
    }

    private var quotaIdentityBadge: some View {
        HStack(spacing: 6) {
            Image("CodexIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)

            Circle()
                .fill(Color.green)
                .frame(width: 5, height: 5)
                .accessibilityHidden(true)

            Text("Codex · \(snapshot.planName)")
                .lineLimit(1)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(CodexVistaTheme.dashboardMutedText)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(CodexVistaTheme.dashboardControlBackground, in: Capsule())
        .overlay {
            Capsule()
                .stroke(CodexVistaTheme.dashboardBorder.opacity(0.7), lineWidth: 0.7)
        }
    }

    private func quotaColor(for quota: QuotaSnapshot) -> Color {
        quota.id == "7d" ? CodexVistaTheme.dashboardAccent : CodexVistaTheme.dashboardAccentSecondary
    }

    @ViewBuilder
    private var quotaRingGroup: some View {
        if CodexVistaTheme.skin == .cyber {
            VStack(spacing: 10) {
                ForEach(snapshot.visibleQuotas) { quota in
                    CodexVistaCyberQuota(quota: quota, compact: snapshot.visibleQuotas.count > 1)
                }
            }
        } else {
            instrumentQuotaRingGroup
        }
    }

    private var instrumentQuotaRingGroup: some View {
        ZStack {
            ForEach(snapshot.visibleQuotas) { quota in
                quotaRing(
                    quota,
                    diameter: quotaDiameter(for: quota),
                    lineWidth: quotaLineWidth(for: quota),
                    color: quotaColor(for: quota)
                )
            }

            if snapshot.visibleQuotas.count == 1,
               let quota = snapshot.visibleQuotas.first {
                quotaCenterLabel(quota)
            } else {
                if let weeklyQuota = snapshot.weeklyQuota {
                    quotaCenterLabel(weeklyQuota)
                }
                if let fiveHourQuota = snapshot.fiveHourQuota {
                    quotaOuterLabel(fiveHourQuota)
                        .offset(y: -56)
                }
            }
        }
        .frame(width: 132, height: 122)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("剩余额度")
    }

    private func quotaDiameter(for quota: QuotaSnapshot) -> CGFloat {
        guard snapshot.visibleQuotas.count > 1 else { return 112 }
        return quota.id == "5h" ? 112 : 86
    }

    private func quotaLineWidth(for quota: QuotaSnapshot) -> CGFloat {
        guard snapshot.visibleQuotas.count > 1 else { return 6 }
        return quota.id == "5h" ? 4.5 : 6.5
    }

    private func quotaCenterLabel(_ quota: QuotaSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(quota.compactTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(quotaColor(for: quota))
            Text("\(quota.remainingPercent)%")
                .font(CodexVistaTheme.metricFont(size: 24))
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(quota.remainingLabel)
    }

    private func quotaOuterLabel(_ quota: QuotaSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(quota.compactTitle)
                .font(.system(size: 10, weight: .semibold))
            Text("\(quota.remainingPercent)%")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(quotaColor(for: quota))
        .padding(.horizontal, 7)
        .background(CodexVistaTheme.dashboardSurfaceStrong)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(quota.remainingLabel)
    }

    private func quotaRing(
        _ quota: QuotaSnapshot,
        diameter: CGFloat,
        lineWidth: CGFloat,
        color: Color
    ) -> some View {
        ZStack {
            Circle()
                .stroke(CodexVistaTheme.dashboardControlBackground, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: quota.remaining)
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.68), color, color.opacity(0.82)],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
        .overlay {
            if CodexVistaTheme.skin == .celadon || CodexVistaTheme.skin == .dusk {
                Circle()
                    .stroke(CodexVistaTheme.dashboardAccent.opacity(0.28), lineWidth: 0.75)
                    .frame(width: diameter + 18, height: diameter + 18)
                    .accessibilityHidden(true)
            } else {
                CodexVistaDialTicks(remaining: quota.remaining)
                    .frame(width: diameter + 20, height: diameter + 20)
            }
        }
    }

    private var quotaResetList: some View {
        VStack(spacing: 0) {
            ForEach(snapshot.visibleQuotas) { quota in
                quotaResetRow(quota, color: quotaColor(for: quota))

                if quota.id != snapshot.visibleQuotas.last?.id {
                    Rectangle()
                        .fill(CodexVistaTheme.dashboardBorder)
                        .frame(height: 1)
                }
            }
        }
        .frame(maxWidth: 200)
    }

    private func quotaResetRow(_ quota: QuotaSnapshot, color: Color) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text("\(quota.compactTitle) 重置")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CodexVistaTheme.dashboardPrimaryText.opacity(0.8))

            Spacer(minLength: 8)

            Text(quota.resetText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(CodexVistaTheme.dashboardPrimaryText.opacity(0.86))
                .monospacedDigit()
        }
        .frame(height: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(quota.compactTitle) 重置 \(quota.resetText)")
    }

    private var selectedPeriod: PeriodUsage? {
        snapshot.periods.first { $0.id == selectedPeriodID } ?? snapshot.periods.first
    }

    private var periodMetricsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 6) {
                ForEach(snapshot.periods) { period in
                    periodSelector(period)
                }
            }

            if let period = selectedPeriod {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(period.title) · Token 构成")
                                .font(CodexVistaTheme.headingFont(size: 14))
                                .lineLimit(1)
                            if period.id == "subscriptionCycle", let cycle = snapshot.subscriptionCycle {
                                Text(subscriptionCycleRangeText(cycle))
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                            }
                        }
                        Spacer(minLength: 0)
                        PeriodModelUsageControl(
                            periodTitle: period.title,
                            periodSubtitle: period.id == "subscriptionCycle"
                                ? snapshot.subscriptionCycle.map(subscriptionCycleRangeText) : nil,
                            ranking: snapshot.modelUsage.ranking(forPeriodID: period.id)
                        )
                    }
                    TokenCompositionView(breakdown: periodTokenBreakdown(period), total: period.total)
                }
                .padding(.horizontal, 12)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func periodSelector(_ period: PeriodUsage) -> some View {
        let isSelected = selectedPeriod?.id == period.id
        return Button {
            selectedPeriodID = period.id
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                Text(period.id == "subscriptionCycle" ? "订阅周期" : period.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? CodexVistaTheme.dashboardAccent : CodexVistaTheme.dashboardMutedText)
                Text(TokenFormatter.compact(period.total))
                    .font(CodexVistaTheme.metricFont(size: 20))
                    .foregroundStyle(CodexVistaTheme.dashboardPrimaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .background(isSelected ? CodexVistaTheme.dashboardControlBackground : Color.clear,
                        in: RoundedRectangle(cornerRadius: CodexVistaTheme.cornerRadius(10)))
            .overlay(alignment: .bottom) {
                if isSelected {
                    Capsule().fill(CodexVistaTheme.dashboardAccent).frame(height: 2)
                        .padding(.horizontal, 10)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("查看\(period.title) Token 构成与模型用量")
        .accessibilityLabel("\(period.title)，总 Token \(period.total.formatted())")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func subscriptionCycleRangeText(_ cycle: SubscriptionCycle) -> String {
        let start = cycle.start.formatted(.dateTime.month().day())
        let end = cycle.end.formatted(.dateTime.month().day())
        return "\(start) – \(end)"
    }

    private func periodTokenBreakdown(_ period: PeriodUsage) -> TokenBreakdown {
        TokenBreakdown(input: period.uncachedInput, cachedInput: period.cachedInput,
                       output: period.visibleOutput, reasoning: period.reasoning)
    }

    private var selectedUsage: [DailyUsage] {
        selectedRange.select(
            from: snapshot.dailyUsage,
            subscriptionCycleUsage: snapshot.subscriptionCycleUsage
        )
    }

    private var availableTrendRanges: [TrendRange] {
        snapshot.subscriptionCycle == nil
            ? [.sevenDays, .thirtyDays]
            : TrendRange.allCases
    }

    private var selectedActivityRanking: ActivityRanking {
        snapshot.activityRankings.ranking(for: selectedActivityRange)
    }

    private var selectedWorkspaceRanking: WorkspaceUsageRanking {
        snapshot.workspaceUsage.ranking(for: selectedProjectRange)
    }

    private var analyticsPanel: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                analyticsTabSelector
                Spacer()
                if selectedAnalyticsTab == .activity {
                    activityRangeSelector
                } else if selectedAnalyticsTab == .project {
                    projectRangeSelector
                }
            }
            .frame(height: 30)

            analyticsContent
        }
        .dashboardPanel(padding: 10)
    }

    private var analyticsContent: some View {
        GeometryReader { geometry in
            Group {
                switch selectedAnalyticsTab {
                case .todayTasks:
                    TodayTaskPanel(ranking: snapshot.workspaceUsage.today)
                case .trend:
                    trendRow
                case .activity:
                    ActivityRankingPanel(ranking: selectedActivityRanking)
                case .project:
                    ProjectUsagePanel(
                        ranking: selectedWorkspaceRanking,
                        range: selectedProjectRange
                    )
                }
            }
            .id(selectedAnalyticsTab)
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .topLeading
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var analyticsTabSelector: some View {
        HStack(spacing: 2) {
            ForEach(DashboardAnalyticsTab.allCases) { tab in
                dashboardSelectorButton(
                    title: tab.rawValue,
                    isSelected: selectedAnalyticsTab == tab,
                    width: tab == .activity ? 102 : 82
                ) {
                    hoveredUsageID = nil
                    selectedAnalyticsTab = tab
                }
            }
        }
        .padding(3)
        .background(
            CodexVistaTheme.dashboardControlBackground,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(CodexVistaTheme.dashboardBorder.opacity(0.72))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("看板内容")
    }

    private var activityRangeSelector: some View {
        analyticsRangeSelector(
            selectedRange: selectedActivityRange,
            accessibilityLabel: "排行榜时间范围"
        ) { selectedActivityRange = $0 }
    }

    private var projectRangeSelector: some View {
        analyticsRangeSelector(
            selectedRange: selectedProjectRange,
            accessibilityLabel: "项目用量时间范围"
        ) { selectedProjectRange = $0 }
    }

    private func analyticsRangeSelector(
        selectedRange: ActivityRange,
        accessibilityLabel: String,
        onSelect: @escaping (ActivityRange) -> Void
    ) -> some View {
        HStack(spacing: 2) {
            ForEach(ActivityRange.allCases) { range in
                dashboardSelectorButton(
                    title: range.rawValue,
                    isSelected: selectedRange == range,
                    width: 48
                ) {
                    onSelect(range)
                }
            }
        }
        .padding(3)
        .background(
            CodexVistaTheme.dashboardControlBackground,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(CodexVistaTheme.dashboardBorder.opacity(0.72))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func dashboardSelectorButton(
        title: String,
        isSelected: Bool,
        width: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? CodexVistaTheme.selectionText : CodexVistaTheme.dashboardMutedText)
                .frame(width: width, height: 24)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(CodexVistaTheme.selectionSurface)
                            .shadow(
                                color: CodexVistaTheme.dashboardShadow,
                                radius: 5,
                                y: 2
                            )
                    }
                }
        }
        .buttonStyle(CodexVistaControlStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectedTotal: Int {
        selectedUsage.reduce(0) { partial, item in
            let (sum, overflow) = partial.addingReportingOverflow(item.total)
            return overflow ? Int.max : sum
        }
    }

    private var selectedAverage: Int {
        guard !selectedUsage.isEmpty else { return 0 }
        return selectedTotal / selectedUsage.count
    }

    private var hoveredUsage: DailyUsage? {
        guard let hoveredUsageID else { return nil }
        return selectedUsage.first { $0.id == hoveredUsageID }
    }

    private var trendUpperBound: Int {
        let maximum = selectedUsage.map(\.total).max() ?? 0
        return max(1, maximum + max(maximum / 5, 1))
    }

    private var trendRow: some View {
        HStack(spacing: 14) {
            UsageCalendarPanel(usage: snapshot.dailyUsage, isEmbedded: true)
                .frame(width: 300)
                .padding(.horizontal, 4)
            trendPanel
        }
    }

    private var trendPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Label("Token 趋势", systemImage: "chart.xyaxis.line")
                    .font(CodexVistaTheme.headingFont(size: 14))

                rangeSelector

                Spacer()

                HStack(spacing: 16) {
                    trendSummary("总计", value: selectedTotal)
                    Rectangle()
                        .fill(CodexVistaTheme.dashboardBorder)
                        .frame(width: 1, height: 24)
                    trendSummary(
                        selectedRange == .subscriptionCycles ? "周期均值" : "日均",
                        value: selectedAverage
                    )
                }
            }

            Chart(selectedUsage) { item in
                AreaMark(
                    x: .value("日期", item.day),
                    y: .value("Token", item.total)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            CodexVistaTheme.dashboardAccent.opacity(0.16),
                            CodexVistaTheme.dashboardAccentSecondary.opacity(0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("日期", item.day),
                    y: .value("Token", item.total)
                )
                .foregroundStyle(CodexVistaTheme.dashboardAccent)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value("日期", item.day),
                    y: .value("Token", item.total)
                )
                .foregroundStyle(CodexVistaTheme.dashboardAccent)
                .symbolSize(24)

                if hoveredUsage?.id == item.id {
                    RuleMark(x: .value("悬停日期", item.day))
                        .foregroundStyle(CodexVistaTheme.dashboardAccent.opacity(0.28))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    PointMark(
                        x: .value("悬停日期", item.day),
                        y: .value("悬停 Token", item.total)
                    )
                    .foregroundStyle(Color.white)
                    .symbolSize(86)

                    PointMark(
                        x: .value("悬停日期", item.day),
                        y: .value("悬停 Token", item.total)
                    )
                    .foregroundStyle(CodexVistaTheme.dashboardAccent)
                    .symbolSize(46)
                    .annotation(
                        position: Double(item.total) / Double(trendUpperBound) > 0.72 ? .bottom : .top,
                        spacing: 8,
                        overflowResolution: .init(
                            x: .fit(to: .chart),
                            y: .disabled
                        )
                    ) {
                        DailyUsageHoverCard(usage: item, dateText: item.day)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(CodexVistaTheme.dashboardGrid)
                    AxisValueLabel {
                        if let tokens = value.as(Int.self) {
                            Text(TokenFormatter.compact(tokens))
                                .font(.system(size: 10))
                                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisTick().foregroundStyle(CodexVistaTheme.dashboardGrid)
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                }
            }
            .chartXAxis(selectedRange.showsXAxis ? .visible : .hidden)
            .chartYScale(domain: 0...trendUpperBound)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(CodexVistaTheme.dashboardPrimaryText.opacity(0.001))
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                updateHoveredUsage(
                                    at: location,
                                    proxy: proxy,
                                    geometry: geometry
                                )
                            case .ended:
                                hoveredUsageID = nil
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 10)
        }
    }

    private var rangeSelector: some View {
        HStack(spacing: 2) {
            ForEach(availableTrendRanges) { range in
                Button {
                    hoveredUsageID = nil
                    selectedRange = range
                } label: {
                    Text(range.rawValue)
                        .font(.system(size: 11, weight: selectedRange == range ? .semibold : .medium))
                        .foregroundStyle(
                            selectedRange == range ? CodexVistaTheme.selectionText : CodexVistaTheme.dashboardMutedText
                        )
                        .frame(width: 54, height: 26)
                        .background {
                            if selectedRange == range {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(CodexVistaTheme.selectionSurface)
                                    .shadow(color: CodexVistaTheme.dashboardShadow, radius: 5, y: 2)
                            }
                        }
                }
                .buttonStyle(CodexVistaControlStyle())
                .accessibilityAddTraits(selectedRange == range ? .isSelected : [])
            }
        }
        .padding(3)
        .background(
            CodexVistaTheme.dashboardControlBackground,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(CodexVistaTheme.dashboardBorder.opacity(0.72))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("趋势时间范围")
    }

    private func updateHoveredUsage(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        guard let plotFrame = proxy.plotFrame else {
            hoveredUsageID = nil
            return
        }

        let frame = geometry[plotFrame]
        guard frame.contains(location) else {
            hoveredUsageID = nil
            return
        }

        let plotX = location.x - frame.minX
        hoveredUsageID = selectedUsage.compactMap { item -> (id: DailyUsage.ID, distance: CGFloat)? in
            guard let itemX = proxy.position(forX: item.day) else { return nil }
            return (item.id, abs(itemX - plotX))
        }
        .min { $0.distance < $1.distance }?
        .id
    }

    private func trendSummary(_ title: String, value: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            Text(TokenFormatter.compact(value))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(CodexVistaTheme.dashboardAccent)
                .monospacedDigit()
        }
    }
}

enum DashboardAnalyticsTab: String, CaseIterable, Identifiable {
    case todayTasks = "今日任务"
    case trend = "用量趋势"
    case activity = "Skills / Tools"
    case project = "项目用量"

    static let defaultTab: DashboardAnalyticsTab = .todayTasks

    var id: Self { self }
}
