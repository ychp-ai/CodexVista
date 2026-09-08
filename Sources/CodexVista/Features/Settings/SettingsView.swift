import SwiftUI

struct CodexPlan: Identifiable, Sendable {
    let name: String
    let summary: String
    let symbol: String
    let isPaid: Bool

    var id: String { name }
}

enum CodexPlanCatalog {
    static let plans: [CodexPlan] = [
        .init(
            name: "Free",
            summary: "适合体验 Codex 和处理简短编码任务",
            symbol: "sparkles",
            isPaid: false
        ),
        .init(
            name: "Go",
            summary: "适合轻量、日常的编码任务",
            symbol: "figure.walk.motion",
            isPaid: true
        ),
        .init(
            name: "Plus",
            summary: "适合每周进行几次专注的编码工作",
            symbol: "plus.circle.fill",
            isPaid: true
        ),
        .init(
            name: "Pro 5x",
            summary: "标准使用额度为 Plus 的 5 倍",
            symbol: "bolt.fill",
            isPaid: true
        ),
        .init(
            name: "Pro 20x",
            summary: "最高用量档位，标准使用额度为 Plus 的 20 倍",
            symbol: "bolt.horizontal.circle.fill",
            isPaid: true
        ),
        .init(
            name: "Business",
            summary: "面向团队，包含项目和基础管理能力",
            symbol: "person.2.fill",
            isPaid: true
        ),
        .init(
            name: "Enterprise / Edu",
            summary: "面向组织和教育机构，提供企业级控制能力",
            symbol: "building.2.fill",
            isPaid: true
        )
    ]

    static func isCurrent(_ plan: CodexPlan, currentPlanName: String?) -> Bool {
        plan.name.caseInsensitiveCompare(currentPlanName ?? "Free") == .orderedSame
    }
}

struct SettingsView: View {
    private enum Layout {
        static let labelWidth: CGFloat = 205
        static let controlWidth: CGFloat = 248
        static let columnSpacing: CGFloat = 20
        static let rowHeight: CGFloat = 56
        static let cardHorizontalPadding: CGFloat = 16
        static let planBadgeWidth: CGFloat = 52
    }

