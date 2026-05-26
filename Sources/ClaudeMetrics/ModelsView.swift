import SwiftUI
import Charts

struct ModelsView: View {
    @EnvironmentObject var store: MetricsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: "Models", subtitle: "Token breakdown and cost per model")

                VStack(spacing: 12) {
                    ForEach(store.filteredSortedModels, id: \.model) { entry in
                        ModelStatCard(model: entry.model, stats: entry.stats)
                    }
                }

                if store.filteredTotalCost > 0 {
                    SectionCard(title: "Cost Breakdown", icon: "dollarsign.circle") {
                        CostPieChart()
                            .frame(height: 220)
                    }
                }

                if store.filteredDailyCostData.count > 1 {
                    SectionCard(title: "Daily Cost Trend", icon: "chart.line.uptrend.xyaxis") {
                        DailyCostTrendChart()
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

struct ModelStatCard: View {
    let model: String
    let stats: ModelTokenStats

    private var color: Color  { Color.forModel(model) }
    private var cost: Double  { ModelPricingTable.price(for: model).cost(for: stats) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Title row
            HStack {
                HStack(spacing: 9) {
                    Circle().fill(color).frame(width: 9, height: 9)
                    Text(modelDisplayName(model))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.appTextPrimary)
                }
                Spacer()
                Text(formatCost(cost))
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
            }

            // Token stats
            HStack(spacing: 0) {
                TokenStat(label: "Input",       value: formatTokens(stats.inputTokens),               color: color.opacity(0.75))
                Divider().frame(height: 36).overlay(Color.appBorder)
                TokenStat(label: "Output",      value: formatTokens(stats.outputTokens),              color: color)
                Divider().frame(height: 36).overlay(Color.appBorder)
                TokenStat(label: "Cache Read",  value: formatTokens(stats.cacheReadInputTokens),      color: color.opacity(0.5))
                Divider().frame(height: 36).overlay(Color.appBorder)
                TokenStat(label: "Cache Write", value: formatTokens(stats.cacheCreationInputTokens),  color: color.opacity(0.4))
            }

            // Proportional token bar
            ProportionalBar(stats: stats, color: color)
                .frame(height: 6)
        }
        .padding(18)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
    }
}

struct ProportionalBar: View {
    let stats: ModelTokenStats
    let color: Color

    private var total: Double {
        Double(stats.inputTokens + stats.outputTokens + stats.cacheReadInputTokens + stats.cacheCreationInputTokens)
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                let w = geo.size.width
                let t = max(total, 1)
                let inFrac    = Double(stats.inputTokens)               / t
                let outFrac   = Double(stats.outputTokens)              / t
                let rdFrac    = Double(stats.cacheReadInputTokens)      / t

                RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.75)).frame(width: w * inFrac)
                RoundedRectangle(cornerRadius: 2).fill(color)              .frame(width: w * outFrac)
                RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.5)) .frame(width: w * rdFrac)
                RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.3)) .frame(maxWidth: .infinity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

struct DailyCostTrendChart: View {
    @EnvironmentObject var store: MetricsStore

    struct CostPoint: Identifiable {
        let id: String; let date: Date; let cost: Double
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
                    colors: [Color.appGold.opacity(0.30), Color.appGold.opacity(0.03)],
                    startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("Date", p.date), y: .value("Cost", p.cost))
                .foregroundStyle(Color.appGold)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
        }
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

struct CostPieChart: View {
    @EnvironmentObject var store: MetricsStore

    struct Slice: Identifiable {
        let id: String
        let name: String
        let cost: Double
        let color: Color
    }

    var slices: [Slice] {
        store.filteredModelCosts.map {
            Slice(id: $0.model, name: modelDisplayName($0.model), cost: $0.cost, color: Color.forModel($0.model))
        }
    }

    var body: some View {
        Chart(slices) { s in
            SectorMark(
                angle: .value("Cost", s.cost),
                innerRadius: .ratio(0.54),
                angularInset: 2
            )
            .foregroundStyle(s.color)
        }
        .chartLegend(position: .trailing, alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(slices) { s in
                    HStack(spacing: 8) {
                        Circle().fill(s.color).frame(width: 8, height: 8)
                        Text(s.name)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.appTextSecondary)
                        Spacer()
                        Text(formatCost(s.cost))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.appTextPrimary)
                    }
                    .frame(minWidth: 200)
                }
            }
        }
        .chartPlotStyle { $0.background(Color.clear) }
    }
}
