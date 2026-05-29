import SwiftUI

struct SessionsView: View {
    @EnvironmentObject var store: MetricsStore

    @State private var sortKey: SessionSortKey = .date
    @State private var sortAsc: Bool = false
    @State private var selectedSession: SessionSummary? = nil

    enum SessionSortKey { case date, messages, output, cost }

    var sortedSessions: [SessionSummary] {
        let base = store.visibleSessions
        switch sortKey {
        case .date:     return sortAsc ? base : base.reversed()
        case .messages: return base.sorted { sortAsc ? $0.messageCount < $1.messageCount : $0.messageCount > $1.messageCount }
        case .output:   return base.sorted { sortAsc ? $0.outputTokens < $1.outputTokens : $0.outputTokens > $1.outputTokens }
        case .cost:     return base.sorted { sortAsc ? $0.costUSD < $1.costUSD : $0.costUSD > $1.costUSD }
        }
    }

    func sortHeader(_ label: String, key: SessionSortKey, width: CGFloat, align: Alignment = .trailing) -> some View {
        Button {
            if sortKey == key { sortAsc.toggle() } else { sortKey = key; sortAsc = false }
        } label: {
            HStack(spacing: 2) {
                if align == .leading { Text(label); Spacer() }
                if sortKey == key {
                    Image(systemName: sortAsc ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                }
                if align == .trailing { Spacer(); Text(label) }
            }
            .frame(width: width, alignment: align)
        }
        .buttonStyle(.plain)
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(sortKey == key ? Color.appAccent : Color.appTextTertiary)
        .tracking(0.5)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    title: "Sessions",
                    subtitle: "\(store.totalFilteredSessionCount) sessions in selected period"
                )

                SectionCard(title: "All Sessions", icon: "bubble.left.and.bubble.right") {
                    TextField("Search by project or session ID…", text: $store.sessionSearchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appTextPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.appSurface.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(Color.appBorder, lineWidth: 1)
                        )
                        .padding(.bottom, 12)

                    if store.totalFilteredSessionCount == 0 {
                        Text("No sessions in selected period")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.appTextSecondary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 0) {
                            HStack(spacing: 8) {
                                Text("SESSION")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Color.appTextTertiary)
                                    .tracking(0.5)
                                    .frame(width: 80, alignment: .leading)
                                Text("PROJECT")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Color.appTextTertiary)
                                    .tracking(0.5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                sortHeader("DATE", key: .date, width: 90, align: .leading)
                                sortHeader("MSGS", key: .messages, width: 50, align: .trailing)
                                sortHeader("OUTPUT", key: .output, width: 70, align: .trailing)
                                sortHeader("COST", key: .cost, width: 70, align: .trailing)
                                Text("MODEL")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Color.appTextTertiary)
                                    .tracking(0.5)
                                    .frame(width: 90, alignment: .leading)
                                Text("RATING")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Color.appTextTertiary)
                                    .tracking(0.5)
                                    .frame(width: 60, alignment: .center)
                            }
                            .padding(.bottom, 8)

                            Color.appBorder.frame(height: 1)

                            ForEach(sortedSessions) { session in
                                Button { selectedSession = session } label: {
                                    SessionRow(session: session)
                                }
                                .buttonStyle(.plain)
                                Color.appBorder.frame(height: 1).opacity(0.5)
                            }

                            if store.visibleSessions.count < store.totalFilteredSessionCount {
                                Button("Load \(min(100, store.totalFilteredSessionCount - store.visibleSessions.count)) more sessions") {
                                    store.sessionDisplayLimit += 100
                                }
                                .font(.system(size: 12))
                                .foregroundStyle(Color.appAccent)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBg)
        .sheet(item: $selectedSession) { session in
            SessionDetailView(session: session).environmentObject(store)
        }
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
        .contentShape(Rectangle())
    }
}

private func ratingStars(_ rating: Int?) -> String {
    guard let r = rating, r >= 1, r <= 5 else { return "·" }
    return String(repeating: "★", count: r) + String(repeating: "☆", count: 5 - r)
}
