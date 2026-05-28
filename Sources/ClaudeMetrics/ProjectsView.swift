import SwiftUI
import Charts

// MARK: - Shared charts used by Activity and Schedule

struct DayOfWeekChart: View {
    @EnvironmentObject var store: MetricsStore

    var maxCount: Int { store.dayOfWeekData.map(\.count).max() ?? 1 }

    var body: some View {
        Chart(store.dayOfWeekData, id: \.day) { item in
            BarMark(x: .value("Day", item.day), y: .value("Messages", item.count))
                .foregroundStyle(
                    item.count == maxCount
                    ? Color.appAccent
                    : Color.appAccent.opacity(0.20 + 0.55 * (maxCount > 0 ? Double(item.count) / Double(maxCount) : 0))
                )
                .cornerRadius(3)
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().font(.system(size: 11)).foregroundStyle(Color.appTextSecondary)
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

struct WorkHoursView: View {
    @EnvironmentObject var store: MetricsStore

    var recent: [DailyWorkHours] { Array(store.workHoursData.suffix(14)) }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(recent.reversed()) { item in
                HStack(spacing: 10) {
                    Text(item.date)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.appTextSecondary)
                        .frame(width: 82, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(Color.appBorder)
                            let total = geo.size.width
                            let startFrac = CGFloat(item.firstHour) / 24.0
                            let endFrac   = CGFloat(item.lastHour + 1) / 24.0
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.appAccent.opacity(0.75))
                                .frame(width: max(4, total * (endFrac - startFrac)))
                                .offset(x: total * startFrac)
                        }
                    }
                    .frame(height: 10)

                    Text("\(hourLabel(item.firstHour))–\(hourLabel(item.lastHour))")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.appTextTertiary)
                        .frame(width: 90, alignment: .trailing)
                }
            }
        }
    }

    func hourLabel(_ h: Int) -> String {
        h == 0 ? "12a" : h < 12 ? "\(h)a" : h == 12 ? "12p" : "\(h-12)p"
    }
}

// MARK: - Projects view

struct ProjectsView: View {
    @EnvironmentObject var store: MetricsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: "Projects", subtitle: "Token usage and cost by repository")

                HStack(spacing: 14) {
                    MetricCard(
                        icon: "folder.fill",
                        iconColor: .appAccent,
                        label: "Projects",
                        value: "\(store.filteredSortedProjects.count)",
                        detail: "tracked repos"
                    )
                    MetricCard(
                        icon: "person.crop.circle.fill",
                        iconColor: .modelSonnet,
                        label: "Direct Sessions",
                        value: "\(store.directSessionCount)",
                        detail: "your sessions"
                    )
                    MetricCard(
                        icon: "cpu.fill",
                        iconColor: .modelHaiku,
                        label: "Subagent Sessions",
                        value: "\(store.subagentSessionCount)",
                        detail: "spawned agents"
                    )
                    MetricCard(
                        icon: "arrow.up.right.circle.fill",
                        iconColor: .modelOpus,
                        label: "Avg Tokens/Session",
                        value: formatTokens(store.avgOutputTokensPerSession),
                        detail: "output tokens"
                    )
                }

                if !store.filteredSortedProjects.isEmpty {
                    SectionCard(title: "Cost by Project", icon: "dollarsign.circle") {
                        ProjectCostChart()
                            .frame(height: max(120, Double(min(store.filteredSortedProjects.count, 8)) * 38))
                    }
                }

                SectionCard(title: "Project Breakdown", icon: "tablecells") {
                    ProjectTable()
                }
            }
            .padding(24)
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBg)
    }
}

struct ProjectCostChart: View {
    @EnvironmentObject var store: MetricsStore

    var items: [ProjectStats] { Array(store.filteredSortedProjects.prefix(8)) }
    var maxCost: Double { items.map(\.estimatedCostUSD).max() ?? 1 }

