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

    var maxVal: Int { store.filteredActivity.map(\.messageCount).max() ?? 1 }

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
