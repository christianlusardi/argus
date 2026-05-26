import SwiftUI
import Charts

struct OverviewView: View {
    @EnvironmentObject var store: MetricsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    title: "Overview",
                    subtitle: store.stats?.lastComputedDate.map { "Data as of \($0)" } ?? "Claude Code usage summary"
                )

                // KPI row 1
                HStack(spacing: 14) {
                    MetricCard(
                        icon: "bubble.left.and.bubble.right.fill",
                        iconColor: .appAccent,
                        label: "Total Messages",
                        value: "\(store.filteredTotalMessages)",
                        detail: "\(store.filteredTotalSessions) sessions"
                    )
                    MetricCard(
                        icon: "arrow.up.right.circle.fill",
                        iconColor: .modelSonnet,
                        label: "Output Tokens",
                        value: formatTokens(store.filteredOutputTokens),
                        detail: "\(formatTokens(store.filteredInputTokens)) input"
                    )
                    MetricCard(
                        icon: "doc.on.doc.fill",
                        iconColor: .modelHaiku,
                        label: "Cache Tokens",
                        value: formatTokens(store.filteredCacheTokens),
                        detail: "reads + writes"
                    )
                    MetricCard(
                        icon: "dollarsign.circle.fill",
                        iconColor: .appGold,
                        label: "Est. Cost",
                        value: formatCost(store.filteredTotalCost),
                        detail: "public pricing"
                    )
                }

                // KPI row 2
                HStack(spacing: 14) {
                    MetricCard(
                        icon: "doc.on.doc.fill",
                        iconColor: .modelHaiku,
                        label: "Cache Hit Rate",
                        value: String(format: "%.1f%%", store.filteredCacheHitRate * 100),
                        detail: "tokens served from cache"
                    )
                    MetricCard(
                        icon: "tag.fill",
                        iconColor: .appGold,
                        label: "Cache Savings",
                        value: formatCost(store.filteredCacheSavings),
                        detail: "vs full input price"
                    )
                    MetricCard(
                        icon: "flame.fill",
                        iconColor: Color.orange,
                        label: "Current Streak",
                        value: "\(store.currentStreak)",
                        detail: "consecutive days"
                    )
                    MetricCard(
                        icon: "magnifyingglass.circle.fill",
                        iconColor: .modelSonnet,
                        label: "Web Searches",
                        value: "\(store.filteredWebSearches)",
                        detail: "server-side searches"
                    )
                }

                // Daily activity chart
                if store.filteredActivity.count > 1 {
                    SectionCard(title: "Daily Messages", icon: "chart.xyaxis.line") {
                        DailyMessagesChart()
                            .frame(height: 200)
                    }
                }

                // Model comparison
                if !store.filteredSortedModels.isEmpty {
                    SectionCard(title: "Token Usage by Model", icon: "cpu") {
                        ModelOutputChart()
                            .frame(height: 150)
                    }
                }

                // Daily cost
                if store.filteredDailyCostData.count > 1 {
                    SectionCard(title: "Daily Cost", icon: "dollarsign.circle") {
                        OverviewDailyCostChart()
                            .frame(height: 160)
                    }
                }
            }
            .padding(24)
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBg)
    }
}

struct DailyMessagesChart: View {
    @EnvironmentObject var store: MetricsStore

    var body: some View {
        Chart(store.filteredActivity) { item in
            AreaMark(
                x: .value("Date", item.dateValue),
                y: .value("Messages", item.messageCount)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.appAccent.opacity(0.35), Color.appAccent.opacity(0.04)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Date", item.dateValue),
                y: .value("Messages", item.messageCount)
            )
            .foregroundStyle(Color.appAccent)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.catmullRom)

            PointMark(
                x: .value("Date", item.dateValue),
                y: .value("Messages", item.messageCount)
            )
            .foregroundStyle(Color.appAccent)
            .symbolSize(28)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 7)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.appBorder)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(Color.appTextSecondary)
                    .font(.system(size: 10))
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

struct OverviewDailyCostChart: View {
    @EnvironmentObject var store: MetricsStore

    struct CostPoint: Identifiable {
        let id: String
        let date: Date
        let cost: Double
    }

    var points: [CostPoint] {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        return store.filteredDailyCostData.compactMap { item in
            guard let d = fmt.date(from: item.date) else { return nil }
            return CostPoint(id: item.date, date: d, cost: item.cost)
        }
    }

    var body: some View {
        Chart(points) { p in
            AreaMark(x: .value("Date", p.date), y: .value("Cost", p.cost))
                .foregroundStyle(LinearGradient(
                    colors: [Color.appGold.opacity(0.35), Color.appGold.opacity(0.04)],
                    startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("Date", p.date), y: .value("Cost", p.cost))
                .foregroundStyle(Color.appGold)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            PointMark(x: .value("Date", p.date), y: .value("Cost", p.cost))
                .foregroundStyle(Color.appGold).symbolSize(28)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 7)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.appBorder)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(Color.appTextSecondary).font(.system(size: 10))
            }
        }
        .chartYAxis {
            AxisMarks { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.appBorder)
                AxisValueLabel {
                    if let n = v.as(Double.self) {
                        Text(formatCost(n)).font(.system(size: 10)).foregroundStyle(Color.appTextSecondary)
                    }
                }
            }
        }
        .chartPlotStyle { $0.background(Color.clear) }
    }
}

struct ModelOutputChart: View {
    @EnvironmentObject var store: MetricsStore

    struct BarItem: Identifiable {
        let id: String
        let model: String
        let tokens: Int
        let kind: String
    }

    var items: [BarItem] {
        store.filteredSortedModels.flatMap { entry in [
            BarItem(id: "\(entry.model)-out", model: modelDisplayName(entry.model),
                    tokens: entry.stats.outputTokens, kind: "Output"),
            BarItem(id: "\(entry.model)-in",  model: modelDisplayName(entry.model),
                    tokens: entry.stats.inputTokens,  kind: "Input"),
        ]}
    }

    var body: some View {
        Chart(items) { item in
            BarMark(
                x: .value("Tokens", item.tokens),
                y: .value("Model", item.model)
            )
            .foregroundStyle(by: .value("Kind", item.kind))
        }
        .chartForegroundStyleScale([
            "Output": Color.appAccent,
            "Input":  Color.appAccent.opacity(0.38),
        ])
        .chartXAxis {
            AxisMarks { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.appBorder)
                AxisValueLabel {
                    if let n = v.as(Int.self) {
                        Text(formatTokens(n))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.appTextSecondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel().font(.system(size: 11)).foregroundStyle(Color.appTextPrimary)
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .chartPlotStyle { $0.background(Color.clear) }
    }
}
