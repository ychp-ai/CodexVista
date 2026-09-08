import Charts
import SwiftUI

struct UsageTrendSeries: Identifiable {
    let model: String?
    let points: [DailyUsage]

    var id: String { model.map { "model:\($0)" } ?? "total" }
    var title: String { model ?? "总量" }

    static func make(from usage: [DailyUsage]) -> [UsageTrendSeries] {
        let models = Set(usage.flatMap { $0.modelEntries.map(\.model) }).sorted()
        return [UsageTrendSeries(model: nil, points: usage)] + models.map { model in
            UsageTrendSeries(model: model, points: usage.map { day in
                let entry = day.modelEntries.first { $0.model == model }
                return DailyUsage(
                    id: day.id, day: day.day, total: entry?.totalTokens ?? 0,
                    uncachedInput: entry?.uncachedInputTokens ?? 0,
                    cachedInput: entry?.cachedInputTokens ?? 0,
                    output: entry?.visibleOutputTokens ?? 0,
                    reasoning: entry?.reasoningTokens ?? 0,
                    estimatedCostUSD: entry.map { $0.estimatedCostUSD } ?? 0,
                    unpricedModelCount: entry != nil && entry?.estimatedCostUSD == nil ? 1 : 0,
                    referencePricedModelCount: entry != nil && ModelPricingCatalog.usesReferencePricing(for: model) ? 1 : 0
                )
            })
        }
    }
}

struct UsageTrendSelection: Equatable {
    let seriesID: String
    let dayID: String
}

struct UsageTrendHitTarget {
    let selection: UsageTrendSelection
    let position: CGPoint

    static func nearest(to location: CGPoint, in targets: [UsageTrendHitTarget]) -> UsageTrendSelection? {
        targets.min { left, right in
            let leftX = abs(left.position.x - location.x)
            let rightX = abs(right.position.x - location.x)
            if leftX != rightX { return leftX < rightX }
            return abs(left.position.y - location.y) < abs(right.position.y - location.y)
        }?.selection
    }
}

struct UsageTrendChart: View {
    let usage: [DailyUsage]
    let showsXAxis: Bool
    let modelNames: [String]

    @State private var hiddenSeriesIDs: Set<String> = []
    @State private var selection: UsageTrendSelection?
    @State private var isHoveringCard = false
    @State private var dismissTask: Task<Void, Never>?

