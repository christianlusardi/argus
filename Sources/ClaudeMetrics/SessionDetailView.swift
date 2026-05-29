import SwiftUI

struct SessionDetailView: View {
    let session: SessionSummary
    @EnvironmentObject var store: MetricsStore
    @Environment(\.dismiss) var dismiss

    @State private var messages: [SessionMessageDetail] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.project)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.appTextPrimary)
                    Text(session.sessionId)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.appTextTertiary)
                }
                Spacer()
                // Summary pills
                HStack(spacing: 8) {
                    pill(formatCost(session.costUSD), color: Color.appGold)
                    pill("\(session.messageCount) msgs", color: Color.appAccent)
                    pill(modelDisplayName(session.topModel), color: Color.forModel(session.topModel))
                }
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.appTextTertiary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.appSurface)

            Color.appBorder.frame(height: 1)

            if messages.isEmpty {
                VStack {
                    ProgressView()
                    Text("Loading messages…")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appTextSecondary)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBg)
            } else {
                // Column headers
                HStack(spacing: 0) {
                    Text("TIME").frame(width: 70, alignment: .leading)
                    Text("MODEL").frame(width: 90, alignment: .leading)
                    Text("INPUT").frame(width: 70, alignment: .trailing)
                    Text("OUTPUT").frame(width: 70, alignment: .trailing)
                    Text("CACHE R").frame(width: 70, alignment: .trailing)
                    Text("CACHE W").frame(width: 70, alignment: .trailing)
                    Text("COST").frame(width: 70, alignment: .trailing)
                    Text("AI LINES").frame(width: 70, alignment: .trailing)
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.appTextTertiary)
                .tracking(0.5)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.appSurface)

                Color.appBorder.frame(height: 1)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(messages) { msg in
                            MessageRow(msg: msg)
                            Color.appBorder.frame(height: 1).opacity(0.4)
                        }
                    }
                }
                .background(Color.appBg)

                // Footer totals
                Color.appBorder.frame(height: 1)
                HStack(spacing: 0) {
                    Text("TOTAL").frame(width: 70, alignment: .leading)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.appTextSecondary)
                    Spacer().frame(width: 90)
                    Text(formatTokens(messages.reduce(0) { $0 + $1.inputTokens }))
                        .frame(width: 70, alignment: .trailing)
                    Text(formatTokens(messages.reduce(0) { $0 + $1.outputTokens }))
                        .frame(width: 70, alignment: .trailing)
                    Text(formatTokens(messages.reduce(0) { $0 + $1.cacheReadTokens }))
                        .frame(width: 70, alignment: .trailing)
                    Text(formatTokens(messages.reduce(0) { $0 + $1.cacheCreateTokens }))
                        .frame(width: 70, alignment: .trailing)
                    Text(formatCost(messages.reduce(0) { $0 + $1.costUSD }))
                        .frame(width: 70, alignment: .trailing)
                        .foregroundStyle(Color.appGold)
                    Text("\(messages.reduce(0) { $0 + $1.aiLines })")
                        .frame(width: 70, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.appTextPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.appSurface)
            }
        }
        .frame(width: 640, height: 480)
        .background(Color.appBg)
        .onAppear { messages = store.loadSessionMessages(sessionId: session.sessionId) }
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct MessageRow: View {
    let msg: SessionMessageDetail

    var body: some View {
        HStack(spacing: 0) {
            Text(msg.formattedTime)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.appTextTertiary)
                .frame(width: 70, alignment: .leading)

            Text(modelDisplayName(msg.model))
                .font(.system(size: 10))
                .foregroundStyle(Color.forModel(msg.model))
                .lineLimit(1)
                .frame(width: 90, alignment: .leading)

            Text(formatTokens(msg.inputTokens))
                .frame(width: 70, alignment: .trailing)
            Text(formatTokens(msg.outputTokens))
                .frame(width: 70, alignment: .trailing)
            Text(formatTokens(msg.cacheReadTokens))
                .frame(width: 70, alignment: .trailing)
            Text(formatTokens(msg.cacheCreateTokens))
                .frame(width: 70, alignment: .trailing)
            Text(formatCost(msg.costUSD))
                .frame(width: 70, alignment: .trailing)
                .foregroundStyle(msg.costUSD > 0.01 ? Color.appGold : Color.appTextSecondary)
            Text(msg.aiLines > 0 ? "\(msg.aiLines)" : "·")
                .frame(width: 70, alignment: .trailing)
                .foregroundStyle(msg.aiLines > 0 ? Color.appAccent : Color.appTextTertiary)
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(Color.appTextSecondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
    }
}
