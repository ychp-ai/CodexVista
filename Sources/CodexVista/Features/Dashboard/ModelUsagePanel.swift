import Foundation
import SwiftUI

struct PeriodModelUsageControl: View {
    let periodTitle: String
    let periodSubtitle: String?
    let ranking: ModelUsageRanking

    @State private var isPresented = false
    @State private var isPinned = false
    @State private var isTriggerHovered = false
    @State private var isPopoverHovered = false
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        Button {
            dismissTask?.cancel()
            if isPinned {
                closePopover()
            } else {
                isPinned = true
                isPresented = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 8.5, weight: .semibold))
                Text("\(ranking.entries.count) 模型")
                    .lineLimit(1)
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(
                ranking.entries.isEmpty
                    ? CodexVistaTheme.dashboardMutedText
                    : CodexVistaTheme.dashboardAccent
            )
            .padding(.horizontal, 7)
            .frame(height: 23)
            .background(
                isPinned ? CodexVistaTheme.dashboardAccent.opacity(0.12) : CodexVistaTheme.dashboardControlBackground,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        isPinned ? CodexVistaTheme.dashboardAccent : CodexVistaTheme.dashboardBorder,
                        lineWidth: isPinned ? 1 : 0.7
                    )
            }
        }
        .buttonStyle(CodexVistaControlStyle())
        .disabled(ranking.entries.isEmpty)
        .contentShape(Capsule())
        .onHover(perform: updateTriggerHover)
        .popover(
            isPresented: presentationBinding,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            PeriodModelRankingPopover(
                periodTitle: periodTitle,
                periodSubtitle: periodSubtitle,
                ranking: ranking,
                isPinned: isPinned,
                onTogglePin: togglePinned,
                onClose: closePopover
            )
            .onHover(perform: updatePopoverHover)
            .onExitCommand(perform: closePopover)
        }
        .accessibilityLabel("\(periodTitle)模型排行，\(ranking.entries.count) 个模型")
        .accessibilityHint(
            ranking.entries.isEmpty
                ? "当前范围暂无模型用量"
                : "悬浮预览，点击固定排行榜"
        )
        .help(
            ranking.entries.isEmpty
                ? "当前范围暂无模型用量"
                : "悬浮预览模型排行，点击固定"
        )
        .onDisappear { dismissTask?.cancel() }
    }

    private var presentationBinding: Binding<Bool> {
        Binding(
            get: { isPresented },
            set: { newValue in
                isPresented = newValue
                if !newValue {
                    isPinned = false
                    isTriggerHovered = false
                    isPopoverHovered = false
                }
            }
        )
    }

    private func updateTriggerHover(_ isHovered: Bool) {
        isTriggerHovered = isHovered
        if isHovered {
            dismissTask?.cancel()
            isPresented = true
        } else {
            scheduleDismissIfNeeded()
        }
    }

    private func updatePopoverHover(_ isHovered: Bool) {
        isPopoverHovered = isHovered
        if isHovered {
            dismissTask?.cancel()
            isPresented = true
        } else {
            scheduleDismissIfNeeded()
        }
    }

    private func scheduleDismissIfNeeded() {
        guard !isPinned else { return }
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled,
                  !isPinned,
                  !isTriggerHovered,
                  !isPopoverHovered
            else { return }
            isPresented = false
        }
    }

    private func togglePinned() {
        dismissTask?.cancel()
        isPinned.toggle()
        isPresented = isPinned || isTriggerHovered || isPopoverHovered
    }

    private func closePopover() {
        dismissTask?.cancel()
        isPinned = false
        isPresented = false
        isTriggerHovered = false
        isPopoverHovered = false
    }
}

private struct PeriodModelRankingPopover: View {
    private static let maximumVisibleModelCount = 5

    let periodTitle: String
    let periodSubtitle: String?
    let ranking: ModelUsageRanking
    let isPinned: Bool
    let onTogglePin: () -> Void
    let onClose: () -> Void

