import SwiftUI

enum TokenRateExplanation {
    case latestReply(completedAt: Date?)
    case reply
    case task
    case todayTask

    var title: String {
        switch self {
        case .latestReply: "最近输出速率"
        case .reply: "回复输出速率"
        case .task, .todayTask: "任务输出速率"
        }
    }

    var formula: String {
        switch self {
        case .latestReply, .reply: "回复输出 Token ÷ 回复累计耗时"
        case .task: "当前范围内输出 Token ÷ 回复累计耗时"
        case .todayTask: "今日输出 Token ÷ 今日回复累计耗时"
        }
    }

    var detail: String {
        switch self {
        case .latestReply:
            "取最近一次有完整用量与耗时的已完成回复，保留结果直到下一次回复完成，不限制近一分钟。"
        case .reply:
            "按这次回复在当前统计范围内的用量和耗时计算。进行中的回复随刷新更新，缺少有效耗时显示“—”。"
        case .task, .todayTask:
            "先汇总回复的输出 Token 和耗时，再相除。进行中的回复随刷新更新；缺少完整耗时或存在未归属回复的 Token 时显示“—”。"
        }
    }
}

struct TokenRateInfoButton: View {
    let explanation: TokenRateExplanation
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("查看输出速率说明")
        .accessibilityLabel("\(explanation.title)说明")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            TokenRateExplanationView(explanation: explanation)
                .onExitCommand { isPresented = false }
        }
    }
}

struct TokenRateExplanationView: View {
    let explanation: TokenRateExplanation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(explanation.title)
                .font(.system(size: 12, weight: .semibold))
            Text(explanation.formula)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CodexVistaTheme.dashboardAccent)
            Text(explanation.detail)
            Text("单位为 Token/s，输出 Token 为可见输出与推理输出之和，不含输入和缓存输入。回复耗时包含等待与工具执行，因此表示整轮回复的平均输出速率，并非纯生成速度。")
            Text("子 Agent 输出归并到主回复，耗时不重复计算。")
            if case .latestReply(let completedAt) = explanation {
                Text(completedAt.map {
                    "最近完成于 \($0.formatted(date: .abbreviated, time: .standard))"
                } ?? "暂无完整回复记录")
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(CodexVistaTheme.dashboardPrimaryText)
        .lineLimit(nil)
        .minimumScaleFactor(1)
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .frame(width: 300, alignment: .leading)
        .background(CodexVistaTheme.dashboardSurface)
    }
}
