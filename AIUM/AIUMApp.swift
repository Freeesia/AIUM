import SwiftUI

@main
struct AIUMApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var dashboardViewModel = DashboardViewModel()

    init() {
        #if os(iOS)
        UsageBackgroundRefreshScheduler.shared.register()
        UsageBackgroundRefreshScheduler.shared.scheduleNextRefresh()
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            DashboardView(viewModel: dashboardViewModel)
                .frame(minWidth: 380, minHeight: 400)
        }
        .defaultSize(width: 1000, height: 720)

        Settings {
            SettingsView()
                .frame(width: 560, height: 680)
                .disabled(dashboardViewModel.isResettingCodexUsage)
        }
        #else
        WindowGroup {
            DashboardView(viewModel: dashboardViewModel)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .background else { return }
                    UsageBackgroundRefreshScheduler.shared.scheduleNextRefresh()
                }
        }
        #endif
    }
}