    private var visibleRanking: ModelUsageRanking {
        let entries = isPinned
            ? ranking.entries
            : Array(ranking.entries.prefix(Self.maximumVisibleModelCount))
        return ModelUsageRanking(
            entries: entries,
            totalTokens: ranking.totalTokens,
            estimatedCostUSD: ranking.estimatedCostUSD,
            unpricedModelCount: ranking.unpricedModelCount,
            referencePricedModelCount: ranking.referencePricedModelCount
        )
    }

    private var omittedModelCount: Int {
        guard !isPinned else { return 0 }
        return max(0, ranking.entries.count - Self.maximumVisibleModelCount)
    }

    private var contentHeight: CGFloat {
        let visibleCount = max(visibleRanking.entries.count, 1)
        let headerHeight: CGFloat = periodSubtitle == nil ? 30 : 40
        let moreHeight: CGFloat = omittedModelCount > 0 ? 32 : 0
        return min(420, headerHeight + 1 + CGFloat(visibleCount) * 33 + moreHeight + 8)
    }

    var body: some View {
        VStack(spacing: 8) {
            ModelUsagePanel(
                ranking: visibleRanking,
                title: "\(periodTitle) · 模型用量",
                subtitle: periodSubtitle,
                omittedModelCount: omittedModelCount,
                onExpand: onTogglePin
            )
            .frame(height: contentHeight)

            HStack(spacing: 10) {
                Text("排行范围继承当前卡片")
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)

                Spacer(minLength: 12)

                Button(action: onTogglePin) {
                    Label(
                        isPinned
                            ? "取消固定"
                            : (omittedModelCount > 0 ? "固定并展开全部" : "固定排行"),
                        systemImage: isPinned ? "pin.slash" : "pin"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(CodexVistaControlStyle())
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("关闭模型排行")
                .help("关闭")
            }
            .font(.system(size: 9.5, weight: .medium))
            .padding(.horizontal, 2)
        }
        .padding(10)
        .frame(width: 560)
        .background(CodexVistaVisualEffect(style: .popover))
    }
}

struct ModelUsagePanel: View {
    let ranking: ModelUsageRanking
    let title: String
    let subtitle: String?
    let omittedModelCount: Int
    let onExpand: () -> Void

    init(
        ranking: ModelUsageRanking,
        title: String = "模型用量排行",
        subtitle: String? = nil,
        omittedModelCount: Int = 0,
        onExpand: @escaping () -> Void = {}
    ) {
        self.ranking = ranking
        self.title = title
        self.subtitle = subtitle
        self.omittedModelCount = omittedModelCount
        self.onExpand = onExpand
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Rectangle()
                .fill(CodexVistaTheme.dashboardBorder)
                .frame(height: 1)

            if ranking.entries.isEmpty {
                ContentUnavailableView(
                    "暂无模型用量",
                    systemImage: "cpu",
                    description: Text("使用 Codex 后会按模型统计 Token 和 API 等值费用。")
                )
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(ranking.entries.enumerated()), id: \.element.id) { index, entry in
                            modelRow(entry, rank: index + 1)
                            if index < ranking.entries.count - 1 {
                                Rectangle()
                                    .fill(CodexVistaTheme.dashboardBorder.opacity(0.72))
                                    .frame(height: 1)
                                    .padding(.leading, 42)
                            }
                        }
                        if omittedModelCount > 0 {
                            omittedModelsIndicator
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .scrollIndicators(.visible)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            CodexVistaTheme.dashboardSurfaceStrong.opacity(0.74),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CodexVistaTheme.dashboardBorder, lineWidth: 1)
        }
    }

