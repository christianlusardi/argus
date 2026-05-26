import SwiftUI

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
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appSettings) {
                Button("Refresh Metrics") {
                    store.loadData()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
