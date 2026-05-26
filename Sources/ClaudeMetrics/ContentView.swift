import SwiftUI
import AppKit

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let w = view.window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility             = .hidden
            w.styleMask.insert(.fullSizeContentView)
            w.isMovableByWindowBackground = true
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

enum NavSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case models   = "Models"
    case activity = "Activity"
    case schedule = "Schedule"
    case projects = "Projects"
    case sessions = "Sessions"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "chart.bar.xaxis.ascending.badge.clock"
        case .models:   return "cpu"
        case .activity: return "calendar.day.timeline.left"
        case .schedule: return "clock.fill"
        case .projects: return "folder.badge.gear"
        case .sessions: return "bubble.left.and.bubble.right"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: MetricsStore
    @State private var selected: NavSection = .overview

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selected: $selected)
                .frame(width: 196)

            Color.appBorder
                .frame(width: 1)

            ZStack {
                Color.appBg.ignoresSafeArea()
                Group {
                    if store.isLoading {
                        LoadingView()
                    } else if let err = store.error {
                        ErrorView(message: err)
                    } else {
                        switch selected {
                        case .overview: OverviewView()
                        case .models:   ModelsView()
                        case .activity: ActivityView()
                        case .schedule: ScheduleView()
                        case .projects: ProjectsView()
                        case .sessions: SessionsView()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.appBg)
        .ignoresSafeArea()
        .background { WindowConfigurator() }
    }
}

struct SidebarView: View {
    @Binding var selected: NavSection
    @EnvironmentObject var store: MetricsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.appAccent.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.appAccent)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Claude")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.appTextPrimary)
                    Text("Metrics")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.appAccent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 38)
            .padding(.bottom, 20)

            // Nav
            VStack(spacing: 2) {
                ForEach(NavSection.allCases) { section in
                    NavButton(section: section, isSelected: selected == section) {
                        withAnimation(.easeInOut(duration: 0.15)) { selected = section }
                    }
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            // Daily limit
            VStack(alignment: .leading, spacing: 6) {
                Color.appBorder.frame(height: 1)
                Text("DAILY LIMIT")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.appTextTertiary)
                    .tracking(0.5)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                TextField("$0.00", value: $store.alertThreshold, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }

            // Date filter
            VStack(alignment: .leading, spacing: 6) {
                Color.appBorder.frame(height: 1)
                Text("TIME RANGE")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.appTextTertiary)
                    .tracking(0.5)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                Picker("", selection: $store.dateFilter) {
                    ForEach(DateFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }

            // Footer
            VStack(alignment: .leading, spacing: 0) {
                Color.appBorder.frame(height: 1)

                if let date = store.lastRefresh {
                    HStack(spacing: 6) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text("Updated \(date, style: .relative) ago")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.appTextTertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }

                Button {
                    store.loadData()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                        Text("Refresh")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(Color.appTextSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 8)
            }
        }
        .background(Color.appSidebar)
    }
}

struct NavButton: View {
    let section: NavSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: section.icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.appAccent : Color.appTextSecondary)
                Text(section.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.appTextPrimary : Color.appTextSecondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.appAccent.opacity(0.13) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.appAccent.opacity(0.25) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
