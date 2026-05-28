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
    case platform = "Platform"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "chart.bar.xaxis.ascending.badge.clock"
        case .models:   return "cpu"
        case .activity: return "calendar.day.timeline.left"
        case .schedule: return "clock.fill"
        case .projects: return "folder.badge.gear"
        case .sessions: return "bubble.left.and.bubble.right"
        case .platform: return "gauge.medium"
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
                        case .platform: PlatformView()
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
            .padding(.bottom, 12)

            // Account chip
            if let acct = store.currentAccount {
                HStack(spacing: 6) {
                    Image(systemName: acct.isOAuth ? "person.crop.circle.fill" : "key.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(acct.isOAuth ? Color.appAccent : Color.orange)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(acct.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.appTextPrimary)
                            .lineLimit(1)
                        if !acct.subtitle.isEmpty {
                            Text(acct.subtitle)
                                .font(.system(size: 9))
                                .foregroundStyle(Color.appTextTertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(acct.isOAuth ? Color.appAccent.opacity(0.08) : Color.orange.opacity(0.08))
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }

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
                Picker("", selection: Binding(
                    get: { store.dateFilter == .custom ? DateFilter.all : store.dateFilter },
                    set: { store.dateFilter = $0 }
                )) {
                    ForEach(DateFilter.presets, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)

                // Custom date range
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Da")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.appTextSecondary)
                            .frame(width: 20, alignment: .trailing)
                        DatePicker("", selection: Binding(
                            get: { store.customStartDate },
                            set: { store.customStartDate = $0; store.dateFilter = .custom }
                        ), in: ...store.customEndDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 6) {
                        Text("Al")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.appTextSecondary)
                            .frame(width: 20, alignment: .trailing)
                        DatePicker("", selection: Binding(
                            get: { store.customEndDate },
                            set: { store.customEndDate = $0; store.dateFilter = .custom }
                        ), in: store.customStartDate..., displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }

            // Account filter (only shown when multiple accounts known)
            if store.knownAccounts.count > 1 {
                VStack(alignment: .leading, spacing: 4) {
                    Color.appBorder.frame(height: 1)
                    Text("ACCOUNT")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.appTextTertiary)
                        .tracking(0.5)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    AccountFilterButton(label: "All Accounts", icon: "person.2.fill",
                                        isSelected: store.accountFilter == nil) {
                        store.accountFilter = nil
                    }
                    ForEach(store.knownAccounts) { acct in
                        AccountFilterButton(
                            label: acct.label,
                            icon: acct.isOAuth ? "person.crop.circle" : "key.fill",
                            isSelected: store.accountFilter == acct.accountUuid
                        ) {
                            store.accountFilter = acct.accountUuid
                        }
                    }
                }
                .padding(.bottom, 6)
            }

            // Project filter (only shown when multiple projects known)
            if store.knownProjects.count > 1 {
                VStack(alignment: .leading, spacing: 4) {
                    Color.appBorder.frame(height: 1)
                    Text("PROJECT")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.appTextTertiary)
                        .tracking(0.5)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    AccountFilterButton(label: "All Projects", icon: "folder.fill",
                                        isSelected: store.projectFilter == nil) {
                        store.projectFilter = nil
                    }
                    ForEach(store.knownProjects, id: \.self) { proj in
                        AccountFilterButton(
                            label: proj,
                            icon: "folder",
                            isSelected: store.projectFilter == proj
                        ) {
                            store.projectFilter = proj
                        }
                    }
                }
                .padding(.bottom, 6)
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

struct AccountFilterButton: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .frame(width: 14)
                    .foregroundStyle(isSelected ? Color.appAccent : Color.appTextSecondary)
                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.appTextPrimary : Color.appTextSecondary)
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Circle().fill(Color.appAccent).frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.appAccent.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
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
