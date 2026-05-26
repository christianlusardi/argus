import SwiftUI
import AppKit

@main
struct ClaudeMetricsApp: App {
    @StateObject private var store = MetricsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .frame(minWidth: 900, idealWidth: 1100, minHeight: 600, idealHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appSettings) {
                Button("Refresh Metrics") {
                    store.loadData()
                }
                .keyboardShortcut("r", modifiers: .command)
                Button("Export CSV") {
                    store.exportCSV()
                }
                .keyboardShortcut("e", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarView().environmentObject(store)
        } label: {
            Label(store.menuBarLabel, systemImage: "waveform.circle.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarView: View {
    @EnvironmentObject var store: MetricsStore

    private var todayCost: Double {
        let start = Calendar.current.startOfDay(for: Date())
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        return (store.stats?.dailyTotals ?? [])
            .filter { (fmt.date(from: $0.date) ?? .distantPast) >= start }
            .reduce(0.0) { $0 + $1.estimatedCostUSD }
    }

    private var todayMessages: Int {
        let start = Calendar.current.startOfDay(for: Date())
        return store.recentActivity
            .filter { $0.dateValue >= start }
            .reduce(0) { $0 + $1.messageCount }
    }

    private var weekCost: Double {
        let cut = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        return (store.stats?.dailyTotals ?? [])
            .filter { (fmt.date(from: $0.date) ?? .distantPast) >= cut }
            .reduce(0.0) { $0 + $1.estimatedCostUSD }
    }

    private var alertColor: Color {
        let threshold = store.alertThreshold
        guard threshold > 0 else { return .clear }
        let ratio = todayCost / threshold
        if ratio >= 1.0 { return Color(red: 0.9, green: 0.3, blue: 0.3) }
        if ratio >= 0.8 { return Color(red: 0.95, green: 0.65, blue: 0.1) }
        return Color(red: 0.3, green: 0.9, blue: 0.4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .foregroundStyle(Color.appAccent)
                Text("ArgusAI")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.appTextPrimary)
                Spacer()
                if store.alertThreshold > 0 {
                    Circle()
                        .fill(alertColor)
                        .frame(width: 8, height: 8)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Today")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appTextSecondary)
                    Spacer()
                    Text("\(formatCost(todayCost))  \(todayMessages) msgs")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.appTextPrimary)
                }
                HStack {
                    Text("This week")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appTextSecondary)
                    Spacer()
                    Text(formatCost(weekCost))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.appTextPrimary)
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button("Open ArgusAI") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.appAccent)

                Spacer()

                Button("Refresh") {
                    store.loadData()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.appTextSecondary)
            }
        }
        .padding(16)
        .frame(width: 260)
        .background(Color.appBg)
        .foregroundStyle(Color.appTextPrimary)
    }
}
