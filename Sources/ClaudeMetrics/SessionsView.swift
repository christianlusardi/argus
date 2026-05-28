import SwiftUI

struct SessionsView: View {
    @EnvironmentObject var store: MetricsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    title: "Sessions",
                    subtitle: "\(store.filteredSessions.count) sessions in selected period"
                )

                SectionCard(title: "All Sessions", icon: "bubble.left.and.bubble.right") {
                    if store.filteredSessions.isEmpty {
                        Text("No sessions in selected period")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.appTextSecondary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 0) {
                            // Header row
                            HStack(spacing: 8) {
                                Text("SESSION")
                                    .frame(width: 80, alignment: .leading)
                                Text("PROJECT")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("DATE")
                                    .frame(width: 90, alignment: .leading)
                                Text("MSGS")
                                    .frame(width: 50, alignment: .trailing)
                                Text("OUTPUT")
                                    .frame(width: 70, alignment: .trailing)
                                Text("COST")
                                    .frame(width: 70, alignment: .trailing)
                                Text("MODEL")
                                    .frame(width: 90, alignment: .leading)
                                Text("RATING")
                                    .frame(width: 60, alignment: .center)
                            }
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.appTextTertiary)
                            .tracking(0.5)
                            .padding(.bottom, 8)

                            Color.appBorder.frame(height: 1)

                            ForEach(store.filteredSessions) { session in
                                SessionRow(session: session)
                                Color.appBorder.frame(height: 1).opacity(0.5)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBg)
    }
}

struct SessionRow: View {
    let session: SessionSummary

    var shortId: String {
        let s = session.sessionId
        return s.count > 8 ? String(s.suffix(8)) : s
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(shortId)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 80, alignment: .leading)

            Text(session.project)
                .font(.system(size: 12))
                .foregroundStyle(Color.appTextPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(session.firstDay)
                .font(.system(size: 11))
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 90, alignment: .leading)

            Text("\(session.messageCount)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.appTextPrimary)
                .frame(width: 50, alignment: .trailing)

            Text(formatTokens(session.outputTokens))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 70, alignment: .trailing)

            Text(formatCost(session.costUSD))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.appGold)
                .frame(width: 70, alignment: .trailing)

            HStack(spacing: 4) {
                Text(modelDisplayName(session.topModel))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.forModel(session.topModel))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 64, alignment: .leading)
                if session.isSubagent {
                    Text("sub")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.appBg)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.appTextSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .frame(width: 90, alignment: .leading)

            Text(ratingStars(session.rating))
                .font(.system(size: 10))
                .frame(width: 60, alignment: .center)
        }
        .padding(.vertical, 8)
    }
}

private func ratingStars(_ rating: Int?) -> String {
    guard let r = rating, r >= 1, r <= 5 else { return "·" }
    return String(repeating: "★", count: r) + String(repeating: "☆", count: 5 - r)
}
