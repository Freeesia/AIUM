import SwiftUI

@main
struct AIUMApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UsageBackgroundRefreshScheduler.shared.register()
        UsageBackgroundRefreshScheduler.shared.scheduleNextRefresh()
    }

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .background else { return }
                    UsageBackgroundRefreshScheduler.shared.scheduleNextRefresh()
                }
        }
    }
}