    let store: DashboardStore
    let reminderController: UsageReminderController
    let updateService: AppUpdateService
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppPreferenceKeys.skin)
    private var skinRaw = AppSkinPreference.standard.rawValue
    @AppStorage(AppPreferenceKeys.colorScheme)
    private var colorSchemeRaw = AppColorSchemePreference.system.rawValue
    @AppStorage(AppPreferenceKeys.keepsDashboardOnTop) private var keepsDashboardOnTop = false
    @AppStorage(AppPreferenceKeys.dashboardCloseBehavior)
    private var dashboardCloseBehaviorRaw = DashboardCloseBehavior.closeDashboard.rawValue
    @AppStorage(AppPreferenceKeys.automaticRefreshEnabled) private var automaticRefreshEnabled = true
    @AppStorage(AppPreferenceKeys.usageRemindersEnabled) private var usageRemindersEnabled = false
    @AppStorage(AppPreferenceKeys.remindsAtTwentyPercent) private var remindsAtTwentyPercent = true
    @AppStorage(AppPreferenceKeys.remindsAtTenPercent) private var remindsAtTenPercent = true
    @AppStorage(AppPreferenceKeys.remindsAtFivePercent) private var remindsAtFivePercent = true
    @AppStorage(AppPreferenceKeys.showsLivePreview) private var showsLivePreview = true
    @AppStorage(AppPreferenceKeys.summaryPlacement) private var summaryPlacementRaw = SummaryPlacementPreference.menuBar.rawValue
    @AppStorage(AppPreferenceKeys.showsResetCountdown) private var showsResetCountdown = true
    @AppStorage(AppPreferenceKeys.quotaDisplay) private var quotaDisplayRaw = QuotaDisplayPreference.remaining.rawValue
    @AppStorage(AppPreferenceKeys.firstSubscriptionDate)
    private var firstSubscriptionTimestamp = 0.0
    @FocusState private var subscriptionDateIsFocused: Bool
    @State private var isEditingSubscriptionDate = false
    @State private var showsRebuildConfirmation = false
    @State private var showsModelPricingExplanation = false

    var body: some View {
        ScrollView {
            CodexVistaGlassGroup(spacing: 24) {
                VStack(alignment: .leading, spacing: 24) {
                    settingsHeader
                    appearanceSettings
                    dashboardSettings
                    statusBarSettings
                    usageReminderSettings
                    dataAndRefreshSettings
                    softwareUpdateSettings
                    planAndBillingSettings
                    privacyNotice
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.automatic)
        .frame(width: 640, height: 700)
        .background { CodexVistaBackdrop() }
        .task {
            await store.start()
            await reminderController.refreshAuthorizationStatus()
        }
        .onAppear {
            finishEditingSubscriptionDate()
        }
        .onDisappear {
            finishEditingSubscriptionDate()
        }
        .alert("清空并重新抓取所有数据？", isPresented: $showsRebuildConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空并重新抓取", role: .destructive) {
                Task { await store.rebuildFromLocalData() }
            }
        } message: {
            Text("这会清空 CodexVista 已抓取的用量、额度、会话和 Skills / Tools 统计，然后从本机 Codex 数据全量重新抓取。不会删除 Codex 原始数据。")
        }
    }

    private var appearanceSettings: some View {
        settingsSection("外观") {
            VStack(spacing: 0) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(AppSkinPreference.allCases) { skin in
                        CodexVistaSkinPreview(
                            skin: skin,
                            isSelected: AppSkinPreference.resolved(from: skinRaw) == skin
                        ) { skinRaw = skin.rawValue }
                    }
                }
                .padding(.vertical, 14)
                settingsDivider
                preferenceRow("色系", detail: appearanceDetail) {
                    if let fixedScheme = selectedSkin.fixedColorScheme {
                        Label(fixedScheme == .light ? "浅色" : "深色", systemImage: fixedScheme == .light ? "sun.max" : "moon")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(CodexVistaTheme.selectionText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(CodexVistaTheme.selectionSurface, in: RoundedRectangle(cornerRadius: 7))
                            .accessibilityLabel(appearanceDetail)
                    } else {
                        segmentedGroup {
                            selectionSegment(
                                "跟随系统",
                                isSelected: colorSchemePreference == .system
                            ) {
                                colorSchemeRaw = AppColorSchemePreference.system.rawValue
                            }
                            selectionSegment(
                                "浅色",
                                isSelected: colorSchemePreference == .light
                            ) {
                                colorSchemeRaw = AppColorSchemePreference.light.rawValue
                            }
                            selectionSegment(
                                "深色",
                                isSelected: colorSchemePreference == .dark
                            ) {
                                colorSchemeRaw = AppColorSchemePreference.dark.rawValue
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Layout.cardHorizontalPadding)
            .settingsCard()
        }
    }

    private var colorSchemePreference: AppColorSchemePreference {
        AppColorSchemePreference.resolved(from: colorSchemeRaw)
    }

    private var selectedSkin: AppSkinPreference {
        AppSkinPreference.resolved(from: skinRaw)
    }

    private var appearanceDetail: String {
        if let fixedScheme = selectedSkin.fixedColorScheme {
            return "\(selectedSkin.title)皮肤仅支持\(fixedScheme == .light ? "浅色" : "深色")"
        }
        if selectedSkin != .standard {
            return colorSchemePreference == .system ? "\(selectedSkin.title)明暗自动跟随 macOS" : selectedSkin.detail
        }
        return switch colorSchemePreference {
        case .system: "自动跟随 macOS 外观设置"
        case .light: "铝灰底色，钴蓝与精密刻度"
        case .dark: "深钢蓝底色，清晰分层"
        }
    }

    private var settingsHeader: some View {
        HStack(spacing: 12) {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(.white)
                .padding(8)
                .background(CodexVistaTheme.brandGradient, in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("CodexVista 设置")
                    .font(.title3.weight(.semibold))
                Text("管理看板、状态栏、本地数据和提醒方式")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var dashboardSettings: some View {
        settingsSection("看板") {
            VStack(spacing: 0) {
                preferenceRow("置顶显示", detail: "让看板始终显示在其他普通窗口上方") {
                    Toggle("", isOn: $keepsDashboardOnTop)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                settingsDivider
                preferenceRow("关闭按钮", detail: dashboardCloseBehaviorDetail) {
                    segmentedGroup {
                        selectionSegment(
                            "仅关闭看板",
                            isSelected: dashboardCloseBehavior == .closeDashboard
                        ) {
                            dashboardCloseBehaviorRaw = DashboardCloseBehavior
                                .closeDashboard.rawValue
                        }
                        selectionSegment(
                            "退出程序",
                            isSelected: dashboardCloseBehavior == .quitApplication
                        ) {
                            dashboardCloseBehaviorRaw = DashboardCloseBehavior
                                .quitApplication.rawValue
                        }
                    }
                }
            }
            .padding(.horizontal, Layout.cardHorizontalPadding)
            .settingsCard()
        }
    }

    private var dashboardCloseBehavior: DashboardCloseBehavior {
        DashboardCloseBehavior.resolved(from: dashboardCloseBehaviorRaw)
    }

    private var dashboardCloseBehaviorDetail: String {
        switch dashboardCloseBehavior {
        case .closeDashboard:
            "关闭后仍可从状态栏再次打开看板"
        case .quitApplication:
            "点击看板关闭按钮时退出 CodexVista"
        }
    }

    private var statusBarSettings: some View {
        settingsSection("状态栏与刘海") {
            VStack(spacing: 0) {
                preferenceRow("展示位置", detail: "无刘海屏幕自动使用状态栏") {
                    segmentedGroup {
                        selectionSegment("状态栏", isSelected: summaryPlacementRaw == SummaryPlacementPreference.menuBar.rawValue) {
                            summaryPlacementRaw = SummaryPlacementPreference.menuBar.rawValue
                        }
                        selectionSegment("刘海下方", isSelected: summaryPlacementRaw == SummaryPlacementPreference.notch.rawValue) {
                            summaryPlacementRaw = SummaryPlacementPreference.notch.rawValue
                        }
                    }
                }
                settingsDivider
                preferenceRow("实时预览", detail: "显示额度摘要，关闭后仅保留图标") {
                    Toggle("", isOn: $showsLivePreview)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                VStack(spacing: 0) {
                    settingsDivider
                    preferenceRow("预览效果", detail: "与所选位置使用同一绘制样式") {
                        if summaryPlacementRaw == SummaryPlacementPreference.notch.rawValue {
                            NotchSummaryView(
                                presentation: statusItemPresentation,
                                quotaDisplay: QuotaDisplayPreference(rawValue: quotaDisplayRaw) ?? .remaining,
                                theme: StatusItemTheme.resolve(appearance: previewAppearance)
                            )
                            .allowsHitTesting(false)
                        } else {
                            Image(nsImage: StatusItemRenderer(theme: .resolve(appearance: previewAppearance)).render(
                                statusItemPresentation,
                                appearance: previewAppearance
                            ))
                            .interpolation(.high)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                            .accessibilityLabel("CodexVista 状态栏预览")
                            .accessibilityValue(statusItemPresentation.label)
                        }
                    }
                    settingsDivider

                    preferenceRow("额度口径", detail: "选择摘要百分比的统计方式") {
                        segmentedGroup {
                            selectionSegment(
                                "已用量",
                                isSelected: quotaDisplayRaw == QuotaDisplayPreference.used.rawValue
                            ) {
                                quotaDisplayRaw = QuotaDisplayPreference.used.rawValue
                            }
                            selectionSegment(
                                "剩余量",
                                isSelected: quotaDisplayRaw == QuotaDisplayPreference.remaining.rawValue
                            ) {
                                quotaDisplayRaw = QuotaDisplayPreference.remaining.rawValue
                            }
                        }
                    }
                    settingsDivider

                    preferenceRow("重置倒计时", detail: "控制摘要及悬浮提示中的倒计时") {
                        Toggle("", isOn: $showsResetCountdown)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
                .disabled(!showsLivePreview)
                .opacity(showsLivePreview ? 1 : 0.45)
            }
            .padding(.horizontal, Layout.cardHorizontalPadding)
            .settingsCard()
        }
    }

    private var usageReminderSettings: some View {
        settingsSection("用量提醒") {
            VStack(spacing: 0) {
                preferenceRow("用量提醒", detail: "额度较低时发送 macOS 系统通知") {
                    Toggle("", isOn: usageRemindersEnabledBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                VStack(spacing: 0) {
                    settingsDivider
                    preferenceRow("预警等级", detail: "剩余额度达到阈值时提醒") {
                        segmentedGroup {
                            multiSelectSegment("20%", isOn: reminderTwentyBinding)
                            multiSelectSegment("10%", isOn: reminderTenBinding)
                            multiSelectSegment("5%", isOn: reminderFiveBinding)
                        }
                    }
                    settingsDivider
                    preferenceRow("提醒规则", detail: "避免同一额度周期重复打扰") {
                        Text("每档每周期一次")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!usageRemindersEnabled)
                .opacity(usageRemindersEnabled ? 1 : 0.45)

                settingsDivider
                preferenceRow("通知权限", detail: notificationPermissionDetail) {
                    notificationPermissionControl
                }
            }
            .padding(.horizontal, Layout.cardHorizontalPadding)
            .settingsCard()
        }
    }

    @ViewBuilder
    private var notificationPermissionControl: some View {
        switch reminderController.authorizationStatus {
        case .notDetermined:
            Label("开启后请求", systemImage: "bell")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        case .authorized:
            Label("已允许", systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.green)
        case .denied:
            HStack(spacing: 8) {
                Label("未授权", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)
                Button("系统设置") {
                    reminderController.openNotificationSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var notificationPermissionDetail: String {
        switch reminderController.authorizationStatus {
        case .notDetermined: "首次开启提醒时申请系统权限"
        case .authorized: "系统通知可以正常发送"
        case .denied: "请在系统设置中允许 CodexVista 通知"
        }
    }

    private var dataAndRefreshSettings: some View {
        settingsSection("数据与刷新") {
            VStack(spacing: 0) {
                healthRow(
                    "Codex CLI",
                    detail: "命令行会话与用量数据",
                    health: store.sourceSummary?.cli
                )
                settingsDivider
                healthRow(
                    "Codex macOS",
                    detail: "桌面端会话与用量数据",
                    health: store.sourceSummary?.desktop
                )
                settingsDivider
                healthRow(
                    "线程索引",
                    detail: "本地线程状态与归档信息",
                    health: store.sourceSummary?.index
                )
                settingsDivider
                preferenceRow("最近成功刷新", detail: "最近一次成功读取本机数据的时间") {
                    Text(lastRefreshText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                settingsDivider
                preferenceRow(
                    "自动刷新",
                    detail: automaticRefreshEnabled
                        ? "每 60 秒读取本机 Codex 用量与额度"
                        : "已关闭，仍可启动时读取或手动刷新"
                ) {
                    HStack(spacing: 10) {
                        Text(automaticRefreshEnabled ? "用量 60 秒" : "已关闭")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Toggle("", isOn: automaticRefreshBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
                settingsDivider
                settingsRow {
                    settingLabel("手动刷新", detail: "立即重新读取本机 Codex 数据")
                } control: {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        if store.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("立即刷新", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isRefreshing || store.isRebuildingData)
                }
                settingsDivider
                settingsRow {
                    settingLabel("重建本地数据", detail: "清空统计与检查点后全量重新抓取")
                } control: {
                    Button(role: .destructive) {
                        showsRebuildConfirmation = true
                    } label: {
                        if store.isRebuildingData {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("正在重新抓取")
                            }
                        } else {
                            Label("清空并重抓", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isRefreshing || store.isRebuildingData)
                }
                if store.isRebuildingData, let progress = store.rebuildProgress {
                    rebuildProgressView(progress)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, Layout.cardHorizontalPadding)
            .settingsCard()
            .animation(.easeOut(duration: 0.16), value: store.isRebuildingData)
        }
    }

    private func rebuildProgressView(_ progress: CodexImportProgress) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(rebuildProgressTitle(progress))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    if let total = progress.totalFileCount {
                        Text("\(progress.completedFileCount) / \(total) 个文件")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Group {
                    if let fraction = progress.fractionCompleted {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView()
                    }
                }
                .progressViewStyle(.linear)
            }
            .frame(width: Layout.controlWidth)
        }
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("本地数据重建进度")
        .accessibilityValue(rebuildProgressAccessibilityValue(progress))
    }

    private func rebuildProgressTitle(_ progress: CodexImportProgress) -> String {
        switch progress.stage {
        case .resetting: "正在清空旧统计"
        case .discovering: "正在扫描 Codex 数据"
        case .importing:
            progress.totalFileCount == 0 ? "未发现可抓取文件" : "正在抓取本地记录"
        case .finalizing: "正在生成统计结果"
        }
    }

    private func rebuildProgressAccessibilityValue(_ progress: CodexImportProgress) -> String {
        guard let total = progress.totalFileCount else {
            return rebuildProgressTitle(progress)
        }
        let percentage = Int(((progress.fractionCompleted ?? 0) * 100).rounded())
        return "\(rebuildProgressTitle(progress))，已处理 \(progress.completedFileCount) / \(total) 个文件，\(percentage)%"
    }

    private var planAndBillingSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSection("订阅周期") {
                VStack(spacing: 0) {
                    preferenceRow(
                        "第一次订阅时间",
                        detail: subscriptionCycleDetail
                    ) {
                        subscriptionDateControl
                    }
                }
                .padding(.horizontal, Layout.cardHorizontalPadding)
                .settingsCard()
            }

            settingsSection("Codex 套餐") {
                VStack(spacing: 0) {
                    ForEach(CodexPlanCatalog.plans) { plan in
                        planRow(plan)
                            .padding(.horizontal, Layout.cardHorizontalPadding)
                            .background {
                                if isCurrent(plan) {
                                    RoundedRectangle(cornerRadius: currentPlanCornerRadius, style: .continuous)
                                        .fill(CodexVistaTheme.isInk
                                            ? CodexVistaTheme.dashboardTile
                                            : CodexVistaTheme.dashboardAccent.opacity(0.08))
                                        .overlay {
                                            if CodexVistaTheme.isInk {
                                                CodexVistaPaperGrain()
                                                    .clipShape(RoundedRectangle(cornerRadius: currentPlanCornerRadius))
                                            }
                                        }
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                }
                            }
                            .overlay {
                                if isCurrent(plan) {
                                    RoundedRectangle(cornerRadius: currentPlanCornerRadius, style: .continuous)
                                        .stroke(currentPlanAccent.opacity(CodexVistaTheme.isInk ? 0.4 : 0.22), lineWidth: 1)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                }
                            }

                        if plan.id != CodexPlanCatalog.plans.last?.id {
                            settingsDivider
                                .padding(.horizontal, Layout.cardHorizontalPadding)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .settingsCard()
            }

            settingsSection("其他计费方式") {
                VStack(spacing: 0) {
                    settingsRow {
                        settingLabel("API Key", detail: "独立按量计费，不属于 ChatGPT 订阅套餐")
                    } control: {
                        Text("按 Token 用量计费")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, Layout.cardHorizontalPadding)

                    settingsDivider
                        .padding(.horizontal, Layout.cardHorizontalPadding)

                    settingsRow {
                        settingLabel(
                            "模型费用说明",
                            detail: "已收录模型按公开价，其他模型按 GPT-5.5 参考价"
                        )
                    } control: {
                        Button("查看说明") {
                            showsModelPricingExplanation.toggle()
                        }
                        .buttonStyle(.bordered)
                        .popover(
                            isPresented: $showsModelPricingExplanation,
                            attachmentAnchor: .rect(.bounds),
                            arrowEdge: .trailing
                        ) {
                            ModelPricingExplanationView()
                                .padding(4)
                        }
                    }
                    .padding(.horizontal, Layout.cardHorizontalPadding)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .settingsCard()
            }
        }
    }

    @ViewBuilder
    private var subscriptionDateControl: some View {
        if let firstSubscriptionDate {
            if isEditingSubscriptionDate {
                subscriptionDateEditor
            } else {
                subscriptionDateSummary(firstSubscriptionDate)
            }
        } else {
            Button("设置时间") {
                updateFirstSubscriptionDate(.now)
                beginEditingSubscriptionDate()
            }
            .buttonStyle(.bordered)
        }
    }

    private var subscriptionDateEditor: some View {
        HStack(spacing: 8) {
            DatePicker(
                "第一次订阅时间",
                selection: firstSubscriptionDateBinding,
                in: Date.distantPast...Date.now,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .frame(width: 200)
            .focused($subscriptionDateIsFocused)
            .onSubmit {
                finishEditingSubscriptionDate()
            }

            Button {
                finishEditingSubscriptionDate()
            } label: {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel("完成设置第一次订阅时间")
            .help("完成编辑")
        }
    }

    private func subscriptionDateSummary(_ date: Date) -> some View {
        HStack(spacing: 8) {
            Text(subscriptionDateText(date))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Button {
                beginEditingSubscriptionDate()
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("编辑第一次订阅时间")
            .help("编辑第一次订阅时间")

            Button {
                finishEditingSubscriptionDate()
                updateFirstSubscriptionDate(nil)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel("清除第一次订阅时间")
            .help("清除第一次订阅时间")
        }
    }

    private func beginEditingSubscriptionDate() {
        isEditingSubscriptionDate = true
        Task { @MainActor in
            await Task.yield()
            subscriptionDateIsFocused = true
        }
    }

    private func finishEditingSubscriptionDate() {
        subscriptionDateIsFocused = false
        isEditingSubscriptionDate = false
    }

    private var firstSubscriptionDate: Date? {
        guard firstSubscriptionTimestamp.isFinite, firstSubscriptionTimestamp > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: firstSubscriptionTimestamp)
    }

    private var firstSubscriptionDateBinding: Binding<Date> {
        Binding(
            get: { firstSubscriptionDate ?? .now },
            set: { updateFirstSubscriptionDate($0) }
        )
    }

    private var subscriptionCycleDetail: String {
        guard let firstSubscriptionDate else {
            return "设置后按该时刻逐月汇总 Token 用量"
        }
        guard let cycle = SubscriptionCycleCalculator.cycle(
            containing: .now,
            firstSubscribedAt: firstSubscriptionDate,
            calendar: .current
        ) else {
            return "第一次订阅时间不能晚于当前时间"
        }
        return "本周期：\(subscriptionDateText(cycle.start)) 至 \(subscriptionDateText(cycle.end))"
    }

    private func subscriptionDateText(_ date: Date) -> String {
        date.formatted(date: .numeric, time: .shortened)
    }

    private func updateFirstSubscriptionDate(_ date: Date?) {
        let calendar = Calendar.current
        let normalizedDate = date.flatMap {
            calendar.date(from: calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: $0
            ))
        }
        firstSubscriptionTimestamp = normalizedDate?.timeIntervalSince1970 ?? 0
        Task { await store.subscriptionPreferenceDidChange() }
    }

    private var softwareUpdateSettings: some View {
        settingsSection("软件更新") {
            VStack(spacing: 0) {
                preferenceRow("当前版本", detail: updateStatusDetail) {
                    Label(updateStatusText, systemImage: updateStatusSymbol)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(updateStatusColor)
                }
                settingsDivider
                preferenceRow("自动检查更新", detail: "启动后自动检查 GitHub 最新正式版") {
                    Toggle("", isOn: automaticallyChecksForUpdatesBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                settingsDivider
                preferenceRow("自动下载更新", detail: "发现新版本后在后台下载并校验 DMG") {
                    Toggle("", isOn: automaticallyDownloadsUpdatesBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!updateService.automaticallyChecksForUpdates)
                }
                settingsDivider
                settingsRow {
                    settingLabel("手动更新", detail: "立即检查，或前往 Releases 自行下载")
                } control: {
                    HStack(spacing: 8) {
                        Button("手动下载") {
                            updateService.openReleasePage()
                        }
                        .buttonStyle(.bordered)

                        updateActionButton
                    }
                }
            }
            .padding(.horizontal, Layout.cardHorizontalPadding)
            .settingsCard()
        }
    }

    @ViewBuilder
    private var updateActionButton: some View {
        switch updateService.state {
        case .checking:
            Button(action: {}) {
                ProgressView()
                    .controlSize(.small)
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
        case .available:
            Button("下载更新") {
                Task { await updateService.updateNow() }
            }
            .buttonStyle(.borderedProminent)
        case .downloading:
            Button(action: {}) {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("下载中")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
        case .ready:
            Button("打开安装包") {
                Task { await updateService.updateNow() }
            }
            .buttonStyle(.borderedProminent)
        case .idle, .upToDate, .failed:
            Button("检查更新") {
                Task { await updateService.checkForUpdates() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var automaticallyChecksForUpdatesBinding: Binding<Bool> {
        Binding(
            get: { updateService.automaticallyChecksForUpdates },
            set: { updateService.setAutomaticallyChecksForUpdates($0) }
        )
    }

    private var automaticallyDownloadsUpdatesBinding: Binding<Bool> {
        Binding(
            get: { updateService.automaticallyDownloadsUpdates },
            set: { updateService.setAutomaticallyDownloadsUpdates($0) }
        )
    }

    private var updateStatusText: String {
        switch updateService.state {
        case .idle: "v\(updateService.currentVersion)"
        case .checking: "正在检查"
        case .upToDate: "v\(updateService.currentVersion) · 最新"
        case .available(let release): "v\(release.version) 可用"
        case .downloading(let release): "正在下载 v\(release.version)"
        case .ready(let release, _): "v\(release.version) 已下载"
        case .failed: "检查失败"
        }
    }

    private var updateStatusDetail: String {
        switch updateService.state {
        case .idle: "尚未检查更新"
        case .checking: "正在连接 GitHub Releases"
        case .upToDate(let checkedAt): "最近检查：\(checkedAt.formatted(date: .omitted, time: .shortened))"
        case .available: "可自动下载更新，或前往 Releases 手动下载"
        case .downloading: "下载完成后会校验安装包完整性"
        case .ready: "打开 DMG 后将 CodexVista 拖入“应用程序”"
        case .failed(let message): message
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
        case .available, .ready: Color.accentColor
        case .failed: .orange
        case .upToDate: .green
        case .idle, .checking, .downloading: .secondary
        }
    }

    private var automaticRefreshBinding: Binding<Bool> {
        Binding(
            get: { automaticRefreshEnabled },
            set: { isEnabled in
                automaticRefreshEnabled = isEnabled
                store.setAutomaticRefreshEnabled(isEnabled)
            }
        )
    }

    private var privacyNotice: some View {
        Label {
            Text("CodexVista 只读取本机 Codex 的安全统计字段，并将聚合数据保存在应用支持目录中。")
        } icon: {
            Image(systemName: "lock.shield")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private var currentPlanAccent: Color {
        CodexVistaTheme.isInk ? CodexVistaTheme.cinnabar : CodexVistaTheme.dashboardAccent
    }

    private var currentPlanCornerRadius: CGFloat {
        CodexVistaTheme.isInk ? 4 : 7
    }

    private func planRow(_ plan: CodexPlan) -> some View {
        HStack(spacing: 12) {
            Image(systemName: plan.symbol)
                .font(.title3)
                .foregroundStyle(isCurrent(plan) ? currentPlanAccent : CodexVistaTheme.dashboardMutedText)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(plan.name)
                        .font(CodexVistaTheme.isInk ? CodexVistaTheme.headingFont(size: 14) : .body)
                        .fontWeight(isCurrent(plan) ? .semibold : .regular)
                        .foregroundStyle(CodexVistaTheme.dashboardPrimaryText)

                    if isCurrent(plan) {
                        Label("当前套餐", systemImage: "checkmark.circle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(currentPlanAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                currentPlanAccent.opacity(CodexVistaTheme.isInk ? 0.06 : 0.12),
                                in: RoundedRectangle(cornerRadius: CodexVistaTheme.isInk ? 3 : 20)
                            )
                            .overlay {
                                if CodexVistaTheme.isInk {
                                    RoundedRectangle(cornerRadius: 3)
                                        .strokeBorder(currentPlanAccent.opacity(0.35), lineWidth: 0.5)
                                }
                            }
                    }
                }

                Text(plan.summary)
                    .font(.caption)
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            }

            Spacer(minLength: 16)

            HStack(spacing: 6) {
                if plan.isPaid {
                    Text("付费")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(CodexVistaTheme.dashboardControlBackground, in: Capsule())
                }
            }
            .frame(width: Layout.planBadgeWidth, alignment: .trailing)
        }
        .frame(minHeight: Layout.rowHeight)
    }

    private func isCurrent(_ plan: CodexPlan) -> Bool {
        CodexPlanCatalog.isCurrent(plan, currentPlanName: store.snapshot?.planName)
    }

    private var menuBarConfiguration: MenuBarLabelConfiguration {
        MenuBarLabelConfiguration(
            showsLivePreview: showsLivePreview,
            quotaDisplay: QuotaDisplayPreference(rawValue: quotaDisplayRaw) ?? .remaining,
            showsFiveHour: false,
            showsWeekly: true,
            showsResetCountdown: showsResetCountdown
        )
    }

    private var statusItemPresentation: StatusItemPresentation {
        StatusItemPresentation(
            snapshot: store.snapshot,
            configuration: menuBarConfiguration
        )
    }

    private var previewAppearance: NSAppearance {
        NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)!
    }

    private var usageRemindersEnabledBinding: Binding<Bool> {
        Binding(
            get: { usageRemindersEnabled },
            set: { isEnabled in
                usageRemindersEnabled = isEnabled
                reminderController.configurationDidChange(
                    requestAuthorizationIfNeeded: isEnabled
                )
            }
        )
    }

    private var reminderTwentyBinding: Binding<Bool> {
        Binding(
            get: { remindsAtTwentyPercent },
            set: { isSelected in
                guard isSelected || remindsAtTenPercent || remindsAtFivePercent else { return }
                remindsAtTwentyPercent = isSelected
                reminderController.configurationDidChange()
            }
        )
    }

    private var reminderTenBinding: Binding<Bool> {
        Binding(
            get: { remindsAtTenPercent },
            set: { isSelected in
                guard isSelected || remindsAtTwentyPercent || remindsAtFivePercent else { return }
                remindsAtTenPercent = isSelected
                reminderController.configurationDidChange()
            }
        )
    }

    private var reminderFiveBinding: Binding<Bool> {
        Binding(
            get: { remindsAtFivePercent },
            set: { isSelected in
                guard isSelected || remindsAtTwentyPercent || remindsAtTenPercent else { return }
                remindsAtFivePercent = isSelected
                reminderController.configurationDidChange()
            }
        )
    }

    private func settingLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func preferenceRow<Control: View>(
        _ title: String,
        detail: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        settingsRow {
            settingLabel(title, detail: detail)
        } control: {
            control()
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: settingsSectionIcon(for: title))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.leading, 4)

            content()
        }
    }

    private func settingsSectionIcon(for title: String) -> String {
        switch title {
        case "外观": "circle.lefthalf.filled"
        case "看板": "rectangle.3.group"
        case "状态栏": "menubar.rectangle"
        case "用量提醒": "bell.badge"
        case "数据与刷新": "externaldrive.badge.timemachine"
        case "软件更新": "arrow.triangle.2.circlepath"
        case "订阅周期": "calendar.badge.clock"
        case "Codex 套餐": "creditcard"
        case "其他计费方式": "dollarsign.circle"
        default: "gearshape"
        }
    }

    private var settingsDivider: some View {
        Divider()
            .accessibilityHidden(true)
    }

    private func segmentedGroup<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 2) {
            content()
        }
        .padding(2)
        .background(CodexVistaTheme.dashboardControlBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func selectionSegment(
        _ title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .frame(maxWidth: .infinity, minHeight: 20)
                .foregroundStyle(isSelected ? CodexVistaTheme.selectionText : CodexVistaTheme.dashboardMutedText)
                .contentShape(Rectangle())
        }
        .buttonStyle(CodexVistaControlStyle())
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isSelected ? CodexVistaTheme.selectionSurface : Color.clear)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func multiSelectSegment(_ title: String, isOn: Binding<Bool>) -> some View {
        selectionSegment(title, isSelected: isOn.wrappedValue) {
            isOn.wrappedValue.toggle()
        }
    }

    private func settingsRow<Leading: View, Control: View>(
        @ViewBuilder label: () -> Leading,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: Layout.columnSpacing) {
            label()
                .frame(width: Layout.labelWidth, alignment: .leading)

            Spacer(minLength: 0)

            control()
                .frame(width: Layout.controlWidth, alignment: .trailing)
        }
        .frame(minHeight: Layout.rowHeight)
    }

    private func healthRow(_ title: String, detail: String, health: SourceHealth?) -> some View {
        settingsRow {
            settingLabel(title, detail: detail)
        } control: {
            Label(healthText(health), systemImage: healthSymbol(health))
                .font(.callout.weight(.medium))
                .foregroundStyle(healthColor(health))
        }
    }

    private var lastRefreshText: String {
        guard let date = store.sourceSummary?.lastSuccessfulRefresh else { return "尚未成功刷新" }
        return date.formatted(date: .abbreviated, time: .standard)
    }

    private func healthText(_ health: SourceHealth?) -> String {
        switch health {
        case .connected: "已连接"
        case .missing: "未检测到"
        case .degraded: "部分不可用"
        case .unsupported: "格式不兼容"
        case nil: "正在检测"
        }
    }

    private func healthSymbol(_ health: SourceHealth?) -> String {
        switch health {
        case .connected: "checkmark.circle.fill"
        case .missing, nil: "minus.circle"
        case .degraded: "exclamationmark.triangle.fill"
        case .unsupported: "xmark.octagon.fill"
        }
    }

    private func healthColor(_ health: SourceHealth?) -> Color {
        switch health {
        case .connected: .green
        case .missing, nil: .secondary
        case .degraded: .orange
        case .unsupported: .red
        }
    }
}

private struct ModelPricingExplanationView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("模型费用说明")
                    .font(.headline)
                Text("标准 API 价格 · 每 100 万 Token")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("最近价格核对：\(ModelPricingCatalog.lastVerifiedDate)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                pricingHeader
                Divider()
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(ModelPricingCatalog.listedModelIDs, id: \.self) { modelID in
                            if let rule = ModelPricingCatalog.rule(for: modelID) {
                                pricingRow(modelID, rule: rule)
                            }
                            if modelID != ModelPricingCatalog.listedModelIDs.last {
                                Divider()
                            }
                        }
                    }
                }
                .frame(height: min(CGFloat(ModelPricingCatalog.listedModelIDs.count * 33), 264))
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text("费用按未缓存输入、缓存输入、可见输出和推理输出分别估算，推理 Token 按输出价格计算。")
                Text("GPT-6 Astra 使用独立公开价格，历史用量也按当前单价重新估算。")
                Text("Spark 暂无公开 API 定价，表中 ≈ 为 GPT-5.5 参考价；codex-auto-review 等未收录独立价格的模型也按此估算。")
                Text("gpt-5.6 是 gpt-5.6-sol 的别名，使用相同价格。")
                Text("未计入长上下文、缓存写入、快速模式和工具调用等无法从聚合数据可靠还原的附加费用。")
                Text("该结果仅用于理解 API 等值规模，不代表 Codex 订阅的实际账单。")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Link(
                "查看 OpenAI 官方价格",
                destination: URL(string: "https://developers.openai.com/api/docs/pricing")!
            )
            .font(.caption.weight(.medium))
            Link(
                "查看 GPT-6 Astra 官方价格",
                destination: URL(string: "https://developers.openai.com/api/docs/models/gpt-6-astra")!
            )
            .font(.caption.weight(.medium))
        }
        .padding(14)
        .frame(width: 500, alignment: .leading)
        .background(CodexVistaVisualEffect(style: .popover))
    }

    private var pricingHeader: some View {
        HStack(spacing: 8) {
            Text("模型")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("输入")
                .frame(width: 62, alignment: .trailing)
            Text("缓存输入")
                .frame(width: 68, alignment: .trailing)
            Text("输出 / 推理")
                .frame(width: 78, alignment: .trailing)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 28)
    }

    private func pricingRow(_ modelID: String, rule: ModelPricingRule) -> some View {
        let isReference = ModelPricingCatalog.usesReferencePricing(for: modelID)
        return HStack(spacing: 8) {
            Text(modelID)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
            pricingValue(rule.inputPerMillionUSD, width: 62, approximate: isReference)
            pricingValue(rule.cachedInputPerMillionUSD, width: 68, approximate: isReference)
            pricingValue(rule.outputPerMillionUSD, width: 78, approximate: isReference)
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 10)
        .frame(height: 32)
    }

    private func pricingValue(_ value: Double, width: CGFloat, approximate: Bool) -> some View {
        Text((approximate ? "≈" : "") + ModelCostFormatter.rate(value))
            .frame(width: width, alignment: .trailing)
    }
}

private extension View {
    func settingsCard() -> some View {
        codexVistaGlassSurface(
            cornerRadius: 12,
            shadowOpacity: 0.54
        )
    }
}