    private var omittedModelsIndicator: some View {
        Button(action: onExpand) {
            HStack(spacing: 4) {
                Text("仅显示 Token 用量前 5 名 · 另有 \(omittedModelCount) 个模型 · 固定后展开")
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(CodexVistaTheme.dashboardAccent)
            }
            .font(.system(size: 9.5, weight: .medium))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(CodexVistaControlStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "仅显示 Token 用量前 5 名，另有 \(omittedModelCount) 个模型，点击固定并展开全部"
        )
        .help("固定排行榜并展开全部模型")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CodexVistaTheme.dashboardAccent)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                }
            }

            if ranking.unpricedModelCount > 0 {
                Text("\(ranking.unpricedModelCount) 个模型暂无定价")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            }
            if ranking.referencePricedModelCount > 0 {
                Text("\(ranking.referencePricedModelCount) 个模型采用参考价")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(TokenFormatter.compact(ranking.totalTokens))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(CodexVistaTheme.dashboardPrimaryText)
                    .monospacedDigit()
                Text("总 Token")
                    .font(.system(size: 8.5, weight: .medium))
            }
            .frame(width: 84, alignment: .trailing)

            VStack(alignment: .trailing, spacing: 1) {
                Text(ModelCostFormatter.usd(ranking.estimatedCostUSD))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(CodexVistaTheme.dashboardAccent)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Text("预估费用总计")
                    .font(.system(size: 8.5, weight: .medium))
            }
            .frame(width: 84, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(CodexVistaTheme.dashboardMutedText)
        .frame(minHeight: subtitle == nil ? 30 : 40)
        .padding(.horizontal, 12)
    }

    private func modelRow(_ entry: ModelUsageEntry, rank: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    rank <= 3 ? CodexVistaTheme.dashboardAccent : CodexVistaTheme.dashboardMutedText
                )
                .frame(width: 22, height: 22)
                .background(
                    CodexVistaTheme.dashboardControlBackground,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )

            Text(entry.model)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 190, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(CodexVistaTheme.dashboardControlBackground)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    CodexVistaTheme.dashboardAccent,
                                    CodexVistaTheme.dashboardAccentSecondary
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(5, geometry.size.width * entry.share))
                }
                .frame(height: 6)
                .frame(maxHeight: .infinity)
            }
            .frame(minWidth: 100, maxWidth: .infinity, minHeight: 22)

            ModelTokenValue(entry: entry)
                .frame(width: 84, alignment: .trailing)

            ModelCostValue(entry: entry)
                .frame(width: 84, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, minHeight: 32)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel(for: entry, rank: rank))
    }

    private func accessibilityLabel(for entry: ModelUsageEntry, rank: Int) -> String {
        let cost = entry.estimatedCostUSD.map {
            ModelCostFormatter.usd(
                $0,
                approximate: ModelPricingCatalog.usesReferencePricing(for: entry.model)
            )
        } ?? "暂无官方定价"
        return "第 \(rank) 名，\(entry.model)，\(entry.totalTokens) Token，API 预估 \(cost)"
    }
}

private struct ModelTokenValue: View {
    let entry: ModelUsageEntry
    @State private var isHovered = false

    var body: some View {
        Text(TokenFormatter.compact(entry.totalTokens))
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(CodexVistaTheme.dashboardPrimaryText.opacity(0.9))
            .monospacedDigit()
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .popover(
                isPresented: $isHovered,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .bottom
            ) {
                ModelTokenDetailCard(entry: entry)
                    .padding(4)
            }
            .help("悬浮查看 Token 明细")
    }
}

private struct ModelCostValue: View {
    let entry: ModelUsageEntry
    @State private var isHovered = false

    var body: some View {
        Text(entry.estimatedCostUSD.map {
            ModelCostFormatter.usd(
                $0,
                approximate: ModelPricingCatalog.usesReferencePricing(for: entry.model)
            )
        } ?? "—")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(
                entry.estimatedCostUSD == nil
                    ? CodexVistaTheme.dashboardMutedText
                    : CodexVistaTheme.dashboardAccent
            )
            .monospacedDigit()
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .popover(
                isPresented: $isHovered,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .bottom
            ) {
                ModelCostDetailCard(entry: entry)
                    .padding(4)
            }
            .help("悬浮查看费用明细")
    }
}

