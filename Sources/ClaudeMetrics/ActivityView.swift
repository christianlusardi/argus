import SwiftUI
import Charts

struct ActivityView: View {
    @EnvironmentObject var store: MetricsStore

    var totalMessages: Int { store.filteredActivity.reduce(0) { $0 + $1.messageCount } }
    var totalTools: Int    { store.filteredActivity.reduce(0) { $0 + $1.toolCallCount } }
    var peakDay: DailyActivity? { store.filteredActivity.max(by: { $0.messageCount < $1.messageCount }) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: "Activity", subtitle: "Sessions, messages, and tool calls per day")

                HStack(spacing: 14) {
                    MetricCard(
                        icon: "bubble.left.fill",
                        iconColor: .appAccent,
                        label: "Tracked Messages",
                        value: "\(totalMessages)",
                        detail: "\(store.filteredActivity.count) active days"
                    )
                    MetricCard(
                        icon: "hammer.fill",
                        iconColor: .modelHaiku,
                        label: "Tool Calls",
                        value: "\(totalTools)",
                        detail: "across all sessions"
                    )
                    if let peak = peakDay {
                        MetricCard(
                            icon: "flame.fill",
                            iconColor: Color.orange,
                            label: "Busiest Day",
                            value: peak.date,
                            detail: "\(peak.messageCount) messages"
                        )
                    }
                    MetricCard(
                        icon: "calendar.badge.checkmark",
                        iconColor: .appAccent,
                        label: "Current Streak",
                        value: "\(store.currentStreak)",
                        detail: "consecutive days"
                    )
                    MetricCard(
                        icon: "trophy.fill",
                        iconColor: .appGold,
                        label: "Best Streak",
                        value: "\(store.longestStreak)",
                        detail: "consecutive days"
                    )
                }

                if store.filteredActivity.count > 1 {
                    SectionCard(title: "Messages per Day", icon: "chart.bar.fill") {
                        ActivityBarChart()
                            .frame(height: 200)
                    }

                    SectionCard(title: "Tool Calls per Day", icon: "hammer") {
                        ToolCallChart()
                            .frame(height: 140)
                    }
                }

                if store.filteredEfficiencyTrend.count > 1 {
                    SectionCard(title: "Output / Context Ratio", icon: "arrow.up.right.circle") {
                        EfficiencyTrendChart()
                            .frame(height: 140)
                    }
                }

                SectionCard(title: "Activity by Day of Week", icon: "calendar") {
                    DayOfWeekChart().frame(height: 160)
                }

                if !store.workHoursData.isEmpty {
                    SectionCard(title: "Work Hours", icon: "clock.badge") {
                        WorkHoursView()
                    }
                }

                SectionCard(title: "Day-by-Day Breakdown", icon: "tablecells") {
                    ActivityTable()
                }
            }
            .padding(24)
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBg)
    }
}

struct ActivityBarChart: View {
    @EnvironmentObject var store: MetricsStore
    @State private var selectedDate: Date? = nil

    private let tooltipFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()

    var maxVal: Int { store.filteredActivity.map(\.messageCount).max() ?? 1 }

    private func closestItem(to date: Date) -> DailyActivity? {
        store.filteredActivity.min(by: {
            abs($0.dateValue.timeIntervalSince(date)) < abs($1.dateValue.timeIntervalSince(date))
        })
    }

    var body: some View {
        Chart(store.filteredActivity) { item in
            BarMark(
                x: .value("Date", item.dateValue, unit: .day),
                y: .value("Messages", item.messageCount)
            )
            .foregroundStyle(
                item.messageCount == maxVal
                ? Color.appAccent
                : Color.appAccent.opacity(0.65)
            )
            .cornerRadius(3)
        }
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 8)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.appBorder)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(Color.appTextSecondary).font(.system(size: 10))
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.appBorder)
                AxisValueLabel().foregroundStyle(Color.appTextSecondary).font(.system(size: 10))
            }
        }
        .chartPlotStyle { $0.background(Color.clear) }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let sel = selectedDate, let item = closestItem(to: sel) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tooltipFmt.string(from: item.dateValue))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.appTextPrimary)
                        Text("\(item.messageCount) msgs")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.appTextSecondary)
                    }
                    .padding(6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .position(x: min(max(40, (proxy.position(forX: sel) ?? 0) + geo.frame(in: .local).minX), geo.size.width - 40), y: 20)
                }
            }
        }
    }
}