    private var series: [UsageTrendSeries] { UsageTrendSeries.make(from: usage) }
    private var visibleSeries: [UsageTrendSeries] {
        series.filter { !hiddenSeriesIDs.contains($0.id) }
    }
    private var selectedPoint: (series: UsageTrendSeries, usage: DailyUsage)? {
        guard let selection,
              let series = visibleSeries.first(where: { $0.id == selection.seriesID }),
              let point = series.points.first(where: { $0.id == selection.dayID }) else { return nil }
        return (series, point)
    }
    private var upperBound: Int {
        let maximum = visibleSeries.flatMap { $0.points.map(\.total) }.max() ?? 0
        let (bound, overflow) = maximum.addingReportingOverflow(max(maximum / 5, 1))
        return overflow ? Int.max : max(1, bound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            legend
            Chart {
                ForEach(visibleSeries) { series in
                    ForEach(series.points) { item in
                        if series.model == nil {
                            AreaMark(x: .value("日期", item.day), y: .value("Token", item.total))
                                .foregroundStyle(LinearGradient(
                                    colors: [CodexVistaTheme.dashboardAccent.opacity(0.14), .clear],
                                    startPoint: .top, endPoint: .bottom
                                ))
                                .interpolationMethod(.monotone)
                        }
                        LineMark(x: .value("日期", item.day), y: .value("Token", item.total))
                            .foregroundStyle(by: .value("曲线", series.id))
                            .lineStyle(StrokeStyle(lineWidth: series.model == nil ? 2.5 : 1.7,
                                                   lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("日期", item.day), y: .value("Token", item.total))
                            .foregroundStyle(by: .value("曲线", series.id))
                            .symbolSize(series.model == nil ? 24 : 16)
                            .accessibilityLabel("\(series.title)，\(item.day)，\(item.total) Token")
                    }
                }
                if let selectedPoint {
                    RuleMark(x: .value("悬停日期", selectedPoint.usage.day))
                        .foregroundStyle(color(for: selectedPoint.series).opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    PointMark(x: .value("日期", selectedPoint.usage.day),
                              y: .value("Token", selectedPoint.usage.total))
                        .foregroundStyle(CodexVistaTheme.dashboardSurface)
                        .symbolSize(86)
                    PointMark(x: .value("日期", selectedPoint.usage.day),
                              y: .value("Token", selectedPoint.usage.total))
                        .foregroundStyle(color(for: selectedPoint.series))
                        .symbolSize(46)
                }
            }
            .chartForegroundStyleScale(domain: series.map(\.id), range: series.map { color(for: $0) })
            .chartLegend(.hidden)
            .chartYScale(domain: 0...upperBound)
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
            .chartXAxis(showsXAxis ? .visible : .hidden)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    dismissTask?.cancel()
                                    guard !isHoveringCard else { return }
                                    updateSelection(at: location, proxy: proxy, geometry: geometry)
                                case .ended:
                                    scheduleDismissal()
                                }
                            }
                        if let selectedPoint, let plotFrame = proxy.plotFrame,
                           let x = proxy.position(forX: selectedPoint.usage.day),
                           let y = proxy.position(forY: selectedPoint.usage.total) {
                            Color.clear
                                .frame(width: 1, height: 1)
                                .popover(isPresented: Binding(
                                    get: { selection != nil },
                                    set: { if !$0 { selection = nil } }
                                ), arrowEdge: .bottom) {
                                    DailyUsageHoverCard(
                                        usage: selectedPoint.usage,
                                        dateText: "\(selectedPoint.usage.day) · \(selectedPoint.series.title)"
                                    )
                                    .padding(4)
                                    .onHover { active in
                                        isHoveringCard = active
                                        dismissTask?.cancel()
                                        if !active { scheduleDismissal() }
                                    }
                                }
                                .position(x: geometry[plotFrame].minX + x, y: geometry[plotFrame].minY + y)
                        }
                    }
                }
            }
        }
        .onDisappear { dismissTask?.cancel() }
    }

    private var legend: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(series) { series in
                    let isVisible = !hiddenSeriesIDs.contains(series.id)
                    Button {
                        selection = nil
                        isHoveringCard = false
                        if isVisible {
                            guard visibleSeries.count > 1 else { return }
                            hiddenSeriesIDs.insert(series.id)
                        } else {
                            hiddenSeriesIDs.remove(series.id)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Capsule().fill(color(for: series)).frame(width: 15, height: 3)
                            Text(series.title)
                                .font(.system(size: 9, weight: .medium))
                                .strikethrough(!isVisible)
                        }
                        .opacity(isVisible ? 1 : 0.4)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .help(isVisible ? "隐藏\(series.title)曲线" : "显示\(series.title)曲线")
                    .accessibilityLabel("\(series.title)曲线，\(isVisible ? "已显示" : "已隐藏")")
                    .accessibilityAddTraits(isVisible ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.visible)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func color(for series: UsageTrendSeries) -> Color {
        guard let model = series.model else { return CodexVistaTheme.dashboardAccent }
        let index = modelNames.firstIndex(of: model) ?? 0
        // The full model catalog keeps colors stable when the time range changes.
        let palette: [Color] = [.blue, .orange, .purple, .pink, .green, .indigo, .red, .cyan]
        return palette[index % palette.count]
    }

    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame, geometry[plotFrame].contains(location) else {
            scheduleDismissal()
            return
        }
        let frame = geometry[plotFrame]
        let targets = visibleSeries.flatMap { series in
            series.points.compactMap { item -> UsageTrendHitTarget? in
                guard let x = proxy.position(forX: item.day), let y = proxy.position(forY: item.total) else { return nil }
                return UsageTrendHitTarget(selection: .init(seriesID: series.id, dayID: item.id),
                                           position: CGPoint(x: x, y: y))
            }
        }
        selection = UsageTrendHitTarget.nearest(
            to: CGPoint(x: location.x - frame.minX, y: location.y - frame.minY), in: targets
        )
    }

    private func scheduleDismissal() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            if !isHoveringCard { selection = nil }
        }
    }
}