private struct ModelTokenDetailCard: View {
    let entry: ModelUsageEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("\(entry.model) · Token 明细")
                .font(.system(size: 12, weight: .semibold))
            detailRow("未缓存输入", value: tokenValue(entry.uncachedInputTokens))
            detailRow("缓存输入", value: tokenValue(entry.cachedInputTokens))
            detailRow("可见输出", value: tokenValue(entry.visibleOutputTokens))
            detailRow("推理输出", value: tokenValue(entry.reasoningTokens))
            Divider()
            detailRow("总用量", value: TokenFormatter.compact(entry.totalTokens), emphasized: true)
        }
        .modelDetailCard()
    }

    private func tokenValue(_ tokens: Int) -> String {
        let share = entry.totalTokens > 0 ? Double(tokens) / Double(entry.totalTokens) : 0
        return "\(TokenFormatter.compact(tokens)) · \(TokenFormatter.percentage(share))"
    }
}

private struct ModelCostDetailCard: View {
    let entry: ModelUsageEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("\(entry.model) · 预估费用")
                .font(.system(size: 12, weight: .semibold))

            if let rule = ModelPricingCatalog.rule(for: entry.model),
               let total = entry.estimatedCostUSD {
                costRow("未缓存输入", tokens: entry.uncachedInputTokens, rate: rule.inputPerMillionUSD)
                costRow("缓存输入", tokens: entry.cachedInputTokens, rate: rule.cachedInputPerMillionUSD)
                costRow("可见输出", tokens: entry.visibleOutputTokens, rate: rule.outputPerMillionUSD)
                costRow("推理输出", tokens: entry.reasoningTokens, rate: rule.outputPerMillionUSD)
                Divider()
                let usesReferencePricing = ModelPricingCatalog.usesReferencePricing(for: entry.model)
                detailRow(
                    "API 等值总额",
                    value: ModelCostFormatter.usd(total, approximate: usesReferencePricing),
                    emphasized: true
                )
                Text(
                    usesReferencePricing
                        ? "该模型没有独立公开价，按 GPT-5.5 参考价估算；不代表 Codex 实际账单。"
                        : "按标准 API 单价估算，不代表 Codex 实际账单；未计长上下文、缓存写入和工具调用附加费。"
                )
                    .font(.system(size: 9.5))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("暂无公开的独立 API 单价", systemImage: "exclamationmark.circle")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                Text("该模型的 Token 不计入费用预估。")
                    .font(.system(size: 9.5))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            }
        }
        .modelDetailCard()
    }

    private func costRow(_ title: String, tokens: Int, rate: Double) -> some View {
        detailRow(
            title,
            value: "\(TokenFormatter.compact(tokens)) × \(ModelCostFormatter.rate(rate)) = "
                + ModelCostFormatter.usd(Double(tokens) / 1_000_000 * rate)
        )
    }
}

private func detailRow(_ title: String, value: String, emphasized: Bool = false) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(title)
            .foregroundStyle(
                emphasized
                    ? CodexVistaTheme.dashboardPrimaryText
                    : CodexVistaTheme.dashboardMutedText
            )
        Spacer(minLength: 12)
        Text(value)
            .fontWeight(emphasized ? .semibold : .medium)
            .foregroundStyle(
                emphasized
                    ? CodexVistaTheme.dashboardAccent
                    : CodexVistaTheme.dashboardPrimaryText
            )
            .monospacedDigit()
    }
    .font(.system(size: 10.5))
}

private extension View {
    func modelDetailCard() -> some View {
        padding(12)
            .frame(width: 310, alignment: .leading)
            .background(CodexVistaVisualEffect(style: .popover))
    }
}
