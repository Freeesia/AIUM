import BackgroundTasks
import Foundation

final class UsageBackgroundRefreshScheduler {
    static let shared = UsageBackgroundRefreshScheduler()
    static let taskIdentifier = "com.studiofreesia.aium.usage-refresh"

    private var isRegistered = false

    private init() {}

    func register() {
        guard !isRegistered else { return }

        isRegistered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            self.handle(task)
        }
    }

    func scheduleNextRefresh() {
        guard isRegistered, !Self.isRunningTests else { return }

        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)

        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(
            TimeInterval(Self.currentIntervalMinutes() * 60)
        )

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("[AIUM][BackgroundRefresh] Failed to schedule usage refresh: \(error.localizedDescription)")
            #endif
        }
    }

    private func handle(_ task: BGTask) {
        guard let task = task as? BGAppRefreshTask else {
            task.setTaskCompleted(success: false)
            return
        }

        let refreshTask = Task {
            let result = await UsageRefreshService().refreshUsage()
            scheduleNextRefresh()
            task.setTaskCompleted(success: result.isSuccess)
        }

        task.expirationHandler = {
            refreshTask.cancel()
        }
    }

    private static func currentIntervalMinutes() -> Int {
        UsageRefreshSchedule.intervalMinutes(
            for: UsageRefreshSchedule.refreshSetting(),
            automaticIntervalMinutes: UsageRefreshSchedule.storedAutomaticIntervalMinutes()
        )
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}