struct ToolCallChart: View {
    @EnvironmentObject var store: MetricsStore

    var body: some View {
        Chart(store.filteredActivity) { item in
            BarMark(
                x: .value("Date", item.dateValue, unit: .day),
                y: .value("Tool Calls", item.toolCallCount)
            )
            .foregroundStyle(Color.modelHaiku.opacity(0.8))
            .cornerRadius(3)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 8)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.appBorder)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(Color.appTextSecondary).font(.system(size: 10))
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.appBorder)
                AxisValueLabel().foregroundStyle(Color.appTextSecondary).font(.system(size: 10))
            }
        }
        .chartPlotStyle { $0.background(Color.clear) }
    }
}

struct EfficiencyTrendChart: View {
    @EnvironmentObject var store: MetricsStore
    @State private var selectedDate: Date? = nil

    private let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private let tooltipFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()

    private struct RatioPoint { let date: Date; let ratio: Double }

    private var points: [RatioPoint] {
        store.filteredEfficiencyTrend.compactMap {
            guard let d = fmt.date(from: $0.date) else { return nil }
            return RatioPoint(date: d, ratio: $0.ratio)
        }
    }

    private func closestPoint(to date: Date) -> RatioPoint? {
        points.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        })
    }

    var body: some View {
        Chart(store.filteredEfficiencyTrend, id: \.date) { item in
            let date = fmt.date(from: item.date) ?? Date()
            LineMark(x: .value("Date", date, unit: .day), y: .value("Ratio", item.ratio))
                .foregroundStyle(Color.modelSonnet)
                .interpolationMethod(.catmullRom)
            AreaMark(x: .value("Date", date, unit: .day), y: .value("Ratio", item.ratio))
                .foregroundStyle(Color.modelSonnet.opacity(0.15))
                .interpolationMethod(.catmullRom)
        }
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.appBorder)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(Color.appTextSecondary).font(.system(size: 10))
            }
        }
        .chartYAxis {
            AxisMarks { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.appBorder)
                if let val = v.as(Double.self) {
                    AxisValueLabel {
                        Text(String(format: "%.2f", val))
                            .font(.system(size: 10)).foregroundStyle(Color.appTextSecondary)
                    }
                }
            }
        }
        .chartPlotStyle { $0.background(Color.clear) }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let sel = selectedDate,
                   let p = closestPoint(to: sel),
                   let plotAnchor = proxy.plotFrame {
                    let plotRect = geo[plotAnchor]
                    let xPos = (proxy.position(forX: p.date) ?? 0) + plotRect.minX
                    let yPos = (proxy.position(forY: p.ratio) ?? 0) + plotRect.minY

                    ChartCrosshair.verticalLine(plotRect: plotRect, xPos: xPos)
                    ChartCrosshair.horizontalLine(plotRect: plotRect, yPos: yPos)
                    ChartCrosshair.point(xPos: xPos, yPos: yPos, color: Color.modelSonnet)
                    ChartCrosshair.tooltip(plotRect: plotRect, xPos: xPos, yPos: yPos) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tooltipFmt.string(from: p.date))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.appTextPrimary)
                            Text(String(format: "%.2f", p.ratio))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.modelSonnet)
                        }
                    }
                }
            }
        }
    }
}

struct ActivityTable: View {
    @EnvironmentObject var store: MetricsStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DATE")      .frame(maxWidth: .infinity, alignment: .leading)
                Text("MESSAGES")  .frame(width: 90, alignment: .trailing)
                Text("SESSIONS")  .frame(width: 90, alignment: .trailing)
                Text("TOOL CALLS").frame(width: 100, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.appTextTertiary)
            .tracking(0.4)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Color.appBorder.frame(height: 1)

            ForEach(store.filteredActivity.reversed()) { item in
                HStack {
                    Text(item.date)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.appTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(item.messageCount)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.appTextPrimary)
                        .frame(width: 90, alignment: .trailing)
                    Text("\(item.sessionCount)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.appTextSecondary)
                        .frame(width: 90, alignment: .trailing)
                    Text("\(item.toolCallCount)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.modelHaiku)
                        .frame(width: 100, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)

                Color.appBorder.opacity(0.45).frame(height: 1)
            }
        }
    }
}
