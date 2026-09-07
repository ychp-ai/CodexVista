import SwiftUI

struct ProjectConversationHoverCard: View {
    let conversation: ProjectConversationUsage
    var expandsActivityDetails = false

    var body: some View {
        let totals = tokenTotals
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "list.bullet.rectangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CodexVistaTheme.dashboardAccent)
                    .frame(width: 30, height: 30)
                    .background(
                        CodexVistaTheme.dashboardAccent.opacity(0.10),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("任务调用详情")
                        .font(.system(size: 13, weight: .semibold))
                    Text(
                        ProjectUsageDateFormatter.relative(
                            conversation.lastMessageAtMilliseconds
                        )
                    )
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                    .monospacedDigit()
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(TokenFormatter.compact(conversation.tokens)) Token")
                        .foregroundStyle(CodexVistaTheme.dashboardAccent)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(
                            CodexVistaTheme.dashboardAccent.opacity(0.09),
                            in: Capsule()
                        )
                    Label(
                        TokenFormatter.compactWorktime(
                            conversation.aiWorktimeMilliseconds
                        ),
                        systemImage: "stopwatch"
                    )
                    .foregroundStyle(CodexVistaTheme.dashboardAccentSecondary)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(
                        CodexVistaTheme.dashboardAccentSecondary.opacity(0.09),
                        in: Capsule()
                    )
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(conversation.tokens.formatted()) Token，耗时 "
                        + TokenFormatter.worktime(conversation.aiWorktimeMilliseconds)
                )
                .help(
                    "耗时："
                        + TokenFormatter.worktime(conversation.aiWorktimeMilliseconds)
                )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.displayTitle ?? conversation.shortThreadID)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("任务标识 \(conversation.shortThreadID)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("模型调用", systemImage: "cpu")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(CodexVistaTheme.dashboardAccent)
                Spacer(minLength: 8)
                Text(modelText)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(CodexVistaTheme.dashboardPrimaryText.opacity(0.90))
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(
                CodexVistaTheme.dashboardAccent.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )

            ProjectTokenCostEstimateCard(
                tokenBreakdown: TokenBreakdown(
                    input: totals.uncachedInput,
                    cachedInput: totals.cachedInput,
                    output: totals.visibleOutput,
                    reasoning: totals.reasoning
                ),
                costBreakdown: conversation.estimatedCostBreakdown,
                unpricedModelCount: conversation.unpricedModelCount,
                referencePricedModelCount: conversation.referencePricedModelCount,
                contextName: "本任务",
                excludedTokenCount: conversation.unattributedTokens
            )

            HStack(spacing: 8) {
                summary(
                    title: "回复",
                    count: conversation.replies.count,
                    icon: "bubble.left.fill",
                    tint: CodexVistaTheme.accent
                )
                summary(
                    title: "Skills",
                    count: skillCallCount,
                    icon: "sparkles",
                    tint: CodexVistaTheme.dashboardInput
                )
                summary(
                    title: "Tools",
                    count: toolCallCount,
                    icon: "wrench.and.screwdriver.fill",
                    tint: CodexVistaTheme.dashboardAccentSecondary
                )
            }

            Divider()

            if expandsActivityDetails {
                activityDetails
            } else {
                ScrollView(.vertical) {
                    activityDetails
                }
                .frame(minHeight: 110, maxHeight: 380)
                .scrollIndicators(.hidden)
            }
        }
        .padding(16)
        .frame(width: 410)
        .background(
            CodexVistaTheme.dashboardSurfaceOpaque,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CodexVistaTheme.dashboardBorder, lineWidth: 1)
        }
        .foregroundStyle(CodexVistaTheme.dashboardPrimaryText)
    }

    private var activityDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            activitySection(
                title: "Skills 调用",
                icon: "sparkles",
                tint: CodexVistaTheme.dashboardInput,
                calls: conversation.skillCalls
            )
            activitySection(
                title: "Tools 调用",
                icon: "wrench.and.screwdriver.fill",
                tint: CodexVistaTheme.dashboardAccentSecondary,
                calls: conversation.toolCalls
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modelText: String {
        ProjectReplyPresentation.modelText(
            conversation.modelCalls
                .map { "\($0.name) ×\($0.count)" }
                .joined(separator: " · ")
        )
    }

    private var skillCallCount: Int {
        conversation.skillCalls.reduce(0) { $0 + $1.count }
    }

    private var toolCallCount: Int {
        conversation.toolCalls.reduce(0) { $0 + $1.count }
    }

    private var tokenTotals: (
        uncachedInput: Int,
        cachedInput: Int,
        visibleOutput: Int,
        reasoning: Int
    ) {
        conversation.replies.reduce(into: (0, 0, 0, 0)) { totals, reply in
            totals.0 += reply.uncachedInputTokens
            totals.1 += reply.cachedInputTokens
            totals.2 += reply.visibleOutputTokens
            totals.3 += reply.reasoningTokens
        }
    }

    private func summary(
        title: String,
        count: Int,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            Spacer(minLength: 0)
            Text("\(count) 次")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 38)
        .background(
            tint.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private func activitySection(
        title: String,
        icon: String,
        tint: Color,
        calls: [ProjectReplyActivityCall]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint)

            if calls.isEmpty {
                Text("本任务未调用")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            } else {
                ForEach(calls) { call in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(tint.opacity(0.72))
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)
                        Text(call.name)
                            .font(.system(size: 10, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Text("\(call.count) 次")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                            .monospacedDigit()
                            .padding(.top, 1)
                    }
                    .frame(minHeight: 20)
                }
            }
        }
    }
}

