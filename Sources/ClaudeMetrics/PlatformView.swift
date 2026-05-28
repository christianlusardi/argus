import SwiftUI
import Charts

struct PlatformView: View {
    @EnvironmentObject var store: MetricsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    title: "Platform KPIs",
                    subtitle: "Operational metrics · \(store.dateFilter.rawValue)"
                )

                // Row 1: cost + volume cards
                HStack(spacing: 14) {
                    MetricCard(
                        icon: "dollarsign.circle.fill",
                        iconColor: .appGold,
                        label: "Total Cost",
                        value: formatCost(store.filteredTotalCost),
                        detail: "est. period total"
                    )
                    MetricCard(
                        icon: "arrow.up.arrow.down.circle.fill",
                        iconColor: .appAccent,
                        label: "Total Requests",
                        value: "\(store.filteredTotalMessages)",
                        detail: "\(store.filteredTotalSessions) sessions"
                    )
                    MetricCard(
                        icon: "dollarsign.square.fill",
                        iconColor: .modelOpus,
                        label: "Avg Cost / Req",
                        value: formatPerRequestCost(store.filteredAvgCostPerRequest),
                        detail: "est. per message"
                    )
                    if let avg = store.filteredAvgRating {
                        MetricCard(
                            icon: "star.fill",
                            iconColor: .appGold,
                            label: "Avg Quality",
                            value: String(format: "%.1f ★", avg),
                            detail: "rated via /rate"
                        )
                    }
                    if let pct = store.filteredAICodePct {
                        MetricCard(
                            icon: "chevron.left.forwardslash.chevron.right",
                            iconColor: .modelSonnet,
                            label: "Code from AI",
                            value: String(format: "%.0f%%", pct * 100),
                            detail: "of git committed lines"
                        )
                    }
                }

                // Row 2: token cards
                HStack(spacing: 14) {
                    MetricCard(
                        icon: "arrow.down.circle.fill",
                        iconColor: .modelSonnet,
                        label: "Avg Context / Req",
                        value: formatTokens(Int(store.filteredAvgContextTokensPerRequest)),
                        detail: "input + cache tokens"
                    )
                    MetricCard(
                        icon: "arrow.up.circle.fill",
                        iconColor: .modelHaiku,
                        label: "Avg Output / Req",
                        value: formatTokens(Int(store.filteredAvgOutputTokensPerRequest)),
                        detail: "generated tokens"
                    )
                }

                // Token trend (aggregated: daily ≤14pt, weekly ≤90pt, monthly beyond)
                if store.platformChartData.count > 1 {
                    SectionCard(title: "Token Trend", icon: "chart.xyaxis.line") {
                        Chart {
                            ForEach(store.platformChartData) { pt in
                                LineMark(
                                    x: .value("Period", pt.label),
                                    y: .value("Tokens", pt.inputTokens),
                                    series: .value("Series", "Input")
                                )
                                .foregroundStyle(Color.appAccent)
                                .interpolationMethod(.catmullRom)
                                LineMark(
                                    x: .value("Period", pt.label),
                                    y: .value("Tokens", pt.outputTokens),
                                    series: .value("Series", "Output")
                                )
                                .foregroundStyle(Color.modelSonnet)
                                .interpolationMethod(.catmullRom)
                            }
                        }
                        .chartForegroundStyleScale([
                            "Input":  Color.appAccent,
                            "Output": Color.modelSonnet
                        ])
                        .chartLegend(position: .topLeading)
                        .chartXAxis {
                            AxisMarks {
                                AxisValueLabel()
                                    .foregroundStyle(Color.appTextTertiary)
                                    .font(.system(size: 9))
                            }
                        }
                        .chartYAxis {
                            AxisMarks {
                                AxisValueLabel()
                                    .foregroundStyle(Color.appTextTertiary)
                                    .font(.system(size: 9))
                            }
                        }
                        .frame(height: 180)
                    }
                }

                // Daily cost chart (uses same adaptive aggregation as Token Trend)
                if store.platformChartData.count > 1 {
                    SectionCard(title: "Daily Cost", icon: "chart.bar.fill") {
                        Chart(store.platformChartData) { pt in
                            BarMark(
                                x: .value("Period", pt.label),
                                y: .value("Cost", pt.costUSD)
                            )
                            .foregroundStyle(Color.appGold.gradient)
                            .cornerRadius(3)
                        }
                        .chartXAxis {
                            AxisMarks {
                                AxisValueLabel()
                                    .foregroundStyle(Color.appTextTertiary)
                                    .font(.system(size: 9))
                            }
                        }
                        .chartYAxis {
                            AxisMarks {
                                AxisValueLabel()
                                    .foregroundStyle(Color.appTextTertiary)
                                    .font(.system(size: 9))
                            }
                        }
                        .chartYAxisLabel("USD", alignment: .center)
                        .frame(height: 120)
                    }
                }

                // Response time
                SectionCard(title: "Response Time", icon: "timer") {
                    if store.filteredDailyResponseTimes.isEmpty {
                        Text("Response time data will appear after new conversations are recorded. Requires conversations logged after this update.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.appTextTertiary)
                            .padding(.vertical, 8)
                    } else {
                        HStack(alignment: .top, spacing: 28) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(formatResponseTime(store.filteredAvgResponseTimeSec))
                                    .font(.system(size: 40, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.appTextPrimary)
                                Text("avg response time")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.appTextSecondary)
                                Text("human message → first token")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.appTextTertiary)
                            }
                            .frame(minWidth: 150)

                            Chart(store.filteredDailyResponseTimes, id: \.date) { pt in
                                BarMark(
                                    x: .value("Date", pt.date),
                                    y: .value("Seconds", pt.avgSec)
                                )
                                .foregroundStyle(Color.appAccent.gradient)
                                .cornerRadius(3)
                            }
                            .chartXAxis {
                                AxisMarks(values: .automatic(desiredCount: 5)) {
                                    AxisValueLabel()
                                        .foregroundStyle(Color.appTextTertiary)
                                        .font(.system(size: 9))
                                }
                            }
                            .chartYAxisLabel("seconds", alignment: .center)
                            .frame(maxWidth: .infinity)
                            .frame(height: 110)
                        }
                    }
                }

                // Per-user cost + requests
                if !store.filteredAccountCosts.isEmpty {
                    SectionCard(title: "Cost per User", icon: "person.2.fill") {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Account")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Color.appTextTertiary)
                                    .tracking(0.5)
                                Spacer()
                                Text("Requests")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Color.appTextTertiary)
                                    .tracking(0.5)
                                    .frame(width: 68, alignment: .trailing)
                                Text("Total Cost")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Color.appTextTertiary)
                                    .tracking(0.5)
                                    .frame(width: 80, alignment: .trailing)
                            }
                            .padding(.bottom, 10)

                            ForEach(store.filteredAccountCosts) { acct in
                                HStack(spacing: 10) {
                                    Image(systemName: acct.authType == "oauth"
                                          ? "person.crop.circle.fill" : "key.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(acct.authType == "oauth"
                                                         ? Color.appAccent : Color.orange)
                                        .frame(width: 16)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(acct.label)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(Color.appTextPrimary)
                                        if !acct.subtitle.isEmpty {
                                            Text(acct.subtitle)
                                                .font(.system(size: 10))
                                                .foregroundStyle(Color.appTextTertiary)
                                        }
                                    }
                                    Spacer()
                                    Text("\(acct.messageCount)")
                                        .font(.system(size: 12, design: .rounded))
                                        .foregroundStyle(Color.appTextSecondary)
                                        .frame(width: 68, alignment: .trailing)
                                    Text(formatCost(acct.costUSD))
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color.appTextPrimary)
                                        .frame(width: 80, alignment: .trailing)
                                }
                                .padding(.vertical, 8)

                                if acct.id != store.filteredAccountCosts.last?.id {
                                    Divider()
                                        .background(Color.appBorder)
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

private func formatResponseTime(_ sec: Double?) -> String {
    guard let sec = sec, sec > 0 else { return "—" }
    if sec < 60 { return String(format: "%.1fs", sec) }
    let m = Int(sec) / 60; let s = Int(sec) % 60
    return "\(m)m \(s)s"
}

private func formatPerRequestCost(_ usd: Double) -> String {
    if usd <= 0 { return "$0" }
    if usd >= 0.01 { return formatCost(usd) }
    if usd >= 0.001 { return String(format: "$%.4f", usd) }
    return String(format: "$%.5f", usd)
}
