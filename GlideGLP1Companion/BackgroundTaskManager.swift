// BackgroundTaskManager.swift
//
// BGTaskScheduler integration — keeps the widget and Live Activity
// fresh even when the app hasn't been opened.
//
// Info.plist — add before shipping:
//   Key:   BGTaskSchedulerPermittedIdentifiers
//   Value: (Array)
//     - com.glide.refresh        ← BGAppRefreshTask
//     - com.glide.healthkit      ← BGProcessingTask

import BackgroundTasks
import SwiftData
import WidgetKit
import Observation

// MARK: - Task identifiers

enum BGTaskID {
    static let appRefresh   = "com.glide.refresh"
    static let healthImport = "com.glide.healthkit"
}

// MARK: - BackgroundTaskManager

@Observable
@MainActor
final class BackgroundTaskManager {

    private(set) var lastRefreshDate: Date?
    private(set) var lastHealthImportDate: Date?

    // Injected by GlideApp — allows background tasks to reach other managers
    var liveActivityManager: LiveActivityManager?
    var healthKitManager:    HealthKitManager?
    var modelContainer:      ModelContainer?

    // MARK: Registration — call once from GlideApp.init()

    /// Registers both task handlers. Must be called before the first runloop iteration.
    nonisolated func registerHandlers() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: BGTaskID.appRefresh,   using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            Task { @MainActor in await self.handleAppRefresh(task: task) }
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: BGTaskID.healthImport, using: nil) { task in
            guard let task = task as? BGProcessingTask else { return }
            Task { @MainActor in await self.handleHealthImport(task: task) }
        }
    }

    // MARK: Scheduling — call from applicationDidEnterBackground / scenePhase

    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: BGTaskID.appRefresh)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // no sooner than 15 min
        try? BGTaskScheduler.shared.submit(request)
    }

    func scheduleHealthImport() {
        let request = BGProcessingTaskRequest(identifier: BGTaskID.healthImport)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower       = false
        request.earliestBeginDate           = Date(timeIntervalSinceNow: 60 * 60) // 1 hour
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: Handlers

    private func handleAppRefresh(task: BGAppRefreshTask) async {
        // Schedule the next refresh before doing work
        scheduleAppRefresh()

        task.expirationHandler = { task.setTaskCompleted(success: false) }

        // 1. Update Live Activity concentration
        await liveActivityManager?.update()

        // 2. Reload widget timelines
        WidgetCenter.shared.reloadAllTimelines()

        lastRefreshDate = .now
        task.setTaskCompleted(success: true)
    }

    private func handleHealthImport(task: BGProcessingTask) async {
        scheduleHealthImport()

        task.expirationHandler = { task.setTaskCompleted(success: false) }

        guard let hk = healthKitManager,
              let container = modelContainer else {
            task.setTaskCompleted(success: false)
            return
        }

        let context = container.mainContext
        await hk.importRecentWorkouts(days: 7, into: context)

        lastHealthImportDate = .now
        task.setTaskCompleted(success: true)
    }
}
