import SwiftUI
import Charts

struct ScheduleView: View {
    @EnvironmentObject var store: MetricsStore

    var peakHourLabel: String {
        guard let h = store.filteredPeakHour else { return "—" }
        return hourLabel(h)
    }

    func hourLabel(_ h: Int) -> String {
        switch h {
        case 0:  return "12 AM"
        case 12: return "12 PM"
        case let x where x < 12: return "\(x) AM"
        default: return "\(h - 12) PM"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: "Schedule", subtitle: "When you use Claude throughout the day")

                HStack(spacing: 14) {
                    if let start = store.avgStartHour {
                        MetricCard(
                            icon: "sunrise.fill",
                            iconColor: .appGold,
                            label: "Avg Start",
                            value: formatHour(start),
                            detail: "first message of the day"
                        )
                    }
                    if let end = store.avgEndHour {
                        MetricCard(
                            icon: "sunset.fill",
                            iconColor: .modelOpus,
                            label: "Avg End",
                            value: formatHour(end),
                            detail: "last message of the day"
                        )
                    }
                    if let longest = store.stats?.longestSession?.messageCount, longest > 0 {
                        MetricCard(
                            icon: "clock.badge.checkmark.fill",
                            iconColor: .modelSonnet,
                            label: "Longest Session",
                            value: "\(longest)",
                            detail: "messages in one session"
                        )
                    }
                    if let first = store.stats?.firstSessionDate {
                        MetricCard(
                            icon: "calendar.badge.clock",
                            iconColor: .modelOpus,
                            label: "First Session",
                            value: first,
                            detail: "when it all started"
                        )
                    }
                    if let ms = store.stats?.totalSpeculationTimeSavedMs, ms > 0 {
                        MetricCard(
                            icon: "bolt.fill",
                            iconColor: .appGold,
                            label: "Time Saved",
                            value: formatMs(ms),
                            detail: "speculative decoding"
                        )
                    }
                    MetricCard(
                        icon: "chart.bar.fill",
                        iconColor: .appAccent,
                        label: "Peak Hour",
                        value: peakHourLabel,
                        detail: "most active time"
                    )
                }

                SectionCard(title: "Activity by Hour of Day", icon: "clock") {
                    HourlyBarChart()
                        .frame(height: 220)
                }

                SectionCard(title: "Top 5 Active Hours", icon: "chart.line.uptrend.xyaxis") {
                    TopHoursView()
                }

                SectionCard(title: "Activity by Day of Week", icon: "calendar.badge.clock") {
                    DayOfWeekChart().frame(height: 160)
                }
            }
            .padding(24)
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBg)
    }

    func formatHour(_ h: Double) -> String {
        let total = Int(h * 60)
        let hour = (total / 60) % 24
        let min  = total % 60
        let suffix = hour < 12 ? "AM" : "PM"
        let h12    = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return min == 0 ? "\(h12) \(suffix)" : String(format: "%d:%02d \(suffix)", h12, min)
    }

    func formatMs(_ ms: Int) -> String {
        let s = ms / 1000
        if s < 60   { return "\(s)s" }
        let m = s / 60
        if m < 60   { return "\(m)m \(s % 60)s" }
        return "\(m / 60)h \(m % 60)m"
    }
}

struct HourlyBarChart: View {
    @EnvironmentObject var store: MetricsStore

    struct HourPoint: Identifiable {
        let id: Int
        let hour: Int
        let count: Int
        let label: String
    }

    var maxCount: Int { store.filteredHourlyData.map(\.count).max() ?? 1 }

    var points: [HourPoint] {
        store.filteredHourlyData.map { d in
            let label: String
            switch d.hour {
            case 0:  label = "12a"
            case 6:  label = "6a"
            case 12: label = "12p"
            case 18: label = "6p"
            case let h where h % 3 == 0: label = h < 12 ? "\(h)a" : "\(h-12)p"
            default: label = ""
            }
            return HourPoint(id: d.hour, hour: d.hour, count: d.count, label: label)
        }
    }

    var body: some View {
        Chart(points) { p in
            BarMark(
                x: .value("Hour", p.label.isEmpty ? " " : p.label),
                y: .value("Sessions", p.count)
            )
            .foregroundStyle(
                p.count == maxCount
                ? Color.appAccent
                : Color.appAccent.opacity(0.20 + 0.65 * (maxCount > 0 ? Double(p.count) / Double(maxCount) : 0))
            )
            .cornerRadius(3)
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.system(size: 10))
                    .foregroundStyle(Color.appTextSecondary)
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

struct TopHoursView: View {
    @EnvironmentObject var store: MetricsStore

    var topHours: [(hour: Int, count: Int)] {
        store.filteredHourlyData.filter { $0.count > 0 }.sorted { $0.count > $1.count }.prefix(5).map { $0 }
    }

    var maxCount: Int { topHours.map(\.count).max() ?? 1 }

    func label(_ h: Int) -> String {
        switch h {
        case 0:  return "Midnight"
        case 12: return "Noon"
        case let x where x < 12: return "\(x):00 AM"
        default: return "\(h - 12):00 PM"
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(topHours, id: \.hour) { item in
                HStack(spacing: 14) {
                    Text(label(item.hour))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appTextSecondary)
                        .frame(width: 90, alignment: .trailing)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(Color.appBorder)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.appAccent, Color.appAccent.opacity(0.6)],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * Double(item.count) / Double(maxCount))
                        }
                    }
                    .frame(height: 16)

                    Text("\(item.count)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.appAccent)
                        .frame(width: 28, alignment: .trailing)
                }
            }

            if topHours.isEmpty {
                Text("No hourly data available")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appTextTertiary)
            }
        }
    }
}