struct ProjectTokenCostEstimateCard: View {
    let tokenBreakdown: TokenBreakdown
    let costBreakdown: ModelCostBreakdown?
    let unpricedModelCount: Int
    let referencePricedModelCount: Int
    let contextName: String
    let excludedTokenCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Token API 等值费用", systemImage: "dollarsign.circle")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(CodexVistaTheme.dashboardAccentSecondary)
                Spacer(minLength: 8)
                if let estimatedCostUSD = costBreakdown?.totalUSD {
                    Text(ModelCostFormatter.usd(
                        estimatedCostUSD,
                        approximate: referencePricedModelCount > 0
                    ))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(CodexVistaTheme.dashboardAccentSecondary)
                        .monospacedDigit()
                } else {
                    Text("暂无公开定价")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                }
            }

            Divider()
            if let costBreakdown {
                TokenCompositionCostTable(breakdown: tokenBreakdown, costs: costBreakdown)
            } else {
                TokenCompositionView(breakdown: tokenBreakdown, compact: true)
            }

            Text(costDescription)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 38)
        .background(
            CodexVistaTheme.dashboardAccentSecondary.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(costAccessibilityLabel)
    }

    private var costDescription: String {
        let pricingDescription: String
        if costBreakdown == nil {
            pricingDescription = "\(contextName)使用的模型均未收录公开 API 单价"
        } else if unpricedModelCount > 0 {
            pricingDescription = "部分估算 · \(unpricedModelCount) 个模型未定价；不代表 Codex 实际账单"
        } else if referencePricedModelCount > 0 {
            pricingDescription = "参考估算 · \(referencePricedModelCount) 个模型按 GPT-5.5 参考价；不代表 Codex 实际账单"
        } else {
            pricingDescription = "按公开 API 标准单价估算，不代表 Codex 实际账单"
        }

        guard excludedTokenCount > 0 else { return pricingDescription }
        return pricingDescription
            + "；另有 \(TokenFormatter.compact(excludedTokenCount)) Token 未归属到回复，未计入估算"
    }

    private var costAccessibilityLabel: String {
        guard let costBreakdown else {
            return "Token API 等值费用，暂无公开定价，\(costDescription)"
        }
        return "Token API 等值费用，未缓存输入 \(ModelCostFormatter.usd(costBreakdown.uncachedInputUSD))，"
            + "缓存输入 \(ModelCostFormatter.usd(costBreakdown.cachedInputUSD))，"
            + "可见输出 \(ModelCostFormatter.usd(costBreakdown.visibleOutputUSD))，"
            + "推理输出 \(ModelCostFormatter.usd(costBreakdown.reasoningUSD))，"
            + "总额 \(ModelCostFormatter.usd(costBreakdown.totalUSD))，\(costDescription)"
    }
}
