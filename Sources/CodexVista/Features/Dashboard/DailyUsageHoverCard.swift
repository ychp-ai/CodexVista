import SwiftUI

struct DailyUsageHoverCard: View {
    let usage: DailyUsage
    let dateText: String
    @Binding var showsModelDetails: Bool
    @State private var showsQuotaChanges = false

    var body: some View {
        // Keep the native popover size stable. Content-driven resizing enters
        // AppKit's animated window layout, which can crash during disclosure updates.
        ScrollView(.vertical) {
            cardContent
        }
        .scrollIndicators(.visible)
        .frame(width: 308, height: 400)
        .background(
            CodexVistaTheme.dashboardSurface,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(CodexVistaTheme.dashboardBorder)
        }
        .shadow(color: CodexVistaTheme.dashboardShadow, radius: 7, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(dateText)，总 Token \(usage.total)，输入 \(usage.uncachedInput)（\(tokenShare(usage.uncachedInput))），缓存 \(usage.cachedInput)（\(tokenShare(usage.cachedInput))），输出 \(usage.output)（\(tokenShare(usage.output))），推理 \(usage.reasoning)（\(tokenShare(usage.reasoning))）\(costAccessibilityDescription)"
        )
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(dateText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(TokenFormatter.compact(usage.total))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(CodexVistaTheme.dashboardPrimaryText)
                    .monospacedDigit()
                    .help(usage.total.formatted())
                Text("总 Token")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            }
            .padding(.bottom, 5)

            Rectangle()
                .fill(CodexVistaTheme.dashboardBorder.opacity(0.8))
                .frame(height: 1)

            TokenCompositionView(
                breakdown: TokenBreakdown(input: usage.uncachedInput, cachedInput: usage.cachedInput,
                                          output: usage.output, reasoning: usage.reasoning),
                total: usage.total, compact: true
            )
            .padding(.vertical, 5)

            if let statistics = usage.quotaStatistics {
                Divider()
                HStack {
                    Text("7 天额度 · 平均每 1%")
                    Spacer()
                    Text(statistics.tokensPerPercent.map {
                        "≈ " + $0.formatted(.number.precision(.fractionLength(0))) + " Token"
                    } ?? "样本不足")
                    .foregroundStyle(CodexVistaTheme.dashboardAccent)
                }
                .font(.system(size: 10, weight: .medium))
                Text("按同日、同周期的观测区间估算；仅含本机 Token。")
                    .font(.system(size: 8.5))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                if statistics.tokensPerPercent != nil {
                    Text("有效样本消耗 \(statistics.consumedPercentagePoints.formatted(.number.precision(.fractionLength(2)))) 个百分点")
                        .font(.system(size: 8.5))
                        .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                }
                Button {
                    showsQuotaChanges.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showsQuotaChanges ? "chevron.down" : "chevron.right")
                            .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                            .accessibilityHidden(true)
                        Text("额度变动记录 · 本地时间（\(statistics.changes.count)）")
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 10))
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(showsQuotaChanges ? "已展开" : "已折叠")
                if showsQuotaChanges {
                    VStack(alignment: .leading, spacing: 6) {
                        if statistics.changes.isEmpty {
                            Text("暂无额度变动观测")
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(statistics.changes.reversed()) { change in
                                    HStack {
                                        Text(change.observedAt.formatted(Date.FormatStyle(timeZone: .autoupdatingCurrent).month(.twoDigits).day(.twoDigits).hour().minute().second()))
                                        Text(change.reason)
                                        Spacer(minLength: 4)
                                        Text("剩余 " + TokenFormatter.percentage(change.remaining))
                                    }
                                }
                            }
                        }
                    }
                    .font(.system(size: 10))
                }
            }

            if let estimatedCostUSD = usage.estimatedCostUSD {
                Rectangle()
                    .fill(CodexVistaTheme.dashboardBorder.opacity(0.8))
                    .frame(height: 1)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("API 等值预计花费")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(CodexVistaTheme.dashboardMutedText)

                    Spacer(minLength: 8)

                    Text(ModelCostFormatter.usd(
                        estimatedCostUSD,
                        approximate: usage.referencePricedModelCount > 0
                    ))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(CodexVistaTheme.dashboardAccent)
                        .monospacedDigit()
                }

                if usage.unpricedModelCount > 0 {
                    Text("部分估算 · \(usage.unpricedModelCount) 个模型未定价")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                } else if usage.referencePricedModelCount > 0 {
                    Text("参考估算 · \(usage.referencePricedModelCount) 个模型按 GPT-5.5 参考价")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                }
            }
            if !usage.modelEntries.isEmpty {
                Divider()
                Button {
                    showsModelDetails.toggle()
                } label: {
                    HStack {
                        Text(showsModelDetails ? "收起模型明细" : "查看模型明细")
                        Spacer()
                        Text("\(usage.modelEntries.count) 个模型")
                            .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                        Image(systemName: showsModelDetails ? "chevron.up" : "chevron.down")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(CodexVistaTheme.dashboardAccent)
                .accessibilityValue(showsModelDetails ? "已展开" : "已折叠")
                if showsModelDetails {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(usage.modelEntries) { entry in
                            modelSection(entry)
                        }
                    }
                    .padding(.vertical, 5)
                }
                Text("API 等值估算，不代表 Codex 实际账单。")
                    .font(.system(size: 8.5))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            }
        }
        .frame(width: 290)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
    }

    private func modelSection(_ entry: ModelUsageEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.model)
                    .font(.system(size: 10, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(TokenFormatter.compact(entry.totalTokens))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            TokenCompositionView(
                breakdown: TokenBreakdown(
                    input: entry.uncachedInputTokens, cachedInput: entry.cachedInputTokens,
                    output: entry.visibleOutputTokens, reasoning: entry.reasoningTokens
                ),
                total: entry.totalTokens, compact: true
            )
            HStack {
                Text("API 等值预计花费")
                Spacer()
                Text(entry.estimatedCostUSD.map {
                    ModelCostFormatter.usd($0, approximate: ModelPricingCatalog.usesReferencePricing(for: entry.model))
                } ?? "未定价")
                    .foregroundStyle(CodexVistaTheme.dashboardAccent)
                    .monospacedDigit()
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            Divider()
        }
    }

    private var costAccessibilityDescription: String {
        guard let estimatedCostUSD = usage.estimatedCostUSD else { return "" }
        let unpricedDescription = usage.unpricedModelCount > 0
            ? "，\(usage.unpricedModelCount) 个模型未定价"
            : ""
        let referenceDescription = usage.referencePricedModelCount > 0
            ? "，\(usage.referencePricedModelCount) 个模型采用 GPT-5.5 参考价"
            : ""
        let cost = ModelCostFormatter.usd(
            estimatedCostUSD,
            approximate: usage.referencePricedModelCount > 0
        )
        return "，API 等值预计花费 \(cost)\(unpricedDescription)\(referenceDescription)"
    }

    private func tokenShare(_ value: Int) -> String {
        TokenFormatter.percentage(usage.total > 0 ? Double(value) / Double(usage.total) : 0)
    }

}