    var body: some View {
        Chart(items) { proj in
            BarMark(
                x: .value("Cost", proj.estimatedCostUSD),
                y: .value("Project", proj.project)
            )
            .foregroundStyle(
                proj.estimatedCostUSD == maxCost
                ? Color.appAccent
                : Color.appAccent.opacity(0.55)
            )
            .cornerRadius(3)
        }
        .chartXAxis {
            AxisMarks { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.appBorder)
                AxisValueLabel {
                    if let n = v.as(Double.self) {
                        Text(formatCost(n)).font(.system(size: 10)).foregroundStyle(Color.appTextSecondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel().font(.system(size: 11)).foregroundStyle(Color.appTextPrimary)
            }
        }
        .chartPlotStyle { $0.background(Color.clear) }
    }
}

enum ProjectSortKey { case name, messages, output, cost, web, aiPct }

struct ProjectTable: View {
    @EnvironmentObject var store: MetricsStore
    @State private var sortKey: ProjectSortKey = .cost
    @State private var sortAsc: Bool = false

    var sorted: [ProjectStats] {
        let base = store.filteredSortedProjects
        switch sortKey {
        case .name:     return base.sorted { sortAsc ? $0.project < $1.project : $0.project > $1.project }
        case .messages: return base.sorted { sortAsc ? $0.messageCount < $1.messageCount : $0.messageCount > $1.messageCount }
        case .output:   return base.sorted { sortAsc ? $0.outputTokens < $1.outputTokens : $0.outputTokens > $1.outputTokens }
        case .cost:     return sortAsc ? base.reversed() : base
        case .web:      return base.sorted { sortAsc ? $0.webSearchRequests < $1.webSearchRequests : $0.webSearchRequests > $1.webSearchRequests }
        case .aiPct:    return base.sorted { sortAsc ? $0.aiCodePct < $1.aiCodePct : $0.aiCodePct > $1.aiCodePct }
        }
    }

    private var chevron: some View {
        Image(systemName: sortAsc ? "chevron.up" : "chevron.down")
            .font(.system(size: 7))
    }

    func colHeader(_ label: String, key: ProjectSortKey, width: CGFloat, align: Alignment = .trailing) -> some View {
        Button {
            if sortKey == key { sortAsc.toggle() } else { sortKey = key; sortAsc = false }
        } label: {
            HStack(spacing: 2) {
                if align == .leading {
                    Text(label)
                    if sortKey == key { chevron }
                    Spacer()
                } else {
                    Spacer()
                    if sortKey == key { chevron }
                    Text(label)
                }
            }
            .frame(width: width, alignment: align)
        }
        .buttonStyle(.plain)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(sortKey == key ? Color.appAccent : Color.appTextTertiary)
        .tracking(0.4)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                colHeader("PROJECT", key: .name, width: .infinity, align: .leading)
                colHeader("MSG", key: .messages, width: 48)
                colHeader("OUTPUT", key: .output, width: 70)
                colHeader("COST", key: .cost, width: 72)
                colHeader("WEB", key: .web, width: 36)
                colHeader("AI LINES", key: .aiPct, width: 68)
                colHeader("% AI", key: .aiPct, width: 48)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Color.appBorder.frame(height: 1)

            ForEach(sorted) { proj in
                HStack {
                    Text(proj.project)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appTextPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                    Text("\(proj.messageCount)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.appTextSecondary)
                        .frame(width: 48, alignment: .trailing)
                    Text(formatTokens(proj.outputTokens))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.appTextPrimary)
                        .frame(width: 70, alignment: .trailing)
                    Text(formatCost(proj.estimatedCostUSD))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.appAccent)
                        .frame(width: 72, alignment: .trailing)
                    Text(proj.webSearchRequests > 0 ? "\(proj.webSearchRequests)" : "—")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.appTextTertiary)
                        .frame(width: 36, alignment: .trailing)
                    Text(proj.aiLinesWritten > 0 ? formatTokens(proj.aiLinesWritten) : "—")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.appTextSecondary)
                        .frame(width: 68, alignment: .trailing)
                    Text(proj.gitLinesAdded > 0 ? String(format: "%.0f%%", proj.aiCodePct * 100) : "—")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(proj.aiCodePct > 0 ? Color.appAccent : Color.appTextTertiary)
                        .frame(width: 48, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)

                Color.appBorder.opacity(0.45).frame(height: 1)
            }

            if store.filteredSortedProjects.isEmpty {
                Text("No project data available")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appTextTertiary)
                    .padding(16)
            }
        }
    }
}
