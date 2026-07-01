import BackgroundTasks
import Foundation
import OSLog

final class UsageBackgroundRefreshScheduler {
    static let shared = UsageBackgroundRefreshScheduler()
    static let taskIdentifier = "com.studiofreesia.aium.usage-refresh"
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.studiofreesia.aium",
        category: "BackgroundRefresh"
    )

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
        if !isRegistered {
            Self.logger.error("Failed to register background refresh task")
        }
    }

    func scheduleNextRefresh() {
        guard isRegistered, !Self.isRunningTests else { return }

        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(
            TimeInterval(Self.currentIntervalMinutes() * 60)
        )

        do {
            try BGTaskScheduler.shared.submit(request)
            Self.logger.debug("Scheduled background refresh")
        } catch {
            Self.logger.error("Failed to schedule background refresh: \(error.localizedDescription)")
        }
    }

    private func handle(_ task: BGTask) {
        guard let task = task as? BGAppRefreshTask else {
            task.setTaskCompleted(success: false)
            return
        }

        // Schedule first so the refresh chain survives expiration or termination.
        scheduleNextRefresh()
        Self.logger.info("Background usage refresh started")

        let refreshTask = Task {
            let result = await UsageRefreshService().refreshUsage()
            let success = result.isSuccess && !Task.isCancelled
            if let errorMessage = result.errorMessage {
                Self.logger.error("Background usage refresh failed: \(errorMessage)")
            } else {
                Self.logger.info("Background usage refresh completed")
            }
            task.setTaskCompleted(success: success)
        }

        task.expirationHandler = {
            Self.logger.error("Background usage refresh expired")
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
