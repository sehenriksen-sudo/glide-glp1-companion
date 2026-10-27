// LiveActivityManager.swift
//
// Main app target only — manages ActivityKit lifecycle.
// Inject into the environment alongside SubscriptionManager and HealthKitManager.

import ActivityKit
import SwiftUI
import Observation

// MARK: - Live Activity Manager

@Observable
@MainActor
final class LiveActivityManager {

    // ── Public state ──────────────────────────────────────────────────────
    private(set) var isActivityRunning: Bool = false
    private(set) var errorMessage:      String?

    // Active activity handle — nil when no activity is live
    private var activity: Activity<MedicationActivityAttributes>?

    // MARK: Availability

    var areActivitiesSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: Start

    /// Start a new Live Activity for the given injection log.
    /// Ends any currently running activity first (only one makes sense).
    func start(for log: MedicationLog) async {
        guard areActivitiesSupported else { return }

        // End any existing activity cleanly
        await endAll(dismissalPolicy: .immediate)

        let med  = log.asMedication()
        let attrs = MedicationActivityAttributes(
            medicationType: log.medicationType,
            doseMg:         log.doseMg,
            shotDate:       log.date,
            halfLifeDays:   med.halfLifeDays
        )
        let state   = attrs.currentContentState()
        let content = ActivityContent(
            state:     state,
            staleDate: state.staleDate
        )

        do {
            activity = try Activity.request(
                attributes: attrs,
                content:    content,
                pushType:   nil   // client-only updates (no APNs)
            )
            isActivityRunning = true
            errorMessage      = nil
        } catch {
            errorMessage      = "Could not start Live Activity: \(error.localizedDescription)"
            isActivityRunning = false
        }
    }

    // MARK: Update

    /// Push a fresh ContentState to the running activity.
    /// Call this when the app returns to the foreground and on a 30-min background refresh.
    func update() async {
        guard let activity else { return }

        // Re-derive attributes from the running activity
        let attrs   = activity.attributes
        let state   = attrs.currentContentState()
        let content = ActivityContent(
            state:        state,
            staleDate:    state.staleDate,
            relevantDate: .now
        )

        await activity.update(content)
        isActivityRunning = activity.activityState == .active
    }

    // MARK: End

    /// End the running activity with an optional final state snapshot.
    func end(after delay: TimeInterval = 0) async {
        guard let activity else { return }

        let attrs   = activity.attributes
        let state   = attrs.currentContentState()
        let content = ActivityContent(state: state, staleDate: .now)

        let policy: ActivityUIDismissalPolicy = delay > 0
            ? .after(Date.now.addingTimeInterval(delay))
            : .immediate

        await activity.end(content, dismissalPolicy: policy)
        self.activity     = nil
        isActivityRunning = false
    }

    /// End every running Glide Live Activity (e.g. when a new shot is logged).
    func endAll(dismissalPolicy: ActivityUIDismissalPolicy = .after(Date.now.addingTimeInterval(5))) async {
        for runningActivity in Activity<MedicationActivityAttributes>.activities {
            let attrs   = runningActivity.attributes
            let state   = attrs.currentContentState()
            let content = ActivityContent(state: state, staleDate: .now)
            await runningActivity.end(content, dismissalPolicy: dismissalPolicy)
        }
        activity          = nil
        isActivityRunning = false
    }

    // MARK: Restore on launch

    /// Re-attach to any activity that was already running before the app restarted.
    func restoreIfNeeded() {
        if let existing = Activity<MedicationActivityAttributes>.activities.first {
            activity          = existing
            isActivityRunning = existing.activityState == .active
        }
    }

    // MARK: Schedule end at next dose date

    /// End the activity automatically at the 7-day mark.
    /// Call once after start, passing the nextDoseDate from the content state.
    func scheduleEnd(at date: Date) {
        Task {
            // Sleep until 5 minutes after the next dose date, then end
            let delay = max(0, date.addingTimeInterval(5 * 60).timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(delay))
            await end(after: 30)  // keep on lock screen 30 s after expiry
        }
    }
}
